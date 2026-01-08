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
        Log.info(
            "Twitch: Joining channel - broadcasterID: \(broadcasterID), botID: \(botID)",
            category: "TwitchChat")
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

        // Send activation message to chat
        sendMessage("WolfWave activated! 🎵 Use !song to check what's playing")
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
        Log.info("Twitch: Fetching bot identity from Helix /users endpoint", category: "TwitchChat")
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

        Log.debug("Twitch: Users endpoint returned HTTP \(http.statusCode)", category: "TwitchChat")
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
        Log.info(
            "Twitch: Bot identity resolved - login: \(login), displayName: \(displayName), userID: \(userID)",
            category: "TwitchChat")

        botID = userID
        botUsername = displayName

        return BotIdentity(userID: userID, login: login, displayName: displayName)
    }

    /// Leave the channel
    func leaveChannel() {
        broadcasterID = nil
        botID = nil
        oauthToken = nil
        clientID = nil

        onConnectionStateChanged?(false)
        Log.info("Twitch: Left channel", category: "TwitchChat")
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
                        Log.debug("Twitch: Message sent", category: "TwitchChat")
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
}
