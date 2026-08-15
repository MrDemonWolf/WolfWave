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
        if let pendingClose = ipcCloseInProgress {
            await pendingClose.wait()
            if ipcCloseInProgress === pendingClose {
                ipcCloseInProgress = nil
            }
        }
        // The close wait is an actor-reentrancy point. A disable may have won
        // while it was suspended, so do not let the stale connect publish a
        // new `.connecting` state after the final user intent is already off.
        guard isEnabled else { return }
        guard state == .disconnected else { return }
        guard !clientID.isEmpty else {
            Log.warn("DiscordRPCService: No client ID configured: skipping connection", category: .discord)
            lastFailure = .notConfigured
            return
        }

        state = .connecting
        let attemptGeneration = connectionGeneration

        let candidates = tempDirectoryCandidates()
        guard !candidates.isEmpty else {
            Log.error("DiscordRPCService: Cannot determine any temp directory", category: .discord)
            lastFailure = .socketUnavailable
            state = .disconnected
            return
        }

        for basePath in candidates {
            Log.debug("DiscordRPCService: Searching for IPC socket in \(basePath)", category: .discord)

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
                let opener = ipcSocketOpener
                let fd = await runOnIPCQueue { opener(socketPath, slot) }
                guard isEnabled,
                      connectionGeneration == attemptGeneration,
                      state == .connecting else {
                    if fd >= 0 {
                        let closer = ipcSocketCloser
                        await runOnIPCQueue { closer(fd) }
                    }
                    // If this attempt still owns the generation, a disable
                    // interleaved after the opener was queued but before it
                    // returned. Retire its transient state so a later enable
                    // can start a fresh connection. Never overwrite a newer
                    // generation's state.
                    if connectionGeneration == attemptGeneration,
                       state == .connecting {
                        state = .disconnected
                    }
                    return
                }
                guard fd >= 0 else { continue }

                socketFD = fd
                ipcReadBuffer = IPCReadBuffer()
                if await performHandshake() {
                    // performHandshake suspends while one write/read transaction
                    // runs on ipcQueue. A setEnabled(false) interleave during that
                    // await bumps the generation and sets socketFD = -1. Committing
                    // .connected here would wedge the service on a dead fd because
                    // connectIfNeeded and pollTick both require .disconnected.
                    // Re-validate before publishing the successful connection.
                    guard ownsConnection(fd: fd, generation: attemptGeneration), isEnabled else {
                        if ownsConnection(fd: fd, generation: attemptGeneration) {
                            await retirePreSourceConnection(
                                fd: fd,
                                generation: attemptGeneration
                            )
                        }
                        return
                    }
                    state = .connected
                    lastFailure = .none
                    reconnectDelay = AppConstants.Discord.reconnectBaseDelay
                    updateAvailabilityPolling()
                    await refreshPresenceFromSettings()
                    startIPCReadPump()
                    return
                } else {
                    Log.warn("DiscordRPCService: Handshake failed on slot \(slot)", category: .discord)
                    // A socket existed and Discord refused us, so this is not
                    // "Discord isn't running" however the loop ends.
                    lastFailure = .handshakeRejected
                    // performHandshake may have already torn down via
                    // handleConnectionLost -> disconnect(), which closes the fd
                    // and resets socketFD to -1. Only close here if the fd is
                    // still ours; otherwise we'd double-close (EBADF, and a
                    // recycled fd could be hit in edge cases).
                    if ownsConnection(fd: fd, generation: attemptGeneration) {
                        await retirePreSourceConnection(
                            fd: fd,
                            generation: attemptGeneration
                        )
                    }
                    guard isEnabled, connectionGeneration == attemptGeneration else { return }
                }
            }
        }

        Log.debug("DiscordRPCService: No active IPC socket found in any candidate directory", category: .discord)
        guard isEnabled,
              connectionGeneration == attemptGeneration,
              state == .connecting else { return }
        // Only claim Discord is closed when no slot rejected us. A handshake
        // rejection recorded above outranks this.
        if lastFailure != .handshakeRejected {
            lastFailure = .notRunning
        }
        state = .disconnected
    }

    /// Result of one injected `poll` call used by the nonblocking-connect seam.
    struct IPCPollResult: Sendable {
        let count: Int32
        let revents: Int16
        let errno: Int32
    }

    /// Opens, connects, and applies timeouts to a Unix-domain socket at
    /// `socketPath`. Pure of actor state so it can run on ``ipcQueue`` (where the
    /// blocking `connect()` belongs). Returns the connected fd with send/receive
    /// timeouts applied, or -1 on any failure (closing any partial fd first).
    /// `slot` is used only for logging.
    nonisolated static func openIPCSocket(at socketPath: String, slot: Int) -> Int32 {
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

        let originalFlags = fcntl(fd, F_GETFL, 0)
        guard originalFlags >= 0,
              fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            Darwin.close(fd)
            return -1
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        let connectError: Int32
        if result == 0 {
            connectError = 0
        } else {
            let immediateError = errno
            if immediateError == EINPROGRESS {
                connectError = waitForNonblockingConnect(
                    fd: fd,
                    deadline: monotonicDeadline(
                        afterNanoseconds: UInt64(AppConstants.Discord.socketTimeoutSeconds)
                            * 1_000_000_000
                    ),
                    now: monotonicNow,
                    poller: systemPollForWrite,
                    socketError: pendingSocketError
                )
            } else {
                connectError = immediateError
            }
        }

        let restoreResult = fcntl(fd, F_SETFL, originalFlags)
        guard connectError == 0, restoreResult == 0 else {
            let err = connectError != 0 ? connectError : errno
            Log.debug("DiscordRPCService: connect() failed on slot \(slot): errno \(err) (\(String(cString: strerror(err))))", category: .discord)
            Darwin.close(fd)
            return -1
        }

        guard setSocketTimeouts(fd) else {
            Darwin.close(fd)
            return -1
        }
        return fd
    }

    /// Waits for a nonblocking connect to finish within an absolute monotonic
    /// deadline. `poller`, `socketError`, and `now` are injected so timeout and
    /// error handling are deterministic in unit tests without a live socket.
    nonisolated static func waitForNonblockingConnect(
        fd: Int32,
        deadline: UInt64,
        now: () -> UInt64,
        poller: (Int32, Int32) -> IPCPollResult,
        socketError: (Int32) -> Int32
    ) -> Int32 {
        while true {
            let current = now()
            guard current < deadline else { return ETIMEDOUT }
            let timeout = pollTimeoutMilliseconds(deadline: deadline, now: current)
            let result = poller(fd, timeout)
            if result.count > 0 {
                return socketError(fd)
            }
            if result.count == 0 {
                return ETIMEDOUT
            }
            if result.errno == EINTR {
                continue
            }
            return result.errno == 0 ? EIO : result.errno
        }
    }

    private nonisolated static func systemPollForWrite(
        _ fd: Int32,
        _ timeout: Int32
    ) -> IPCPollResult {
        var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let count = Darwin.poll(&descriptor, nfds_t(1), timeout)
        return IPCPollResult(
            count: count,
            revents: descriptor.revents,
            errno: count < 0 ? errno : 0
        )
    }

    private nonisolated static func pendingSocketError(_ fd: Int32) -> Int32 {
        var pendingError: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &pendingError, &size) == 0 else {
            return errno
        }
        return pendingError
    }

    /// Sends the RPC handshake and accepts only Discord's READY dispatch.
    ///
    /// The write and response read run in one ``ipcQueue`` block. Keeping the
    /// exchange atomic prevents another actor call from inserting a command
    /// between the handshake write and READY response.
    ///
    /// - Returns: True only for an opcode-``Opcode/frame`` response whose payload
    ///   has `cmd == "DISPATCH"` and `evt == "READY"`.
    func performHandshake() async -> Bool {
        let handshake: [String: Any] = [
            "v": AppConstants.Discord.rpcVersion,
            "client_id": clientID,
        ]

        guard let outbound = Self.encodeFrame(opcode: .handshake, payload: handshake) else {
            Log.error("DiscordRPCService: Failed to serialize handshake", category: .discord)
            return false
        }

        let fd = socketFD
        guard fd >= 0 else { return false }
        let generation = connectionGeneration
        let readBuffer = ipcReadBuffer
        let timeoutNanoseconds = ipcTransactionTimeoutNanoseconds
        let result = await runOnIPCQueue {
            Self.performIPCTransaction(
                outbound,
                expecting: .ready,
                fd: fd,
                readBuffer: readBuffer,
                timeoutNanoseconds: timeoutNanoseconds
            )
        }

        // The actor was re-entrant while the blocking transaction ran. An fd
        // integer can be reused, so both fd and generation are required before
        // this continuation may inspect or mutate connection state.
        guard ownsConnection(fd: fd, generation: generation) else { return false }

        guard result.writeResult.ok else {
            let err = result.writeResult.errno
            let reason = "\(err) (\(String(cString: strerror(err))))"
            Log.error(
                "DiscordRPCService: Handshake write failed/timed out: \(reason)",
                category: .discord
            )
            return false
        }

        guard result.response != nil else {
            if result.readErrno != 0 {
                let err = result.readErrno
                let reason = "\(err) (\(String(cString: strerror(err))))"
                Log.error(
                    "DiscordRPCService: Handshake read failed/timed out: \(reason)",
                    category: .discord
                )
            } else {
                Log.warn("DiscordRPCService: Invalid handshake response; expected DISPATCH/READY", category: .discord)
            }
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
            if let pendingClose = ipcCloseInProgress {
                await pendingClose.wait()
                if ipcCloseInProgress === pendingClose {
                    ipcCloseInProgress = nil
                }
            }
            return
        }

        let fd = socketFD
        let source = ipcReadSource
        let sourceClose = ipcReadSourceClose

        // Retire every actor-visible ownership token before the first await.
        // Another disconnect or connect can now observe that this generation no
        // longer owns `fd`, even while the asynchronous cancel handler is gated.
        socketFD = -1
        ipcReadSource = nil
        ipcReadSourceClose = nil
        state = .disconnected

        let completion = sourceClose ?? IPCDescriptorClose()
        ipcCloseInProgress = completion
        let closer = ipcSocketCloser
        if let source {
            if sourceClose == nil {
                // Defensive repair for an incompletely installed test source.
                // Production installation always pairs these atomically.
                source.setCancelHandler {
                    closer(fd)
                    completion.complete()
                }
            }
            // Once installed, the source cancellation handler is the sole
            // descriptor closer. Never directly close `fd` on this path.
            source.cancel()
        } else {
            // Pre-source descriptor (normally a handshake in progress).
            ipcQueue.async {
                closer(fd)
                completion.complete()
            }
        }

        await completion.wait()
        if ipcCloseInProgress === completion {
            ipcCloseInProgress = nil
        }
    }

    /// Synchronously retires an actor-owned descriptor that has not yet gained a
    /// read source, then awaits its queue-confined close. Used by stale-success
    /// and failed-handshake paths so actor reentrancy cannot retain a recycled fd.
    private func retirePreSourceConnection(fd: Int32, generation: UInt64) async {
        guard ownsConnection(fd: fd, generation: generation) else { return }
        socketFD = -1
        ipcReadSource = nil
        ipcReadSourceClose = nil

        let completion = IPCDescriptorClose()
        ipcCloseInProgress = completion
        let closer = ipcSocketCloser
        ipcQueue.async {
            closer(fd)
            completion.complete()
        }
        await completion.wait()
        if ipcCloseInProgress === completion {
            ipcCloseInProgress = nil
        }
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
    private func runOnIPCQueue<T: Sendable>(
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        let observer = ipcWorkEnqueuedObserver
        return await withCheckedContinuation { continuation in
            ipcQueue.async {
                continuation.resume(returning: work())
            }
            // DispatchQueue.async has accepted the block before this fires,
            // giving tests a real enqueue happens-before edge.
            observer?()
        }
    }

    /// Installs the optional queue-enqueue observer used by deterministic socket
    /// transaction tests.
    func setIPCWorkEnqueuedObserver(_ observer: (@Sendable () -> Void)?) {
        ipcWorkEnqueuedObserver = observer
    }

    /// Applies send/receive timeouts to the IPC socket.
    ///
    /// The frame I/O uses blocking `Darwin.read`/`Darwin.write` on ``ipcQueue``.
    /// Without a timeout, a Discord peer that stalls mid-frame (or stops draining
    /// its receive buffer) would block the queue's worker thread forever.
    /// `SO_RCVTIMEO`/`SO_SNDTIMEO` make a stalled read/write fail with `EAGAIN`,
    /// which the frame I/O treats as a lost connection. Pure: no actor state.
    nonisolated static func setSocketTimeouts(_ fd: Int32) -> Bool {
        var tv = timeval(tv_sec: AppConstants.Discord.socketTimeoutSeconds, tv_usec: 0)
        var noSigPipe: Int32 = 1
        let size = socklen_t(MemoryLayout<timeval>.size)
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            let err = errno
            Log.error(
                "DiscordRPCService: Failed to suppress SIGPIPE: errno \(err)",
                category: .discord
            )
            return false
        }
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, size) == 0 else {
            let err = errno
            Log.error(
                "DiscordRPCService: Failed to set receive timeout: errno \(err)",
                category: .discord
            )
            return false
        }
        guard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, size) == 0 else {
            let err = errno
            Log.error(
                "DiscordRPCService: Failed to set send timeout: errno \(err)",
                category: .discord
            )
            return false
        }
        return true
    }

    /// Current monotonic time used for socket deadlines.
    private nonisolated static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    /// Saturating absolute monotonic deadline.
    private nonisolated static func monotonicDeadline(
        afterNanoseconds interval: UInt64
    ) -> UInt64 {
        let now = monotonicNow()
        let (deadline, overflow) = now.addingReportingOverflow(interval)
        return overflow ? UInt64.max : deadline
    }

    /// Remaining `poll(2)` timeout, rounded up so a sub-millisecond remainder
    /// does not become a premature zero-timeout poll.
    private nonisolated static func pollTimeoutMilliseconds(
        deadline: UInt64,
        now: UInt64
    ) -> Int32 {
        guard deadline > now else { return 0 }
        let remaining = deadline - now
        let whole = remaining / 1_000_000
        let rounded = whole + (remaining % 1_000_000 == 0 ? 0 : 1)
        return Int32(Swift.min(rounded, UInt64(Int32.max)))
    }

    /// Waits until `fd` is ready for the requested operation, recomputing the
    /// remaining time after signals so one absolute deadline bounds every retry.
    private nonisolated static func waitForSocket(
        _ fd: Int32,
        events: Int16,
        deadline: UInt64
    ) -> Int32 {
        while true {
            let now = monotonicNow()
            guard now < deadline else { return ETIMEDOUT }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(
                &descriptor,
                nfds_t(1),
                pollTimeoutMilliseconds(deadline: deadline, now: now)
            )
            if result > 0 {
                guard monotonicNow() < deadline else { return ETIMEDOUT }
                return descriptor.revents & Int16(POLLNVAL) == 0 ? 0 : EBADF
            }
            if result == 0 { return ETIMEDOUT }
            if errno == EINTR { continue }
            return errno
        }
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
    private nonisolated static func writeFully(
        _ data: Data,
        fd: Int32,
        deadline: UInt64
    ) -> WriteResult {
        guard !data.isEmpty else { return WriteResult(ok: true, errno: 0) }
        return data.withUnsafeBytes { raw -> WriteResult in
            guard let base = raw.baseAddress else { return WriteResult(ok: false, errno: 0) }
            var total = 0
            while total < data.count {
                let waitError = waitForSocket(
                    fd,
                    events: Int16(POLLOUT),
                    deadline: deadline
                )
                guard waitError == 0 else {
                    return WriteResult(ok: false, errno: waitError)
                }
                let n = Darwin.send(
                    fd,
                    base + total,
                    data.count - total,
                    Int32(MSG_DONTWAIT)
                )
                if n > 0 {
                    total += n
                } else if n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
                    continue
                } else {
                    return WriteResult(ok: false, errno: n == 0 ? EPIPE : errno)
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
    private nonisolated static func readFully(
        _ count: Int,
        fd: Int32,
        deadline: UInt64
    ) -> ReadResult {
        guard count > 0 else { return ReadResult(data: Data(), errno: 0) }
        var buffer = Data(count: count)
        var failErrno: Int32 = 0
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var total = 0
            while total < count {
                let waitError = waitForSocket(
                    fd,
                    events: Int16(POLLIN),
                    deadline: deadline
                )
                guard waitError == 0 else {
                    failErrno = waitError
                    return false
                }
                let n = Darwin.recv(
                    fd,
                    base + total,
                    count - total,
                    Int32(MSG_DONTWAIT)
                )
                if n > 0 {
                    total += n
                } else if n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
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

    /// One decoded IPC frame carried across the ``ipcQueue`` continuation.
    private struct IPCFrame: Sendable {
        let opcode: UInt32
        let payload: Data?
    }

    /// Result of reading one complete IPC frame on ``ipcQueue``.
    private struct FrameReadResult: Sendable {
        let frame: IPCFrame?
        let errno: Int32
    }

    /// Result of one queue-owned write/read exchange.
    private struct IPCTransactionResult: Sendable {
        let writeResult: WriteResult
        let response: IPCFrame?
        let readErrno: Int32
    }

    /// Response identity used while draining an IPC transaction.
    private enum IPCResponseExpectation: Sendable {
        case ready
        case command(nonce: String, command: String)
    }

    /// Finite drain bound for a malformed or hostile peer that continuously
    /// sends unmatched frames. READY and command transactions share the same
    /// policy because WolfWave does not subscribe to Discord event frames.
    private nonisolated static let ipcTransactionMaximumFrames = 32

    /// Encodes one Discord IPC frame.
    ///
    /// Frame format: `[opcode: UInt32 LE][length: UInt32 LE][JSON payload]`.
    /// Guards invalid JSON leaves and oversized payloads before integer
    /// conversion so malformed app state cannot trap the process.
    private nonisolated static func encodeFrame(
        opcode: Opcode,
        payload: [String: Any]
    ) -> Data? {
        guard let jsonData = JSONObjectSerialization.data(from: payload),
              let length = UInt32(exactly: jsonData.count),
              length < AppConstants.Discord.maxIPCFrameBytes else {
            return nil
        }

        var header = Data(count: 8)
        header.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: opcode.rawValue.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: length.littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        return header + jsonData
    }

    /// Encodes a frame whose body must be preserved byte-for-byte (PING/PONG).
    private nonisolated static func encodeRawFrame(
        opcode: Opcode,
        payload: Data
    ) -> Data? {
        guard let length = UInt32(exactly: payload.count),
              length < AppConstants.Discord.maxIPCFrameBytes else { return nil }
        var header = Data(count: 8)
        header.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: opcode.rawValue.littleEndian, toByteOffset: 0, as: UInt32.self)
            buf.storeBytes(of: length.littleEndian, toByteOffset: 4, as: UInt32.self)
        }
        return header + payload
    }

    /// Sends one command and consumes its matching Discord reply atomically.
    ///
    /// The entire write plus reply-drain loop is a single ``ipcQueue`` block.
    /// Actor reentrancy can enqueue another transaction while this method awaits,
    /// but that transaction cannot write until this command's nonce-matched reply
    /// has been consumed.
    @discardableResult
    func sendCommandFrame(_ payload: [String: Any]) async -> Bool {
        guard let nonce = payload["nonce"] as? String,
              !nonce.isEmpty,
              let command = payload["cmd"] as? String,
              !command.isEmpty,
              let outbound = Self.encodeFrame(opcode: .frame, payload: payload) else {
            Log.error("DiscordRPCService: Invalid command payload", category: .discord)
            return false
        }

        let fd = socketFD
        guard fd >= 0 else { return false }
        let generation = connectionGeneration
        let readBuffer = ipcReadBuffer
        let timeoutNanoseconds = ipcTransactionTimeoutNanoseconds
        let result = await runOnIPCQueue {
            Self.performIPCTransaction(
                outbound,
                expecting: .command(nonce: nonce, command: command),
                fd: fd,
                readBuffer: readBuffer,
                timeoutNanoseconds: timeoutNanoseconds
            )
        }

        guard ownsConnection(fd: fd, generation: generation) else { return false }

        guard result.writeResult.ok else {
            let err = result.writeResult.errno
            let reason = "\(err) (\(String(cString: strerror(err))))"
            Log.error(
                "DiscordRPCService: Command write failed/timed out: \(reason)",
                category: .discord
            )
            await handleConnectionLost(fd: fd, generation: generation)
            return false
        }

        guard let response = result.response,
              let payloadData = response.payload,
              let responsePayload = Self.decodeFramePayload(payloadData) else {
            if result.readErrno != 0 {
                let err = result.readErrno
                let reason = "\(err) (\(String(cString: strerror(err))))"
                Log.error(
                    "DiscordRPCService: Command reply read failed/timed out: \(reason)",
                    category: .discord
                )
            } else {
                Log.warn("DiscordRPCService: Missing or mismatched command reply", category: .discord)
            }
            await handleConnectionLost(fd: fd, generation: generation)
            return false
        }

        if responsePayload["evt"] as? String == "ERROR" {
            Log.warn("DiscordRPCService: Discord rejected \(command)", category: .discord)
            return false
        }
        return true
    }

    /// Performs a write plus response match as one serial-queue transaction.
    ///
    /// Unmatched frames are drained inside the same block. A CLOSE frame,
    /// malformed frame, timeout, or exhausted drain bound fails the transaction;
    /// no reply is left unread for the next command to accidentally consume.
    private nonisolated static func performIPCTransaction(
        _ outbound: Data,
        expecting expectation: IPCResponseExpectation,
        fd: Int32,
        readBuffer: IPCReadBuffer,
        timeoutNanoseconds: UInt64
    ) -> IPCTransactionResult {
        // A single absolute deadline covers the write and every subsequent
        // header/body/PONG/unmatched-frame operation. Receiving one byte or one
        // stale frame never resets the budget.
        let deadline = monotonicDeadline(afterNanoseconds: timeoutNanoseconds)
        let writeResult = writeFully(outbound, fd: fd, deadline: deadline)
        guard writeResult.ok else {
            return IPCTransactionResult(
                writeResult: writeResult,
                response: nil,
                readErrno: 0
            )
        }

        for _ in 0..<Self.ipcTransactionMaximumFrames {
            guard monotonicNow() < deadline else {
                return IPCTransactionResult(
                    writeResult: writeResult,
                    response: nil,
                    readErrno: ETIMEDOUT
                )
            }
            let readResult = readIPCFrame(
                fd: fd,
                readBuffer: readBuffer,
                deadline: deadline
            )
            guard let frame = readResult.frame else {
                return IPCTransactionResult(
                    writeResult: writeResult,
                    response: nil,
                    readErrno: readResult.errno
                )
            }
            guard frame.opcode != Opcode.close.rawValue else {
                return IPCTransactionResult(
                    writeResult: writeResult,
                    response: nil,
                    readErrno: 0
                )
            }
            if frame.opcode == Opcode.ping.rawValue {
                guard let pong = encodeRawFrame(
                    opcode: .pong,
                    payload: frame.payload ?? Data()
                ) else {
                    return IPCTransactionResult(
                        writeResult: WriteResult(ok: false, errno: EMSGSIZE),
                        response: nil,
                        readErrno: 0
                    )
                }
                let pongResult = writeFully(pong, fd: fd, deadline: deadline)
                guard pongResult.ok else {
                    return IPCTransactionResult(
                        writeResult: pongResult,
                        response: nil,
                        readErrno: 0
                    )
                }
                continue
            }
            if response(frame, matches: expectation) {
                return IPCTransactionResult(
                    writeResult: writeResult,
                    response: frame,
                    readErrno: 0
                )
            }
        }

        return IPCTransactionResult(
            writeResult: writeResult,
            response: nil,
            readErrno: 0
        )
    }

    /// Reads one complete framed message. Must run on ``ipcQueue``.
    private nonisolated static func readIPCFrame(
        fd: Int32,
        readBuffer: IPCReadBuffer,
        deadline: UInt64
    ) -> FrameReadResult {
        while true {
            if let parsed = popIPCFrame(from: readBuffer) { return parsed }

            let targetCount: Int
            if readBuffer.data.count < 8 {
                targetCount = 8
            } else {
                let length = readBuffer.data.withUnsafeBytes { buf in
                    UInt32(littleEndian: buf.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
                }
                guard length < AppConstants.Discord.maxIPCFrameBytes else {
                    readBuffer.data.removeAll(keepingCapacity: true)
                    return FrameReadResult(frame: nil, errno: EMSGSIZE)
                }
                targetCount = 8 + Int(length)
            }

            let missing = targetCount - readBuffer.data.count
            let readResult = readFully(missing, fd: fd, deadline: deadline)
            guard let bytes = readResult.data else {
                return FrameReadResult(frame: nil, errno: readResult.errno)
            }
            readBuffer.data.append(bytes)
        }
    }

    /// Removes one complete frame from the shared queue-owned byte buffer.
    private nonisolated static func popIPCFrame(
        from readBuffer: IPCReadBuffer
    ) -> FrameReadResult? {
        guard readBuffer.data.count >= 8 else { return nil }
        let opcode = readBuffer.data.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
        }
        let length = readBuffer.data.withUnsafeBytes { buf in
            UInt32(littleEndian: buf.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        guard length < AppConstants.Discord.maxIPCFrameBytes else {
            readBuffer.data.removeAll(keepingCapacity: true)
            return FrameReadResult(frame: nil, errno: EMSGSIZE)
        }
        let total = 8 + Int(length)
        guard readBuffer.data.count >= total else { return nil }
        let payload = length == 0
            ? nil
            : readBuffer.data.subdata(in: 8..<total)
        readBuffer.data.removeSubrange(0..<total)
        return FrameReadResult(
            frame: IPCFrame(opcode: opcode, payload: payload),
            errno: 0
        )
    }

    /// Tests a decoded frame against the active transaction expectation.
    private nonisolated static func response(
        _ frame: IPCFrame,
        matches expectation: IPCResponseExpectation
    ) -> Bool {
        guard let payloadData = frame.payload,
              let payload = decodeFramePayload(payloadData) else {
            return false
        }

        switch expectation {
        case .ready:
            return isReadyHandshakeResponse(opcode: frame.opcode, payload: payload)
        case let .command(nonce, command):
            return isCommandResponse(
                opcode: frame.opcode,
                payload: payload,
                nonce: nonce,
                command: command
            )
        }
    }

    /// Pure validator for Discord's handshake response.
    nonisolated static func isReadyHandshakeResponse(
        opcode: UInt32,
        payload: [String: Any]?
    ) -> Bool {
        opcode == Opcode.frame.rawValue
            && payload?["cmd"] as? String == "DISPATCH"
            && payload?["evt"] as? String == "READY"
    }

    /// Pure validator for a command response. Both command and nonce must match.
    nonisolated static func isCommandResponse(
        opcode: UInt32,
        payload: [String: Any]?,
        nonce: String,
        command: String
    ) -> Bool {
        opcode == Opcode.frame.rawValue
            && payload?["cmd"] as? String == command
            && payload?["nonce"] as? String == nonce
    }

    /// Decodes a Discord IPC frame body into a JSON object, or nil if the bytes
    /// aren't a JSON object. Pure and static so it's unit-testable without a live
    /// socket. `JSONSerialization.jsonObject(with:)` throws (caught by `try?`) on
    /// malformed input and never raises, so a hostile or garbled frame can't crash.
    nonisolated static func decodeFramePayload(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Idle Inbound Pump

    /// Result of one short, queue-owned idle read slice.
    private enum IdleReadResult: Sendable {
        case handled
        case needsDrain
        case connectionLost(errno: Int32)
    }

    /// Starts the sole unsolicited-frame reader for the current connection.
    ///
    /// The dispatch source only schedules work when the socket becomes readable,
    /// avoiding the permanent 100 ms polling loop previously used here. Its
    /// event handler runs on ipcQueue, the same serial queue as command
    /// transactions. A handler that runs first cannot steal a future command
    /// reply because that command has not yet written; a transaction that runs
    /// first owns its complete write/read exchange.
    func startIPCReadPump() {
        // Installation transfers physical fd ownership to the source's cancel
        // handler. Replacing a live source would create two potential closers,
        // so repeated starts are deliberately a no-op.
        guard ipcReadSource == nil else { return }
        guard state == .connected, socketFD >= 0 else {
            return
        }
        guard ipcCloseInProgress == nil else { return }
        let fd = socketFD
        let generation = connectionGeneration
        let readBuffer = ipcReadBuffer
        let closeCompletion = IPCDescriptorClose()
        let closer = ipcSocketCloser
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ipcQueue)
        source.setEventHandler { [weak self] in
            let result = Self.performIdleReadSlice(fd: fd, readBuffer: readBuffer)
            switch result {
            case .handled:
                break
            case .needsDrain, .connectionLost:
                Task {
                    await self?.handleIdleReadResult(
                        result,
                        fd: fd,
                        generation: generation,
                        readBuffer: readBuffer
                    )
                }
            }
        }
        source.setCancelHandler {
            closer(fd)
            closeCompletion.complete()
        }
        ipcReadSource = source
        ipcReadSourceClose = closeCompletion
        source.resume()
    }

    /// Finishes bounded buffered draining or handles a connection loss back on
    /// the actor. Each additional drain is submitted as a fresh queue block so a
    /// command transaction already waiting on ipcQueue can run between batches.
    private func handleIdleReadResult(
        _ initialResult: IdleReadResult,
        fd: Int32,
        generation: UInt64,
        readBuffer: IPCReadBuffer
    ) async {
        var result = initialResult
        while ownsConnection(fd: fd, generation: generation), state == .connected {
            switch result {
            case .handled:
                return
            case .connectionLost(let err):
                if err != 0 {
                    Log.debug(
                        "DiscordRPCService: Idle IPC read failed: errno \(err)",
                        category: .discord
                    )
                }
                await handleConnectionLost(fd: fd, generation: generation)
                return
            case .needsDrain:
                result = await runOnIPCQueue {
                    Self.performIdleReadSlice(fd: fd, readBuffer: readBuffer)
                }
            }
        }
    }

    /// Reads one currently available byte batch and answers up to 32 complete
    /// unsolicited frames. `MSG_DONTWAIT` keeps this event handler from parking
    /// ipcQueue if DispatchSource coalesces readiness notifications.
    private nonisolated static func performIdleReadSlice(
        fd: Int32,
        readBuffer: IPCReadBuffer
    ) -> IdleReadResult {
        let deadline = monotonicDeadline(
            afterNanoseconds: UInt64(AppConstants.Discord.socketTimeoutSeconds)
                * 1_000_000_000
        )
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = bytes.withUnsafeMutableBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return Darwin.recv(fd, baseAddress, rawBuffer.count, Int32(MSG_DONTWAIT))
        }
        if count > 0 {
            readBuffer.data.append(contentsOf: bytes.prefix(count))
        } else if count == 0 {
            return .connectionLost(errno: 0)
        } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
            return .connectionLost(errno: errno)
        }

        for _ in 0..<32 {
            guard let readResult = popIPCFrame(from: readBuffer) else { break }
            guard let frame = readResult.frame else {
                return .connectionLost(errno: readResult.errno)
            }
            if frame.opcode == Opcode.close.rawValue {
                return .connectionLost(errno: 0)
            }
            guard frame.opcode == Opcode.ping.rawValue else { continue }
            guard let pong = encodeRawFrame(
                opcode: .pong,
                payload: frame.payload ?? Data()
            ) else {
                return .connectionLost(errno: EMSGSIZE)
            }
            let writeResult = writeFully(pong, fd: fd, deadline: deadline)
            guard writeResult.ok else {
                return .connectionLost(errno: writeResult.errno)
            }
        }

        return hasCompleteIPCFrame(in: readBuffer) ? .needsDrain : .handled
    }

    /// Whether the queue-owned buffer contains at least one complete frame.
    /// An oversized advertised length also counts as complete so the next drain
    /// reports the malformed frame instead of leaving it buffered forever.
    private nonisolated static func hasCompleteIPCFrame(in readBuffer: IPCReadBuffer) -> Bool {
        guard readBuffer.data.count >= 8 else { return false }
        let length = readBuffer.data.withUnsafeBytes { buffer in
            UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        guard length < AppConstants.Discord.maxIPCFrameBytes else { return true }
        return readBuffer.data.count >= 8 + Int(length)
    }

    /// Connection ownership predicate. Descriptor integers alone are unsafe:
    /// the OS may recycle one for a replacement socket after a teardown.
    nonisolated static func isCurrentConnection(
        capturedFD: Int32,
        capturedGeneration: UInt64,
        currentFD: Int32,
        currentGeneration: UInt64
    ) -> Bool {
        capturedFD >= 0
            && capturedFD == currentFD
            && capturedGeneration == currentGeneration
    }

    private func ownsConnection(fd: Int32, generation: UInt64) -> Bool {
        Self.isCurrentConnection(
            capturedFD: fd,
            capturedGeneration: generation,
            currentFD: socketFD,
            currentGeneration: connectionGeneration
        )
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
    private func handleConnectionLost(fd: Int32, generation: UInt64) async {
        guard ownsConnection(fd: fd, generation: generation) else { return }
        await disconnect()
        // The coarse availability fallback is useful only while disconnected;
        // successful connect paths stop it again immediately.
        updateAvailabilityPolling()

        guard isEnabled else { return }

        let delay = reconnectDelay
        Log.info("DiscordRPCService: Scheduling reconnect in \(delay)s", category: .discord)
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
