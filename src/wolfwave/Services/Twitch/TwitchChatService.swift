//
//  TwitchChatService.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 1/8/26.
//

import Foundation

// MARK: - Chat Message Models

/// Service managing Twitch chat connection and bot commands via EventSub WebSocket.
///
/// This service handles:
/// - WebSocket connection to Twitch EventSub
/// - EventSub subscription management for chat messages
/// - Bot command processing via `BotCommandDispatcher`
/// - Message sending and replying
/// - OAuth token validation
/// - User identity resolution
///
/// Example usage:
/// ```swift
/// let service = TwitchChatService()
/// try await service.connectToChannel(
///     channelName: "streamer",
///     token: oauthToken,
///     clientID: clientID
/// )
/// service.sendMessage("Hello, chat!")
/// ```
final class TwitchChatService {
    
    /// Represents an incoming chat message from Twitch EventSub.
    struct ChatMessage {
        let messageID: String
        let username: String
        let userID: String
        let message: String
        let channel: String
        let badges: [Badge]
        let reply: Reply?

        /// A Twitch chat badge (e.g., subscriber, moderator).
        struct Badge {
            let setID: String
            let id: String
            let info: String
        }

        /// Information about a message being replied to.
        struct Reply {
            let parentMessageID: String
            let parentMessageBody: String
            let parentUserID: String
            let parentUsername: String
        }
    }

    // MARK: - Connection Errors

    /// Errors that can occur during Twitch connection and API operations.
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

    // MARK: - Bot Identity
    
    /// Bot identity information returned from Twitch users endpoint.
    struct BotIdentity {
        let userID: String
        let login: String
        let displayName: String
    }

    // MARK: - Properties
    
    /// Base URL for Twitch Helix API
    private let apiBaseURL = "https://api.twitch.tv/helix"
    
    /// Dispatcher for routing chat messages to bot commands
    private let commandDispatcher = BotCommandDispatcher()

    /// Active WebSocket connection to Twitch EventSub
    private var webSocketTask: URLSessionWebSocketTask?
    
    /// Session ID received from EventSub welcome message
    private var sessionID: String?

    /// The broadcaster's Twitch user ID
    private var broadcasterID: String?
    
    /// The bot's Twitch user ID
    private var botID: String?
    
    /// OAuth token for API authentication
    private var oauthToken: String?
    
    /// Twitch application client ID
    private var clientID: String?
    
    /// The bot's display username
    private var botUsername: String?
    
    /// Whether to log debug information for WebSocket messages
    var debugLoggingEnabled = false

    /// Callback to get current song info for bot commands
    var getCurrentSongInfo: (() -> String)?
    
    /// Callback to get last song info for bot commands
    var getLastSongInfo: (() -> String)?
    
    /// Whether bot commands are enabled
    var commandsEnabled = true
    
    /// Callback fired when a chat message is received
    var onMessageReceived: ((ChatMessage) -> Void)?

    /// Callback fired when connection state changes
    var onConnectionStateChanged: ((Bool) -> Void)?

    /// Notification posted when connection state changes
    static let connectionStateChanged = NSNotification.Name("TwitchChatConnectionStateChanged")

    // MARK: - Public Methods

    /// Joins a Twitch channel using pre-resolved IDs.
    ///
    /// - Parameters:
    ///   - broadcasterID: The broadcaster's Twitch user ID
    ///   - botID: The bot's Twitch user ID
    ///   - token: OAuth access token with chat scopes
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if credentials are invalid or missing
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

        commandDispatcher.setCurrentSongInfo { [weak self] in
            self?.getCurrentSongInfo?() ?? "No track currently playing"
        }

        commandDispatcher.setLastSongInfo { [weak self] in
            self?.getLastSongInfo?() ?? "No previous track available"
        }

