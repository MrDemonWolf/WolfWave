//
//  DiscordRPCService+IPC.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-07-15.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import Darwin
import Foundation

extension DiscordRPCService {

    // MARK: - Connection

    /// Attempts to connect to Discord's IPC socket.
    ///
    /// Tries each candidate temp directory, and within each, tries sockets 0 through 9.
    /// Keeps the first successful connection.
    func connectIfNeeded() async {
        guard state == .disconnected else { return }
        guard !clientID.isEmpty else {
            Log.warn("DiscordRPCService: No client ID configured: skipping connection", category: "Discord")
            return
        }

        state = .connecting

        let candidates = tempDirectoryCandidates()
        guard !candidates.isEmpty else {
            Log.error("DiscordRPCService: Cannot determine any temp directory", category: "Discord")
            state = .disconnected
            return
        }

        for basePath in candidates {
            Log.debug("DiscordRPCService: Searching for IPC socket in \(basePath)", category: "Discord")

            for slot in 0..<AppConstants.Discord.ipcSocketSlots {
                let socketPath = URL(filePath: basePath)
                    .appending(path: "\(AppConstants.Discord.ipcSocketPrefix)\(slot)")
                    .path(percentEncoded: false)

                // The blocking `connect()` (plus the socket setup and timeout
                // opts it gates) runs off the actor executor on `ipcQueue`. On
                // success it returns the ready fd with timeouts applied; on
                // failure it returns -1 after closing any partial fd. The actor
                // only records the result and runs the handshake.
                //
                // Capture the generation BEFORE the await. If a disconnect /
                // teardown bumps it (or the service is disabled) while the open
                // is in flight, close the just-opened fd on `ipcQueue` and bail
                // without committing `socketFD`/`state`, so a stale connect can
                // never overwrite a fresh teardown.
                let generation = connectionGeneration
                let fd = await runOnIPCQueue { Self.openIPCSocket(at: socketPath, slot: slot) }
                guard fd >= 0 else { continue }

                guard isEnabled, connectionGeneration == generation, state == .connecting else {
                    await runOnIPCQueue { Self.closeFD(fd) }
                    return
                }

                socketFD = fd
                if await performHandshake() {
                    // performHandshake suspends twice (write + read on ipcQueue).
                    // A setEnabled(false) interleave during those awaits bumps the
                    // generation and sets socketFD = -1; committing .connected
                    // unconditionally here would wedge the service .connected on a
                    // dead fd forever (sendFrame no-ops on fd < 0, and both
                    // connectIfNeeded and pollTick guard state == .disconnected, so
                    // re-enabling can never reconnect until relaunch). Re-validate.
                    guard isEnabled, connectionGeneration == generation, socketFD == fd else {
                        if socketFD == fd {
                            await runOnIPCQueue { Self.closeFD(fd) }
                            socketFD = -1
                        }
                        return
                    }
                    state = .connected
                    reconnectDelay = AppConstants.Discord.reconnectBaseDelay
                    return
                } else {
                    Log.warn("DiscordRPCService: Handshake failed on slot \(slot)", category: "Discord")
                    // performHandshake may have already torn down via
                    // handleConnectionLost -> disconnect(), which closes the fd
                    // and resets socketFD to -1. Only close here if the fd is
                    // still ours; otherwise we'd double-close (EBADF, and a
                    // recycled fd could be hit in edge cases).
                    if socketFD == fd {
                        await runOnIPCQueue { Self.closeFD(fd) }
                        socketFD = -1
                    }
                }
            }
        }

        Log.debug("DiscordRPCService: No active IPC socket found in any candidate directory", category: "Discord")
        state = .disconnected
    }

