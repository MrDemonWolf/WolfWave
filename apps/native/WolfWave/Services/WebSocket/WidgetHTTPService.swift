//
//  WidgetHTTPService.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-03-18.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
//

import AppKit
import Foundation
import Network

// MARK: - Widget HTTP Service

/// Serves the bundled `widget.html` over a plain HTTP/1.1 connection.
///
/// Owned and driven by `WebSocketServerService`. Starts when the WS server starts,
/// stops when it stops. Binds to all interfaces so LAN peers (a second-PC OBS,
/// a phone browser) can fetch the widget for two-PC streaming setups.
///
/// ## Token injection
///
/// The bundled `widget.html` contains a `__WOLFWAVE_TOKEN__` sentinel. The
/// substitution runs **only when the requesting peer is loopback** so a LAN
/// fetch cannot lift the WebSocket credential out of the served HTML. Remote
/// peers receive the raw template; the JS falls back to the `?token=` URL
/// query string for the WebSocket handshake.
///
/// - `GET /` or `GET /?...` → `200 OK` with `widget.html` body
/// - `GET /widget-tokens.generated.js` → `200 OK` with generated design tokens JS
/// - `GET /favicon.ico` / `GET /favicon.png` → `200 OK` with app icon PNG
/// - All other requests → `404 Not Found`
///
/// ## Connection lifecycle
///
/// Accepted connections are tracked and bounded: at most
/// `maxConcurrentConnections` are served at once (extra accepts are cancelled
/// immediately), a connection that never delivers complete request headers is
/// cancelled after `headerTimeout`, and `stop()` cancels every tracked
/// connection along with the listener. Without this, a half-open LAN peer
/// (an OBS box losing power mid-connect) would pin an `NWConnection` and its
/// file descriptor for the app lifetime via the pending receive callback.
nonisolated final class WidgetHTTPService: @unchecked Sendable {

    // MARK: - Errors

    /// Thrown from `ready()` when the listener will never reach `.ready` for the
    /// current `start()` cycle: either the bind failed or the service was stopped
    /// before binding. Lets a caller distinguish "bound" from "shut down" instead
    /// of hanging forever.
    enum ReadyError: Error {
        /// The `NWListener` transitioned to `.failed` before becoming ready.
        case listenerFailed
        /// `stop()` ran before the listener became ready.
        case stopped
    }

    // MARK: - Properties

    private let port: UInt16
    /// Token baked into the served `widget.html` so OBS browser sources hit the
    /// WebSocket with a valid `wolfwave.token.<hex>` subprotocol without the user
    /// pasting a query string. `nil` ships the file un-substituted (test-only).
    private let authToken: String?
    /// Guards all reads and writes of `listener` so the state-callback queue and
    /// `stop()` callers cannot race on the reference.
    private let listenerLock = NSLock()
    private var _listener: NWListener?
    /// Thread-safe accessor for the underlying `NWListener`.
    private var listener: NWListener? {
        get { listenerLock.withLock { _listener } }
        set { listenerLock.withLock { _listener = newValue } }
    }
    private let queue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.widget-http",
        qos: .utility
    )

    /// Book-keeping for one accepted connection: the connection itself plus
    /// whether its request headers have finished arriving, which disarms the
    /// header timeout.
    private struct TrackedConnection {
        let connection: NWConnection
        var headersComplete = false
    }

    /// Guards all reads and writes of `activeConnections` so the connection
    /// callbacks on `queue` and `stop()` callers cannot race.
    private let connectionsLock = NSLock()
    /// Accepted connections currently being served, keyed by identity so each
    /// connection's state callback removes exactly its own entry. Tracking lets
    /// `stop()` tear down in-flight connections and lets the header timeout
    /// find its peer.
    private var activeConnections: [ObjectIdentifier: TrackedConnection] = [:]

    /// Upper bound on concurrently tracked connections. Extra accepts are
    /// cancelled immediately so a misbehaving LAN peer cannot exhaust file
    /// descriptors.
    private let maxConcurrentConnections: Int

    /// How long an accepted connection may take to deliver its complete
    /// request headers before it is cancelled.
    private let headerTimeout: TimeInterval

    /// Number of connections currently tracked. Exposed so tests can await
    /// accepts deterministically instead of sleeping.
    var activeConnectionCount: Int {
        connectionsLock.withLock { activeConnections.count }
    }

    /// Readiness latch, fulfilled once on the first `NWListener.State.ready`.
    /// Lets callers (notably tests) await the listener actually binding the
    /// port instead of sleeping a fixed interval. Guarded by `readyLock` so the
    /// `networkQueue` state callback and an awaiting caller can race safely.
    private let readyLock = NSLock()
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    /// Sentinel string in the bundled `widget.html` that we replace with the
    /// live auth token before sending the response.
    private static let tokenPlaceholder = "__WOLFWAVE_TOKEN__"

    /// `<script src>` tag in the bundled `widget.html` that we replace with an
    /// inlined `<script>` block carrying `widget-tokens.generated.js` so the
    /// browser doesn't have to make a second HTTP round-trip before first paint.
    private static let tokensScriptTag = "<script src=\"widget-tokens.generated.js\"></script>"

    // MARK: - Init

    /// Creates a widget HTTP service.
    ///
    /// - Parameters:
    ///   - port: TCP port to listen on. Bound on all interfaces so LAN peers
    ///     can reach the widget for two-PC streaming setups.
    ///   - authToken: WebSocket auth token to inject into the served HTML
    ///     **for loopback requests only**. Pass `nil` to ship the file
    ///     untouched. Only useful for tests.
    ///   - headerTimeout: Seconds an accepted connection may take to deliver
    ///     its complete request headers before it is cancelled. Defaults to
    ///     10; override only in tests.
    ///   - maxConcurrentConnections: Upper bound on concurrently tracked
    ///     connections; extra accepts are cancelled immediately. Defaults to
    ///     32; override only in tests.
    init(
        port: UInt16,
        authToken: String? = nil,
        headerTimeout: TimeInterval = 10,
        maxConcurrentConnections: Int = 32
    ) {
        self.port = port
        self.authToken = authToken
        self.headerTimeout = headerTimeout
        self.maxConcurrentConnections = maxConcurrentConnections
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Brings up the HTTP listener and begins accepting connections.
    /// Binds to all interfaces; per-request loopback gating is enforced in
    /// `serveWidget` for token injection. Idempotent. A second call while
    /// already running is a no-op.
    func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            Log.error("WidgetHTTPService: Invalid port \(port)", category: "WebSocket")
            return
        }

        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            Log.error("WidgetHTTPService: Failed to create listener: \(error)", category: "WebSocket")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.info("WidgetHTTPService: Listening on port \(self.port)", category: "WebSocket")
                self.markReady()
            case .failed(let error):
                Log.error("WidgetHTTPService: Listener failed: \(error)", category: "WebSocket")
                self.listener = nil
                self.failReadyWaiters(with: .listenerFailed)
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    /// Cancels the listener and tears down the bound port, then cancels every
    /// tracked connection so pending receive callbacks (which retain their
    /// connection) cannot outlive the service. Safe to call when the service
    /// was never started or has already stopped.
    func stop() {
        listener?.cancel()
        listener = nil
        let openConnections: [NWConnection] = connectionsLock.withLock {
            let open = activeConnections.values.map(\.connection)
            activeConnections.removeAll()
            return open
        }
        for connection in openConnections {
            connection.cancel()
        }
        readyLock.withLock { isReady = false }
        // Wake any caller still awaiting `ready()` so a stop-before-bind doesn't
        // leave them suspended forever.
        failReadyWaiters(with: .stopped)
        Log.info("WidgetHTTPService: Server stopped", category: "WebSocket")
    }

    /// Suspends until the listener reaches `NWListener.State.ready` (the port
    /// is bound and accepting connections). Returns immediately if the service
    /// is already ready. Use this instead of a fixed `Thread.sleep` so callers
    /// (and tests) wait exactly as long as the bind takes and no longer.
    ///
    /// - Throws: `ReadyError.listenerFailed` if the bind fails, or
    ///   `ReadyError.stopped` if `stop()` runs before the listener binds. This
    ///   guarantees the call always resolves instead of hanging on a listener
    ///   that will never reach `.ready`.
    func ready() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let alreadyReady: Bool = readyLock.withLock {
                if isReady { return true }
                readyWaiters.append(continuation)
                return false
            }
            if alreadyReady {
                continuation.resume()
            }
        }
    }

    /// Latches readiness and resumes any callers awaiting `ready()`. Invoked
    /// once on the first `.ready` listener transition (on `queue`).
    private func markReady() {
        let waiters: [CheckedContinuation<Void, Error>] = readyLock.withLock {
            guard !isReady else { return [] }
            isReady = true
            let pending = readyWaiters
            readyWaiters.removeAll()
            return pending
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Resumes any pending `ready()` waiters with the given failure, then clears
    /// the queue. Invoked when the listener fails to bind or when `stop()` tears
    /// the service down before it ever reaches `.ready`.
    private func failReadyWaiters(with error: ReadyError) {
        let waiters: [CheckedContinuation<Void, Error>] = readyLock.withLock {
            let pending = readyWaiters
            readyWaiters.removeAll()
            return pending
        }
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    // MARK: - Connection Handling

    /// Largest request-header block we will buffer before giving up. Bounds the
    /// reassembly below so a slow or hostile peer can't make us hold an unbounded
    /// buffer while we wait for `\r\n\r\n`.
    private static let maxHeaderBytes = 8192

    /// HTTP header terminator: a blank line (CRLF CRLF) ends the request headers.
    private static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])

    /// Accepts an inbound TCP connection, tracks it for lifecycle teardown,
    /// arms the header timeout, and begins reading the request headers.
    /// Connections beyond `maxConcurrentConnections` are cancelled immediately.
    private func handleConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)

        let accepted: Bool = connectionsLock.withLock {
            guard activeConnections.count < maxConcurrentConnections else { return false }
            activeConnections[id] = TrackedConnection(connection: connection)
            return true
        }
        guard accepted else {
            Log.warn(
                "WidgetHTTPService: Refusing connection, \(maxConcurrentConnections) already active",
                category: "WebSocket"
            )
            connection.cancel()
            return
        }

        // Untrack on any terminal state so the table cannot grow without bound.
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed:
                connection?.stateUpdateHandler = nil
                connection?.cancel()
                self?.removeConnection(id)
            case .cancelled:
                connection?.stateUpdateHandler = nil
                self?.removeConnection(id)
            default:
                break
            }
        }

        connection.start(queue: queue)
        scheduleHeaderTimeout(for: connection)
        readRequestHeaders(from: connection, accumulated: Data())
    }

    /// Cancels `connection` if its request headers have not completed within
    /// `headerTimeout` of accept. Disarmed by `serveResponse` marking the
    /// headers complete; a no-op once the connection has been untracked.
    private func scheduleHeaderTimeout(for connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        queue.asyncAfter(deadline: .now() + headerTimeout) { [weak self, weak connection] in
            guard let self, let connection else { return }
            let stillAwaitingHeaders: Bool = self.connectionsLock.withLock {
                guard let tracked = self.activeConnections[id],
                      tracked.connection === connection else { return false }
                return !tracked.headersComplete
            }
            guard stillAwaitingHeaders else { return }
            Log.warn(
                "WidgetHTTPService: Cancelling connection with incomplete headers after \(self.headerTimeout)s",
                category: "WebSocket"
            )
            connection.cancel()
        }
    }

    /// Disarms the header timeout for `connection` once its request headers
    /// have fully arrived.
    private func markHeadersComplete(for connection: NWConnection) {
        connectionsLock.withLock {
            activeConnections[ObjectIdentifier(connection)]?.headersComplete = true
        }
    }

    /// Drops the tracking entry for a connection that reached a terminal state.
    private func removeConnection(_ id: ObjectIdentifier) {
        connectionsLock.withLock {
            _ = activeConnections.removeValue(forKey: id)
        }
    }

    /// Reads from `connection` until the `\r\n\r\n` header terminator is seen or
    /// the `maxHeaderBytes` cap is hit, reassembling across fragmented reads so a
    /// split first packet can't produce a false 404. The request line is always in
    /// the first chunk we hand to `serveResponse`, so once the headers are complete
    /// (or the cap is reached) we parse and stop reading. No security change: the
    /// auth gate still lives in the WebSocket handshake, not here.
    private func readRequestHeaders(from connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            guard error == nil else { connection.cancel(); return }

            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.isEmpty {
                // Peer closed without sending anything.
                connection.cancel()
                return
            }

            // Headers complete, cap reached, or peer finished sending: parse now.
            if buffer.range(of: Self.headerTerminator) != nil
                || buffer.count >= Self.maxHeaderBytes
                || isComplete {
                self.serveResponse(to: connection, requestData: buffer)
                return
            }

            // Need more bytes to complete the header block.
            self.readRequestHeaders(from: connection, accumulated: buffer)
        }
    }

    /// Parses the HTTP request line and routes to the matching handler.
    ///
    /// Routes:
    /// - `GET /` (or empty path, with or without query) → `serveWidget`
    /// - `GET /favicon.ico` / `GET /favicon.png` → `serveFavicon`
    /// - Anything else → `send404`
    private func serveResponse(to connection: NWConnection, requestData: Data) {
        markHeadersComplete(for: connection)
        let requestString = String(data: requestData, encoding: .utf8) ?? ""
        let firstLine = requestString.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        let method = parts.count > 0 ? parts[0] : ""
        let rawPath = parts.count > 1 ? parts[1] : ""
        let path = rawPath.components(separatedBy: "?").first ?? rawPath

        if method == "GET" && (path == "/" || path.isEmpty) {
            serveWidget(to: connection)
        } else if method == "GET" && path == "/widget-tokens.generated.js" {
            serveTokensJS(to: connection)
        } else if method == "GET" && (path == "/favicon.ico" || path == "/favicon.png") {
            serveFavicon(to: connection)
        } else {
            send404(to: connection)
        }
    }

    // MARK: - Responses

    /// Writes the bundled `widget.html` as an HTTP/1.1 200 response and
    /// closes the connection. Falls back to a 404 when the asset is missing.
    ///
    /// Token injection is gated on the peer being loopback: a LAN peer
    /// receives the raw template (its JS picks the token up from the
    /// `?token=` URL query) so the credential never leaves this Mac in an
    /// unauthenticated HTTP response.
    private func serveWidget(to connection: NWConnection) {
        guard let url = Bundle.main.url(forResource: "widget", withExtension: "html"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            Log.error("WidgetHTTPService: widget.html not found in bundle", category: "WebSocket")
            send404(to: connection)
            return
        }

        let isLoopback = Self.isLoopbackPeer(connection)
        var rendered: String
        if isLoopback, let token = authToken, WebSocketAuthToken.isValid(token) {
            // `isValid` gates the substitution on hex-only / bounded length so a
            // corrupted or hand-edited token can't inject `</script>` or other
            // characters that would break out of the JS string context.
            rendered = raw.replacingOccurrences(of: Self.tokenPlaceholder, with: token)
        } else {
            if isLoopback, let token = authToken, !WebSocketAuthToken.isValid(token) {
                Log.warn(
                    "WidgetHTTPService: Refusing to inject non-hex auth token into widget.html",
                    category: "WebSocket"
                )
            }
            rendered = raw
        }

        // Inline widget-tokens.generated.js to save the second HTTP round-trip
        // on first paint. If the bundle asset is missing, leave the original
        // <script src> tag so the /widget-tokens.generated.js route still works.
        if let tokensURL = Bundle.main.url(forResource: "widget-tokens.generated", withExtension: "js"),
           let tokensJS = try? String(contentsOf: tokensURL, encoding: .utf8) {
            let inlined = "<script>\n" + tokensJS + "\n</script>"
            rendered = rendered.replacingOccurrences(of: Self.tokensScriptTag, with: inlined)
        } else {
            Log.warn(
                "WidgetHTTPService: widget-tokens.generated.js not found in bundle, falling back to external <script src>",
                category: "WebSocket"
            )
        }

        let body = Data(rendered.utf8)

        let header = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/html; charset=utf-8\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Writes the bundled `widget-tokens.generated.js` as an HTTP/1.1 200 response.
    /// Sourced from `design-system/tokens.json` via the token generator and bundled
    /// alongside `widget.html`. Falls back to 404 when the asset is missing.
    private func serveTokensJS(to connection: NWConnection) {
        guard let url = Bundle.main.url(forResource: "widget-tokens.generated", withExtension: "js"),
              let body = try? Data(contentsOf: url) else {
            Log.error("WidgetHTTPService: widget-tokens.generated.js not found in bundle", category: "WebSocket")
            send404(to: connection)
            return
        }

        let header = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/javascript; charset=utf-8\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: no-cache\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Encodes the app icon as PNG and serves it with a one-day cache header.
    /// Used so browser tabs displaying the widget show a recognizable icon.
    private func serveFavicon(to connection: NWConnection) {
        guard let image = NSImage(named: "AppIcon"),
              let body = image.pngData() else {
            send404(to: connection)
            return
        }

        let header = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: image/png\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Cache-Control: public, max-age=86400\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Peer Inspection

    /// Returns `true` when the peer's remote endpoint is on `127.0.0.0/8` or `::1`.
    ///
    /// Used by `serveWidget` to gate token injection: only same-Mac peers see
    /// the auth credential baked into the served HTML. LAN peers receive the
    /// raw template and must supply `?token=…` in the URL.
    private static func isLoopbackPeer(_ connection: NWConnection) -> Bool {
        switch connection.endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let addr):
                return addr.isLoopback
            case .ipv6(let addr):
                return addr.isLoopback
            case .name:
                // The widget always connects to ws://localhost which resolves to
                // an IP endpoint; an unresolved .name is never a genuine loopback
                // peer, so return false rather than trusting a hostname string.
                return false
            @unknown default:
                return false
            }
        default:
            return false
        }
    }

    /// Writes a minimal `404 Not Found` plain-text response and closes the
    /// connection.
    private func send404(to connection: NWConnection) {
        let body = "Not Found"
        let response = "HTTP/1.1 404 Not Found\r\n" +
            "Content-Type: text/plain\r\n" +
            "Content-Length: \(body.utf8.count)\r\n" +
            "Connection: close\r\n\r\n" + body
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
