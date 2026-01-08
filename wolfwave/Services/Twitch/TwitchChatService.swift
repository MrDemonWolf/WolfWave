//
//  TwitchChatService.swift
//  wolfwave
//
//  Created by Nathanial Henniges on 1/8/26.
//

import Foundation

/// Modern Twitch Chat service using Helix API + EventSub (recommended by Twitch)
///
/// Uses the Twitch Helix API for sending messages and EventSub for receiving.
/// Supports message replies with proper thread tracking.
///
/// Usage:
/// ```swift
/// let service = TwitchChatService()
/// service.getCurrentSongInfo = { /* return current song */ }
///
/// service.joinChannel(
///     broadcasterID: "12345",
///     botID: "67890",
///     token: "oauth:xxxxx"
/// )
/// ```
final class TwitchChatService {
    // MARK: - Types

    struct ChatMessage {
        let messageID: String
        let username: String
        let userID: String
        let message: String
        let channel: String
        let badges: [Badge]
        let reply: Reply?

        struct Badge {
            let setID: String
            let id: String
            let info: String
        }

        struct Reply {
            let parentMessageID: String
            let parentMessageBody: String
            let parentUserID: String
            let parentUsername: String
        }
    }

    enum ConnectionError: LocalizedError {
        case invalidCredentials
        case missingClientID
        case networkError(String)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .invalidCredentials:
                return "Invalid Twitch credentials"
            case .missingClientID:
                return "Twitch Client ID is not configured"
            case .networkError(let msg):
                return "Network error: \(msg)"
            case .authenticationFailed:
                return "Failed to authenticate with Twitch"
            }
        }
    }

    // MARK: - Properties

    private let apiBaseURL = "https://api.twitch.tv/helix"
    private let commandDispatcher = BotCommandDispatcher()

    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionID: String?

    private var broadcasterID: String?
    private var botID: String?
    private var oauthToken: String?
    private var clientID: String?
    private var botUsername: String?
    var debugLoggingEnabled = false

    /// Callback to get current song info for !song command
    var getCurrentSongInfo: (() -> String)?

    /// Callback when a message is received
    var onMessageReceived: ((ChatMessage) -> Void)?

    /// Callback when connection state changes
    var onConnectionStateChanged: ((Bool) -> Void)?

    // MARK: - Types

    struct BotIdentity {
        let userID: String
        let login: String
        let displayName: String
    }

    // MARK: - Public Methods

    /// Join a channel to start receiving messages
    ///
    /// - Parameters:
    ///   - broadcasterID: The broadcaster's Twitch user ID (channel owner)
    ///   - botID: The bot's Twitch user ID
    ///   - token: OAuth token with user:write:chat scope
    ///   - clientID: Twitch Client ID
    func joinChannel(
        broadcasterID: String,
        botID: String,
        token: String,
        clientID: String
    ) throws {
        guard !broadcasterID.isEmpty, !botID.isEmpty, !token.isEmpty else {
            Log.error("Twitch: Invalid credentials for channel join", category: "TwitchChat")
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            Log.error("Twitch: Missing client ID for channel join", category: "TwitchChat")
            throw ConnectionError.missingClientID
        }

        self.broadcasterID = broadcasterID
        self.botID = botID
        self.oauthToken = token
        self.clientID = clientID
        self.botUsername = nil

        // Set up the current song info callback for commands
        commandDispatcher.setCurrentSongInfo { [weak self] in
            self?.getCurrentSongInfo?() ?? "No track currently playing"
        }

        onConnectionStateChanged?(true)
        Log.info("Twitch: Joined channel \(broadcasterID)", category: "TwitchChat")

        // Connect to EventSub WebSocket to receive messages
        connectToEventSub()

        // Send activation message to chat
        sendMessage("WolfWave Application is connected! 🎵")
    }

    /// Connect to a Twitch channel with automatic bot identity resolution.
    ///
    /// This method handles the complete setup:
    /// 1. Resolves the bot identity (user ID and username) if needed
    /// 2. Resolves the channel name to a user ID
    /// 3. Joins the channel via EventSub
    ///
    /// - Parameters:
    ///   - channelName: The channel to join (username)
    ///   - token: OAuth token with user:write:chat scope
    ///   - clientID: Twitch Client ID
    /// - Throws: Connection error if any step fails
    func connectToChannel(channelName: String, token: String, clientID: String) async throws {
        guard !channelName.isEmpty, !token.isEmpty else {
            Log.error("Twitch: Invalid channel name or token", category: "TwitchChat")
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            Log.error("Twitch: Missing client ID for channel connect", category: "TwitchChat")
            throw ConnectionError.missingClientID
        }

        // Get or resolve bot identity
        var botUserID = KeychainService.loadTwitchBotUserID()
        var resolvedUsername = KeychainService.loadTwitchUsername() ?? ""

        if botUserID?.isEmpty ?? true {
            let identity = try await fetchBotIdentity(token: token, clientID: clientID)
            botUserID = identity.userID
            resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName
            try KeychainService.saveTwitchUsername(resolvedUsername)
            try KeychainService.saveTwitchBotUserID(identity.userID)
            Log.debug(
                "Twitch: Resolved bot identity - username: \(resolvedUsername)",
                category: "TwitchChat")
        }

        guard let botUserID = botUserID else {
            throw ConnectionError.invalidCredentials
        }

        // Resolve channel name to user ID
        let broadcasterUserID = try await resolveUsername(
            channelName,
            token: token,
            clientID: clientID
        )

        guard !broadcasterUserID.isEmpty else {
            throw ConnectionError.networkError("Could not resolve channel name to user ID")
        }

        // Join the channel
        try joinChannel(
            broadcasterID: broadcasterUserID,
            botID: botUserID,
            token: token,
            clientID: clientID
        )

        Log.info("Twitch: Connected to channel \(channelName)", category: "TwitchChat")
    }

    /// Resolve and cache the bot identity (user ID and username).
    ///
    /// This method fetches the bot's user ID and username from Twitch and caches them locally.
    /// Used for populating UI and internal state without connecting to a channel.
    ///
    /// - Parameters:
    ///   - token: OAuth token with user:read:users scope
    ///   - clientID: Twitch Client ID
    /// - Throws: Connection error if the fetch fails
    func resolveBotIdentity(token: String, clientID: String) async throws {
        guard !token.isEmpty else {
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            throw ConnectionError.missingClientID
        }

        let identity = try await fetchBotIdentity(token: token, clientID: clientID)
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        // Cache the identity
        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)

        Log.debug(
            "Twitch: Resolved bot identity - username: \(resolvedUsername)",
            category: "TwitchChat")
    }

    /// Static method to resolve and cache bot identity without requiring a service instance.
    ///
    /// This is useful for SettingsView when the service might not be available yet.
    /// Fetches bot identity from Twitch API and caches to Keychain.
    ///
    /// - Parameters:
    ///   - token: OAuth token with user:read:users scope
    ///   - clientID: Twitch Client ID
    /// - Throws: Connection error if the fetch fails
    static func resolveBotIdentityStatic(token: String, clientID: String) async throws {
        guard !token.isEmpty else {
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            throw ConnectionError.missingClientID
        }

        let service = TwitchChatService()
        let identity = try await service.fetchBotIdentity(token: token, clientID: clientID)
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        // Cache the identity
        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)

        Log.debug(
            "Twitch: Resolved bot identity (static) - username: \(resolvedUsername)",
            category: "TwitchChat")
    }

    /// Resolve the Twitch Client ID from environment or Info.plist
    static func resolveClientID() -> String? {
        if let env = ProcessInfo.processInfo.environment["TWITCH_CLIENT_ID"], !env.isEmpty {
            return env
        }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "TwitchClientID") as? String,
            !plistValue.isEmpty
        {
            return plistValue
        }

        return nil
    }

    /// Fetch the bot identity (user id and usernames) from Twitch using the OAuth token.
    func fetchBotIdentity(token: String, clientID: String) async throws -> BotIdentity {
        guard let url = URL(string: apiBaseURL + "/users") else {
            Log.error("Twitch: Failed to construct users endpoint URL", category: "TwitchChat")
            throw ConnectionError.networkError("Invalid users endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ConnectionError.networkError("No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                Log.error(
                    "Twitch: Authentication failed (401) - invalid or expired OAuth token",
                    category: "TwitchChat")
                throw ConnectionError.authenticationFailed
            }
            Log.error(
                "Twitch: Users endpoint error HTTP \(http.statusCode)", category: "TwitchChat")
            throw ConnectionError.networkError("Users endpoint returned \(http.statusCode)")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]],
            let first = dataArray.first,
            let userID = first["id"] as? String,
            let login = first["login"] as? String
        else {
            Log.error("Twitch: Failed to parse user identity from response", category: "TwitchChat")
            throw ConnectionError.networkError("Unable to parse user identity")
        }

        let displayName = first["display_name"] as? String ?? login

        botID = userID
        botUsername = displayName

        return BotIdentity(userID: userID, login: login, displayName: displayName)
    }

    /// Leave the channel
    func leaveChannel() {
        disconnectFromEventSub()

        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil

        onConnectionStateChanged?(false)
        Log.info("Twitch: Left channel", category: "TwitchChat")
    }

    /// Validate an OAuth token with Twitch and verify required scopes
    /// - Parameters:
    ///   - token: The OAuth access token (raw string, not prefixed)
    ///   - requiredScopes: Scopes that must be present for chat features
    /// - Returns: true if token is valid and has required scopes
    func validateToken(
        _ token: String, requiredScopes: [String] = ["user:read:chat", "user:write:chat"]
    ) async -> Bool {
        guard let url = URL(string: "https://id.twitch.tv/oauth2/validate") else {
            Log.error("Twitch: Invalid validate URL", category: "TwitchChat")
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Per Twitch docs, use "OAuth <token>" for the validate endpoint
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 {
                    Log.warn(
                        "Twitch: Stored OAuth token is invalid or expired", category: "TwitchChat")
                } else {
                    Log.warn(
                        "Twitch: Token validate HTTP \(http.statusCode)", category: "TwitchChat")
                }
                return false
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.warn("Twitch: Could not parse token validate response", category: "TwitchChat")
                return false
            }

            // optional: check scopes
            if let scopes = json["scopes"] as? [String] {
                let missing = requiredScopes.filter { !scopes.contains($0) }
                if !missing.isEmpty {
                    Log.warn(
                        "Twitch: Token missing required scopes: \(missing.joined(separator: ", "))",
                        category: "TwitchChat")
                    return false
                }
            }

            return true
        } catch {
            Log.error(
                "Twitch: Token validate request failed - \(error.localizedDescription)",
                category: "TwitchChat")
            return false
        }
    }

    /// Send a message to the channel
    func sendMessage(_ message: String) {
        sendMessage(message, replyTo: nil)
    }

    /// Send a message that replies to another message
    func sendMessage(_ message: String, replyTo parentMessageID: String?) {
        guard let broadcasterID = broadcasterID,
            let botID = botID,
            let token = oauthToken,
            let clientID = clientID
        else {
            Log.warn("Twitch: Not connected", category: "TwitchChat")
            return
        }

        var body: [String: Any] = [
            "broadcaster_id": broadcasterID,
            "sender_id": botID,
            "message": message,
        ]

        if let parentMessageID = parentMessageID {
            body["reply_parent_message_id"] = parentMessageID
        }

        sendAPIRequest(
            method: "POST",
            endpoint: "/chat/messages",
            body: body,
            token: token,
            clientID: clientID
        ) { result in
            switch result {
            case .success(let data):
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let dataArray = json["data"] as? [[String: Any]],
                    let messageData = dataArray.first
                {
                    let isSent = messageData["is_sent"] as? Bool ?? false
                    if isSent {
                    } else {
                        Log.warn("Twitch: Message dropped", category: "TwitchChat")
                    }
                }
            case .failure(let error):
                Log.error(
                    "Twitch: Failed to send message - \(error.localizedDescription)",
                    category: "TwitchChat")
            }
        }
    }

    /// Parse and handle an incoming message from EventSub
    func handleEventSubMessage(_ json: [String: Any]) {
        if debugLoggingEnabled {
            Log.debug("Twitch: Raw EventSub message: \(json)", category: "TwitchChat")
        }

        guard let event = json["event"] as? [String: Any] else { return }

        let messageID = event["message_id"] as? String ?? ""
        let username = event["chatter_user_name"] as? String ?? ""
        let userID = event["chatter_user_id"] as? String ?? ""
        let broadcasterID = event["broadcaster_user_id"] as? String ?? ""
        let messageText = event["message"] as? [String: Any]
        let text = messageText?["text"] as? String ?? ""

        // Parse badges
        var badges: [ChatMessage.Badge] = []
        if let badgeArray = event["badges"] as? [[String: Any]] {
            for badge in badgeArray {
                if let setID = badge["set_id"] as? String,
                    let id = badge["id"] as? String
                {
                    let info = badge["info"] as? String ?? ""
                    badges.append(ChatMessage.Badge(setID: setID, id: id, info: info))
                }
            }
        }

        // Parse reply
        var reply: ChatMessage.Reply?
        if let replyObj = event["reply"] as? [String: Any] {
            let parentMessageID = replyObj["parent_message_id"] as? String ?? ""
            let parentBody = replyObj["parent_message_body"] as? String ?? ""
            let parentUserID = replyObj["parent_user_id"] as? String ?? ""
            let parentUsername = replyObj["parent_user_name"] as? String ?? ""

            reply = ChatMessage.Reply(
                parentMessageID: parentMessageID,
                parentMessageBody: parentBody,
                parentUserID: parentUserID,
                parentUsername: parentUsername
            )
        }

        let chatMessage = ChatMessage(
            messageID: messageID,
            username: username,
            userID: userID,
            message: text,
            channel: broadcasterID,
            badges: badges,
            reply: reply
        )

        // Process message through command dispatcher
        if let response = commandDispatcher.processMessage(text) {
            sendMessage(response, replyTo: messageID)
        }

        onMessageReceived?(chatMessage)
    }

    // MARK: - Private Helpers

    private func sendAPIRequest(
        method: String,
        endpoint: String,
        body: [String: Any]?,
        token: String,
        clientID: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let url = URL(string: apiBaseURL + endpoint) else {
            completion(.failure(ConnectionError.networkError("Invalid URL")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(ConnectionError.networkError("No response data")))
                return
            }

            completion(.success(data))
        }.resume()
    }

    // MARK: - EventSub WebSocket

    private func connectToEventSub() {
        Log.debug("Twitch: Connecting to EventSub WebSocket", category: "TwitchChat")
        guard let url = URL(string: "wss://eventsub.wss.twitch.tv/ws") else {
            Log.error("Twitch: Invalid EventSub URL", category: "TwitchChat")
            onConnectionStateChanged?(false)
            return
        }

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        Log.info("Twitch: EventSub WebSocket task resumed", category: "TwitchChat")
        receiveWebSocketMessage()
    }

    private func disconnectFromEventSub() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        sessionID = nil
        Log.info("Twitch: Disconnected from EventSub WebSocket", category: "TwitchChat")
    }

    private func receiveWebSocketMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleWebSocketMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleWebSocketMessage(text)
                    } else {
                        Log.warn(
                            "Twitch: Failed to decode WebSocket data as UTF-8",
                            category: "TwitchChat"
                        )
                    }
                @unknown default:
                    Log.warn(
                        "Twitch: Unknown WebSocket message type received",
                        category: "TwitchChat"
                    )
                }

                // Continue receiving messages
                self.receiveWebSocketMessage()

            case .failure(let error):
                Log.error(
                    "Twitch: WebSocket error - \(error.localizedDescription)",
                    category: "TwitchChat")
                self.onConnectionStateChanged?(false)
            }
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        if debugLoggingEnabled {
            Log.debug("Twitch: WebSocket message - \(text)", category: "TwitchChat")
        }

        guard let metadata = json["metadata"] as? [String: Any],
            let messageType = metadata["message_type"] as? String
        else {
            return
        }

        switch messageType {
        case "session_welcome":
            handleSessionWelcome(json)
        case "notification":
            handleNotification(json)
        case "session_keepalive":
            // Just keep the connection alive
            break
        default:
            break
        }
    }

    private func handleSessionWelcome(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
            let session = payload["session"] as? [String: Any],
            let sessionID = session["id"] as? String
        else {
            Log.error("Twitch: Failed to parse session ID", category: "TwitchChat")
            return
        }

        self.sessionID = sessionID
        // EventSub session established

        // Subscribe to chat message events
        subscribeToChannelChatMessage()
    }

    private func handleNotification(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        handleEventSubMessage(payload)
    }

    private func subscribeToChannelChatMessage() {
        guard let sessionID = sessionID,
            let broadcasterID = broadcasterID,
            let botID = botID,
            let token = oauthToken,
            let clientID = clientID
        else {
            Log.error(
                "Twitch: Missing credentials for EventSub subscription", category: "TwitchChat")
            return
        }

        let subscriptionBody: [String: Any] = [
            "type": "channel.chat.message",
            "version": "1",
            "condition": [
                "broadcaster_user_id": broadcasterID,
                "user_id": botID,
            ],
            "transport": [
                "method": "websocket",
                "session_id": sessionID,
            ],
        ]

        guard let url = URL(string: apiBaseURL + "/eventsub/subscriptions") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: subscriptionBody)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Log.error(
                    "Twitch: EventSub subscription error - \(error.localizedDescription)",
                    category: "TwitchChat")
                return
            }

            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    Log.info("Twitch: Connected to chat", category: "TwitchChat")
                } else {
                    let responseText =
                        data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response"
                    Log.error(
                        "Twitch: EventSub subscription failed - HTTP \(http.statusCode) - \(responseText)",
                        category: "TwitchChat")
                }
            }
        }.resume()
    }

    /// Resolve a Twitch username to a user ID
    func resolveUsername(_ username: String, token: String, clientID: String) async throws -> String
    {

        guard let url = URL(string: apiBaseURL + "/users?login=\(username)") else {
            throw ConnectionError.networkError("Invalid users endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientID, forHTTPHeaderField: "Client-ID")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ConnectionError.networkError("No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ConnectionError.networkError("HTTP \(http.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]],
            let first = dataArray.first,
            let userID = first["id"] as? String
        else {
            throw ConnectionError.networkError("Unable to resolve username")
        }

        // Username resolved
        return userID
    }

}