    /// Opens, connects, and applies timeouts to a Unix-domain socket at
    /// `socketPath`. Pure of actor state so it can run on ``ipcQueue`` (where the
    /// blocking `connect()` belongs). Returns the connected fd with send/receive
    /// timeouts applied, or -1 on any failure (closing any partial fd first).
    /// `slot` is used only for logging.
    private nonisolated static func openIPCSocket(at socketPath: String, slot: Int) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return -1
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            sunPathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    guard let srcBase = src.baseAddress else { return }
                    _ = memcpy(dest, srcBase, pathBytes.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        guard result == 0 else {
            let err = errno
            Log.debug("DiscordRPCService: connect() failed on slot \(slot): errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            Darwin.close(fd)
            return -1
        }

        setSocketTimeouts(fd)
        return fd
    }

    /// Sends the RPC handshake (opcode 0) with the client ID.
    ///
    /// - Returns: True if handshake was sent and a response was received.
    private func performHandshake() async -> Bool {
        let handshake: [String: Any] = [
            "v": AppConstants.Discord.rpcVersion,
            "client_id": clientID,
        ]

        guard await sendFrame(opcode: .handshake, payload: handshake) else {
            return false
        }

        // Read the READY response
        guard let (opcode, _) = await readFrame() else {
            Log.warn("DiscordRPCService: No handshake response", category: "Discord")
            return false
        }

        if opcode == Opcode.close.rawValue {
            Log.warn("DiscordRPCService: Received CLOSE during handshake", category: "Discord")
            return false
        }

        return true
    }

    /// Disconnects from the IPC socket.
    ///
    /// Bumps ``connectionGeneration`` so any in-flight connect that resumes after
    /// this teardown discards its fd instead of committing it. The close runs on
    /// ``ipcQueue`` so it serializes after any queued read/write still holding the
    /// captured fd, never racing them or closing a recycled descriptor.
    func disconnect() async {
        connectionGeneration &+= 1

        guard socketFD >= 0 else {
            if state != .disconnected { state = .disconnected }
            return
        }
        let fd = socketFD
        socketFD = -1
        state = .disconnected
        await runOnIPCQueue { Self.closeFD(fd) }
    }

    // MARK: - Frame I/O

    /// Suspends the actor and runs `work` on ``ipcQueue``, resuming with its result.
    ///
    /// This is the bridge that keeps the blocking socket syscalls off the actor's
    /// serial executor. `work` runs on the dedicated serial `ipcQueue`; the actor
    /// `await`s the continuation, so a stalled `read`/`write`/`connect` parks only
    /// the queue's worker thread, never the actor. Because `ipcQueue` is serial,
    /// only one such block runs at a time, preserving single-threaded socket
    /// access. `work` must be self-contained: it takes only `Sendable` inputs and
    /// touches no actor state, so the hop is safe.
    private nonisolated func runOnIPCQueue<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            ipcQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Applies send/receive timeouts to the IPC socket.
    ///
    /// The frame I/O uses blocking `Darwin.read`/`Darwin.write` on ``ipcQueue``.
    /// Without a timeout, a Discord peer that stalls mid-frame (or stops draining
    /// its receive buffer) would block the queue's worker thread forever.
    /// `SO_RCVTIMEO`/`SO_SNDTIMEO` make a stalled read/write fail with `EAGAIN`,
    /// which the frame I/O treats as a lost connection. Pure: no actor state.
    private nonisolated static func setSocketTimeouts(_ fd: Int32) {
        var tv = timeval(tv_sec: AppConstants.Discord.socketTimeoutSeconds, tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, size)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, size)
    }

    /// Result of a blocking write, carrying the failing `errno` captured on the
    /// same `ipcQueue` worker thread that ran the syscall.
    ///
    /// `errno` is thread-local, so it must be read inside the queue closure (right
    /// after the failing syscall) rather than back on the actor executor where it
    /// reflects unrelated work. `errno` is meaningful only when `ok == false`.
    struct WriteResult: Sendable {
        let ok: Bool
        let errno: Int32
    }

    /// Result of a blocking read, carrying the bytes (nil on failure) plus the
    /// failing `errno` captured on the `ipcQueue` worker thread. `errno` is
    /// meaningful only when `data == nil`.
    struct ReadResult: Sendable {
        let data: Data?
        let errno: Int32
    }

