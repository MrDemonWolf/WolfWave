//
//  WidgetHTTPService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/15/26.
//

import AppKit
import Foundation
import Network

// MARK: - Widget HTTP Service

/// Serves the bundled `widget.html` over a plain HTTP/1.1 connection on localhost.
///
/// Owned and driven by `WebSocketServerService` — starts when the WS server starts,
/// stops when it stops. Binds to the loopback interface only.
///
/// - `GET /` or `GET /?...` → `200 OK` with `widget.html` body
/// - `GET /widget-tokens.generated.js` → `200 OK` with generated design tokens JS
/// - `GET /favicon.ico` / `GET /favicon.png` → `200 OK` with app icon PNG
/// - All other requests → `404 Not Found`
nonisolated final class WidgetHTTPService: @unchecked Sendable {

    // MARK: - Properties

    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.widget-http",
        qos: .utility
    )

    // MARK: - Init

    /// Creates a widget HTTP service bound to the loopback interface.
    ///
    /// - Parameter port: TCP port to listen on. Caller is responsible for
    ///   choosing a free port (typically `AppConstants.WebSocketServer.widgetDefaultPort`).
    init(port: UInt16) {
        self.port = port
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Brings up the loopback listener and begins accepting connections.
    /// Idempotent — a second call while already running is a no-op.
    func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            Log.error("WidgetHTTPService: Invalid port \(port)", category: "WebSocket")
            return
        }
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: nwPort
        )

        do {
            listener = try NWListener(using: parameters)
        } catch {
            Log.error("WidgetHTTPService: Failed to create listener: \(error)", category: "WebSocket")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.info("WidgetHTTPService: Listening on port \(self.port)", category: "WebSocket")
            case .failed(let error):
                Log.error("WidgetHTTPService: Listener failed: \(error)", category: "WebSocket")
                self.listener = nil
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    /// Cancels the listener and tears down the bound port. Safe to call when
    /// the service was never started or has already stopped.
    func stop() {
        listener?.cancel()
        listener = nil
        Log.info("WidgetHTTPService: Server stopped", category: "WebSocket")
    }

    // MARK: - Connection Handling

    /// Accepts an inbound TCP connection and reads up to 8 KiB of the request
    /// before dispatching to `serveResponse`.
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { connection.cancel(); return }
            guard let data, !data.isEmpty, error == nil else { connection.cancel(); return }
            self.serveResponse(to: connection, requestData: data)
        }
    }

    /// Parses the HTTP request line and routes to the matching handler.
    ///
    /// Routes:
    /// - `GET /` (or empty path, with or without query) → `serveWidget`
    /// - `GET /favicon.ico` / `GET /favicon.png` → `serveFavicon`
    /// - Anything else → `send404`
    private func serveResponse(to connection: NWConnection, requestData: Data) {
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
    private func serveWidget(to connection: NWConnection) {
        guard let url = Bundle.main.url(forResource: "widget", withExtension: "html"),
              let body = try? Data(contentsOf: url) else {
            Log.error("WidgetHTTPService: widget.html not found in bundle", category: "WebSocket")
            send404(to: connection)
            return
        }

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
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let body = bitmap.representation(using: .png, properties: [:]) else {
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
