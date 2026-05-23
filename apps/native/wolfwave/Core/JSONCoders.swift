//
//  JSONCoders.swift
//  wolfwave
//
//  Created by MrDemonWolf, Inc. on 5/15/26.
//

import Foundation

/// Shared, pre-configured `JSONDecoder` and `JSONEncoder` instances.
///
/// Centralizes JSON coding configuration so services do not duplicate setup
/// (snake-case key conversion, ISO-8601 date strategy) at every call site.
///
/// Use the static properties directly:
/// ```swift
/// let response = try JSONCoders.snakeCase.decode(MyType.self, from: data)
/// ```
///
/// - Note: `JSONDecoder` / `JSONEncoder` are thread-safe for read-only use,
///   so a single shared instance per configuration is safe.
nonisolated enum JSONCoders {

    // MARK: - Decoders

    /// Decoder that converts `snake_case` JSON keys to `camelCase` Swift
    /// properties and parses ISO-8601 date strings.
    ///
    /// Use for Twitch Helix and most third-party APIs.
    static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Decoder that matches JSON keys to Swift properties verbatim and parses
    /// ISO-8601 date strings.
    ///
    /// Use when the API already uses `camelCase` keys (e.g. iTunes Search).
    static let camelCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Encoders

    /// Encoder that converts `camelCase` Swift properties to `snake_case`
    /// JSON keys and emits ISO-8601 date strings.
    static let snakeCaseEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Encoder that matches Swift property names verbatim and emits ISO-8601
    /// date strings.
    static let camelCaseEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