    /// Writes all of `data` to socket `fd`, looping over partial writes.
    ///
    /// A stream socket may accept fewer bytes than requested per `write`, so a
    /// single call can't be assumed to flush the whole frame. Returns `ok: false`
    /// (with the captured `errno`) if the socket errors or times out before
    /// everything is written. The `errno` is read on this worker thread so it
    /// reflects the actual failure, not later actor-executor work. Pure of actor
    /// state (takes `fd` explicitly) so it can run on ``ipcQueue``.
    private nonisolated static func writeFully(_ data: Data, fd: Int32) -> WriteResult {
        guard !data.isEmpty else { return WriteResult(ok: true, errno: 0) }
        return data.withUnsafeBytes { raw -> WriteResult in
            guard let base = raw.baseAddress else { return WriteResult(ok: false, errno: 0) }
            var total = 0
            while total < data.count {
                let n = Darwin.write(fd, base + total, data.count - total)
                if n > 0 {
                    total += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    return WriteResult(ok: false, errno: errno)
                }
            }
            return WriteResult(ok: true, errno: 0)
        }
    }

    /// Reads exactly `count` bytes from socket `fd`, looping over partial reads.
    ///
    /// A stream socket may return fewer bytes than requested per `read`, so a
    /// single call can't be assumed to fill the buffer. Returns `data: nil` (with
    /// the captured `errno`) if the peer closes (`read` returns 0) or the socket
    /// errors/times out before `count` bytes arrive. The `errno` is read on this
    /// worker thread so it reflects the actual failure, not later actor-executor
    /// work. A clean peer close (`read` returns 0) leaves `errno == 0`. Pure of
    /// actor state (takes `fd` explicitly) so it can run on ``ipcQueue``.
    private nonisolated static func readFully(_ count: Int, fd: Int32) -> ReadResult {
        guard count > 0 else { return ReadResult(data: Data(), errno: 0) }
        var buffer = Data(count: count)
        var failErrno: Int32 = 0
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var total = 0
            while total < count {
                let n = Darwin.read(fd, base + total, count - total)
                if n > 0 {
                    total += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    // peer closed (n == 0, errno stays 0) or error/timeout (n < 0)
                    failErrno = n < 0 ? errno : 0
                    return false
                }
            }
            return true
        }
        return ok ? ReadResult(data: buffer, errno: 0) : ReadResult(data: nil, errno: failErrno)
    }

    /// Closes `fd` on ``ipcQueue`` so the close serializes after any queued
    /// read/write on the same descriptor. Pure of actor state. A no-op for a
    /// negative `fd`. Closing on the queue (never on the actor executor) prevents
    /// a double-close or closing a recycled descriptor while an in-flight
    /// `readFully`/`writeFully` still holds the captured fd value.
    private nonisolated static func closeFD(_ fd: Int32) {
        guard fd >= 0 else { return }
        Darwin.close(fd)
    }

    /// Sends a framed message to Discord.
    ///
    /// Frame format: `[opcode: UInt32 LE][length: UInt32 LE][JSON payload]`
    ///
    /// - Parameters:
    ///   - opcode: The IPC opcode.
    ///   - payload: Dictionary to serialize as JSON.
    /// - Returns: True if the write succeeded.
    @discardableResult
    func sendFrame(opcode: Opcode, payload: [String: Any]) async -> Bool {
        let fd = socketFD
        guard fd >= 0 else { return false }

        // Guards a non-JSON leaf (NaN/Inf Double, non-String key) from raising an
        // ObjC `NSInvalidArgumentException` that `try?` cannot catch.
        guard let jsonData = JSONObjectSerialization.data(from: payload) else {
            Log.error("DiscordRPCService: Failed to serialize payload", category: "Discord")
            return false
        }

        var header = Data(count: 8)
        header.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: opcode.rawValue.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: UInt32(jsonData.count).littleEndian, toByteOffset: 4, as: UInt32.self)
        }

        // Blocking write runs off the actor executor on `ipcQueue`. The frame is
        // fully built here, so the closure only flushes bytes to `fd`. The
        // `errno` is captured inside the closure (on the worker thread) so it
        // reflects the actual write failure, not unrelated actor-executor work.
        let frame = header + jsonData
        let result = await runOnIPCQueue { Self.writeFully(frame, fd: fd) }
        guard result.ok else {
            let err = result.errno
            Log.error("DiscordRPCService: Write failed/timed out with errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            await handleConnectionLost()
            return false
        }

        return true
    }

    /// Reads a single framed message from Discord.
    ///
    /// - Returns: Tuple of (opcode, JSON payload) or nil on failure.
    private func readFrame() async -> (UInt32, [String: Any]?)? {
        let fd = socketFD
        guard fd >= 0 else { return nil }

        // Blocking reads run off the actor executor on `ipcQueue`. The queue is
        // serial, so the header read always completes before the body read, and
        // no other IPC operation interleaves on `fd`. The `errno` is captured
        // inside the closure (on the worker thread) so it reflects the actual
        // read failure, not unrelated actor-executor work.
        let headerResult = await runOnIPCQueue { Self.readFully(8, fd: fd) }
        guard let headerBuf = headerResult.data else {
            let err = headerResult.errno
            Log.error("DiscordRPCService: Header read failed/timed out with errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            return nil
        }

        let opcode = headerBuf.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.load(fromByteOffset: 0, as: UInt32.self))
        }
        let length = headerBuf.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.load(fromByteOffset: 4, as: UInt32.self))
        }

        guard length > 0 else { return (opcode, nil) }
        guard length < AppConstants.Discord.maxIPCFrameBytes else {
            Log.warn("DiscordRPCService: Oversized IPC frame (\(length) bytes); disconnecting", category: "Discord")
            return nil
        }

        let bodyLength = Int(length)
        let bodyResult = await runOnIPCQueue { Self.readFully(bodyLength, fd: fd) }
        guard let bodyBuf = bodyResult.data else {
            let err = bodyResult.errno
            Log.error("DiscordRPCService: Body read failed/timed out with errno \(err) (\(String(cString: strerror(err))))", category: "Discord")
            return nil
        }

        let json = Self.decodeFramePayload(bodyBuf)
        return (opcode, json)
    }

    /// Decodes a Discord IPC frame body into a JSON object, or nil if the bytes
    /// aren't a JSON object. Pure and static so it's unit-testable without a live
    /// socket. `JSONSerialization.jsonObject(with:)` throws (caught by `try?`) on
    /// malformed input and never raises, so a hostile or garbled frame can't crash.
    static func decodeFramePayload(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Reconnection

    /// Computes the next exponential-backoff delay: doubles `current` and clamps
    /// to `max`. Pure and `nonisolated` so the backoff math is unit-testable
    /// without the actor. Reset is just `base` (see `reconnectBaseDelay`).
    nonisolated static func nextBackoff(
        _ current: TimeInterval, base: TimeInterval, max: TimeInterval
    ) -> TimeInterval {
        Swift.min(current * 2, max)
    }

    /// Handles a lost connection by disconnecting and scheduling reconnect.
    private func handleConnectionLost() async {
        await disconnect()

        guard isEnabled else { return }

        let delay = reconnectDelay
        Log.info("DiscordRPCService: Scheduling reconnect in \(delay)s", category: "Discord")
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await self.attemptReconnect()
        }

        reconnectDelay = Self.nextBackoff(
            reconnectDelay,
            base: AppConstants.Discord.reconnectBaseDelay,
            max: AppConstants.Discord.reconnectMaxDelay)
    }

    private func attemptReconnect() async {
        guard isEnabled else { return }
        await connectIfNeeded()
    }
}
