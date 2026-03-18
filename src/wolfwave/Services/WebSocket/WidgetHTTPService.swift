//
//  WidgetHTTPService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 3/15/26.
//

import Foundation
import Network

// MARK: - Widget HTTP Service

/// Serves the bundled `widget.html` over a plain HTTP/1.1 connection on localhost.
///
/// Owned and driven by `WebSocketServerService` — starts when the WS server starts,
/// stops when it stops. Binds to the loopback interface only.
///
/// - `GET /` or `GET /?...` → `200 OK` with `widget.html` body
/// - All other requests → `404 Not Found`
final class WidgetHTTPService {

    // MARK: - Properties

    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(
        label: "com.mrdemonwolf.wolfwave.widget-http",
        qos: .utility
    )

    // MARK: - Init

    init(port: UInt16) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start() {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            Log.error("WidgetHTTP: Invalid port \(port)", category: "WidgetHTTP")
            return
        }
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: nwPort
        )

        do {
            listener = try NWListener(using: parameters)
        } catch {
            Log.error("WidgetHTTP: Failed to create listener: \(error)", category: "WidgetHTTP")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.info("WidgetHTTP: Listening on port \(self.port)", category: "WidgetHTTP")
            case .failed(let error):
                Log.error("WidgetHTTP: Listener failed: \(error)", category: "WidgetHTTP")
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

    func stop() {
        listener?.cancel()
        listener = nil
        Log.info("WidgetHTTP: Server stopped", category: "WidgetHTTP")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { connection.cancel(); return }
            guard let data, !data.isEmpty, error == nil else { connection.cancel(); return }
            self.serveResponse(to: connection, requestData: data)
        }
    }

    private func serveResponse(to connection: NWConnection, requestData: Data) {
        let requestString = String(data: requestData, encoding: .utf8) ?? ""
        let firstLine = requestString.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        let method = parts.count > 0 ? parts[0] : ""
        let rawPath = parts.count > 1 ? parts[1] : ""
        let path = rawPath.components(separatedBy: "?").first ?? rawPath

        if method == "GET" && (path == "/" || path.isEmpty) {
            serveWidget(to: connection)
        } else {
            send404(to: connection)
        }
    }

    // MARK: - Responses

    private func serveWidget(to connection: NWConnection) {
        guard let url = Bundle.main.url(forResource: "widget", withExtension: "html"),
              let body = try? Data(contentsOf: url) else {
            Log.error("WidgetHTTP: widget.html not found in bundle", category: "WidgetHTTP")
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
