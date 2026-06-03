//
//  JSONCoders.swift
//  WolfWave
//
//  Created by Nathanial Henniges on 2026-05-16.
//  Copyright © 2026 MrDemonWolf, Inc. All rights reserved.
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

    /// Decoder with no key or date strategy applied. Matches Swift's default
    /// `JSONDecoder()` behavior.
    ///
    /// Use for on-disk formats whose schema is owned by us (explicit
    /// `CodingKeys` on the model, `Date`s stored via the default
    /// `deferredToDate` strategy). Sharing this instance avoids per-store
    /// `JSONDecoder()` allocations without changing the on-disk format.
    static let `default`: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    // MARK: - Encoders

    /// Encoder with no key or date strategy applied. Matches Swift's default
    /// `JSONEncoder()` behavior.
    ///
    /// Pair with `JSONCoders.default` for on-disk persistence whose format is
    /// owned by us (NDJSON play log, lifetime tally JSON).
    static let defaultEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()

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