        onConnectionStateChanged?(true)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": true]
        )
        Log.info("Twitch: Joining channel \(broadcasterID)", category: "TwitchChat")

        connectToEventSub()
    }

    /// Connects to a Twitch channel by name, resolving usernames to IDs.
    ///
    /// This is the main entry point for connecting to chat. It:
    /// 1. Resolves bot identity if not already cached
    /// 2. Resolves broadcaster username to user ID
    /// 3. Calls `joinChannel` with resolved IDs
    ///
    /// - Parameters:
    ///   - channelName: The broadcaster's Twitch username
    ///   - token: OAuth access token with chat scopes
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if resolution or connection fails
    func connectToChannel(channelName: String, token: String, clientID: String) async throws {
        guard !channelName.isEmpty, !token.isEmpty else {
            Log.error("Twitch: Invalid channel name or token", category: "TwitchChat")
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            Log.error("Twitch: Missing client ID for channel connect", category: "TwitchChat")
            throw ConnectionError.missingClientID
        }

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

        let broadcasterUserID = try await resolveUsername(
            channelName,
            token: token,
            clientID: clientID
        )

        guard !broadcasterUserID.isEmpty else {
            throw ConnectionError.networkError("Could not resolve channel name to user ID")
        }

        try joinChannel(
            broadcasterID: broadcasterUserID,
            botID: botUserID,
            token: token,
            clientID: clientID
        )

        Log.info("Twitch: Connected to channel \(channelName)", category: "TwitchChat")
    }

    /// Resolves and stores the bot's identity (user ID and username).
    ///
    /// - Parameters:
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if identity resolution fails
    func resolveBotIdentity(token: String, clientID: String) async throws {
        guard !token.isEmpty else {
            throw ConnectionError.invalidCredentials
        }

        guard !clientID.isEmpty else {
            throw ConnectionError.missingClientID
        }

        let identity = try await fetchBotIdentity(token: token, clientID: clientID)
        let resolvedUsername = identity.displayName.isEmpty ? identity.login : identity.displayName

        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)

        Log.debug(
            "Twitch: Resolved bot identity - username: \(resolvedUsername)",
            category: "TwitchChat")
    }

    /// Static method to resolve bot identity without an instance.
    ///
    /// Useful for resolving identity before creating a service instance.
    ///
    /// - Parameters:
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Throws: `ConnectionError` if identity resolution fails
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

        try KeychainService.saveTwitchUsername(resolvedUsername)
        try KeychainService.saveTwitchBotUserID(identity.userID)

        Log.debug(
            "Twitch: Resolved bot identity (static) - username: \(resolvedUsername)",
            category: "TwitchChat")
    }

    /// Resolves the Twitch Client ID from environment or Info.plist.
    ///
    /// Checks in order:
    /// 1. `TWITCH_CLIENT_ID` environment variable
    /// 2. `TwitchClientID` key in Info.plist
    ///
    /// - Returns: The client ID if found, otherwise nil
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

    /// Fetches the bot's identity (user ID and usernames) from Twitch.
    ///
    /// Uses the `/users` endpoint to retrieve information about the authenticated user.
    ///
    /// - Parameters:
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Returns: The bot's identity information
    /// - Throws: `ConnectionError` if the API request fails or returns 401 Unauthorized
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

    /// Leaves the current channel and disconnects from EventSub.
    ///
    /// Clears all stored credentials and session state.
    func leaveChannel() {
        disconnectFromEventSub()

        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil

        onConnectionStateChanged?(false)
        NotificationCenter.default.post(
            name: TwitchChatService.connectionStateChanged,
            object: nil,
            userInfo: ["isConnected": false]
        )
        Log.info("Twitch: Left channel", category: "TwitchChat")
    }

    /// Validates an OAuth token with Twitch and verifies required scopes.
    ///
    /// Calls the `/oauth2/validate` endpoint to check token validity and scope permissions.
    ///
    /// - Parameters:
    ///   - token: The OAuth access token (raw string, not prefixed)
    ///   - requiredScopes: Scopes that must be present (default: chat read/write scopes)
    /// - Returns: True if the token is valid and has all required scopes
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

    /// Sends the connection confirmation message to the channel.
    ///
    /// Called automatically when the bot successfully subscribes to channel chat messages.
    /// Sends: "WolfWave Application is connected! 🎵"
    func sendConnectionMessage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.sendMessage("WolfWave Application is connected! 🎵")
        }
    }

    /// Sends a message to the current channel.
    ///
    /// - Parameter message: The message text to send
    func sendMessage(_ message: String) {
        sendMessage(message, replyTo: nil)
    }

    /// Sends a message that replies to another message.
    ///
    /// - Parameters:
    ///   - message: The message text to send
    ///   - parentMessageID: The ID of the message to reply to, or nil for a regular message
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

    // MARK: - Message Parsing

    /// Parses and handles an incoming message from EventSub.
    ///
    /// Extracts message data, processes bot commands if enabled, and fires callbacks.
    ///
    /// - Parameter json: The EventSub payload JSON
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

        if commandsEnabled, let response = commandDispatcher.processMessage(text) {
            sendMessage(response, replyTo: messageID)
        }

        onMessageReceived?(chatMessage)
    }

    // MARK: - API Requests

    /// Sends an API request to the Twitch Helix API.
    ///
    /// - Parameters:
    ///   - method: The HTTP method (GET, POST, etc.)
    ///   - endpoint: The API endpoint path (e.g., "/chat/messages")
    ///   - body: Optional JSON body dictionary
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    ///   - completion: Callback with the result (Data or Error)
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

    // MARK: - WebSocket Management

    /// Connects to the Twitch EventSub WebSocket endpoint.
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

    /// Disconnects from the EventSub WebSocket and clears session state.
    private func disconnectFromEventSub() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        sessionID = nil
        Log.info("Twitch: Disconnected from EventSub WebSocket", category: "TwitchChat")
    }

    /// Continuously receives messages from the WebSocket connection.
    ///
    /// Recursively calls itself to maintain the message receive loop.
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

                self.receiveWebSocketMessage()

            case .failure(let error):
                Log.error(
                    "Twitch: WebSocket error - \(error.localizedDescription)",
                    category: "TwitchChat")
                self.onConnectionStateChanged?(false)
            }
        }
    }

    /// Handles a received WebSocket message.
    ///
    /// Parses JSON and routes to appropriate handler based on message type.
    ///
    /// - Parameter text: The raw WebSocket message text
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
            break
        default:
            break
        }
    }

    /// Handles the session_welcome message from EventSub.
    ///
    /// Extracts the session ID and subscribes to channel chat messages.
    ///
    /// - Parameter json: The session_welcome message JSON
    private func handleSessionWelcome(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
            let session = payload["session"] as? [String: Any],
            let sessionID = session["id"] as? String
        else {
            Log.error("Twitch: Failed to parse session ID", category: "TwitchChat")
            return
        }

        self.sessionID = sessionID

        subscribeToChannelChatMessage()
    }

    /// Handles notification messages containing EventSub events.
    ///
    /// - Parameter json: The notification message JSON
    private func handleNotification(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any] else { return }
        handleEventSubMessage(payload)
    }

    // MARK: - EventSub Subscriptions

    /// Subscribes to the channel.chat.message EventSub event.
    ///
    /// Called after receiving the session_welcome message with a valid session ID.
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

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                Log.error(
                    "Twitch: EventSub subscription error - \(error.localizedDescription)",
                    category: "TwitchChat")
                return
            }

            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) {
                    Log.info("Twitch: Connected to chat", category: "TwitchChat")
                    self?.sendConnectionMessage()
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

    // MARK: - Username Resolution

    /// Resolves a Twitch username to a user ID.
    ///
    /// - Parameters:
    ///   - username: The Twitch username to resolve
    ///   - token: OAuth access token
    ///   - clientID: Twitch application client ID
    /// - Returns: The user ID
    /// - Throws: `ConnectionError` if the username cannot be resolved
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

        return userID
    }

}
