//
//  NetworkInfoService.swift
//  wolfwave
//

import Darwin
import Foundation
import Network
import os

/// Off-main helper for resolving the device's primary non-loopback IPv4 address.
///
/// `getifaddrs` walks every network interface. The result is cached behind a lock so SwiftUI
/// views can read the last-known IP synchronously (no `await`) on first render, eliminating the
/// "pop-in" lag previously seen when opening the Now-Playing Server settings.
///
/// Refreshes still serialize through the actor; reads hit the lock-protected static cache.
actor NetworkInfoService {
    static let shared = NetworkInfoService()

    // MARK: - Cache

    private static let cacheLock = OSAllocatedUnfairLock<String?>(initialState: nil)

    // MARK: - Shared path monitor

    /// One process-lifetime `NWPathMonitor`. Views consume `pathUpdates` instead of allocating
    /// their own monitor each appear — switching settings panes no longer pays the
    /// `NWPathMonitor.start` cost.
    private static let pathMonitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: .global(qos: .utility))
        return monitor
    }()

    private static let pathContinuationsLock = OSAllocatedUnfairLock<[UUID: AsyncStream<NWPath>.Continuation]>(initialState: [:])

    private static let pathHandlerInstalled: Bool = {
        pathMonitor.pathUpdateHandler = { path in
            let continuations = pathContinuationsLock.withLock { $0 }
            for cont in continuations.values { cont.yield(path) }
        }
        return true
    }()

    /// Shared `AsyncStream` of network path updates. Each subscriber gets its own stream backed by
    /// the single process-wide monitor. Cancelling the consuming task removes the subscription.
    nonisolated static func pathUpdates() -> AsyncStream<NWPath> {
        _ = pathHandlerInstalled
        return AsyncStream { continuation in
            let id = UUID()
            pathContinuationsLock.withLock { $0[id] = continuation }
            continuation.onTermination = { _ in
                pathContinuationsLock.withLock { _ = $0.removeValue(forKey: id) }
            }
        }
    }

    /// Last-known IPv4 address, readable from any thread. `nil` until first refresh completes.
    static var cachedIPv4: String? {
        cacheLock.withLock { $0 }
    }

    /// Synchronously walks `getifaddrs` and primes the cache. Call once at app launch on a
    /// background thread so the first Settings open always finds a hot cache.
    @discardableResult
    static func warmCache() -> String? {
        let value = computePrimaryIPv4()
        cacheLock.withLock { $0 = value }
        return value
    }

    // MARK: - Public API

    /// Returns the cached IPv4 address if available, otherwise walks `getifaddrs` and caches the result.
    func primaryIPv4() -> String? {
        if let cached = Self.cachedIPv4 { return cached }
        return refreshIPv4()
    }

    /// Forces a fresh `getifaddrs` walk and updates the cache. Returns the new value.
    @discardableResult
    func refreshIPv4() -> String? {
        let value = Self.computePrimaryIPv4()
        Self.cacheLock.withLock { $0 = value }
        return value
    }

    // MARK: - Private

    /// Returns the first non-loopback, up, running IPv4 address, or `nil` if not connected.
    private static func computePrimaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let interface = ptr {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = flags & Int32(IFF_UP) != 0
            let isRunning = flags & Int32(IFF_RUNNING) != 0
            let isLoopback = flags & Int32(IFF_LOOPBACK) != 0

            if let addr = interface.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_INET),
               isUp, isRunning, !isLoopback {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                            &host, socklen_t(host.count),
                            nil, 0, NI_NUMERICHOST)
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                return String(decoding: bytes, as: UTF8.self)
            }
            ptr = interface.pointee.ifa_next
        }
        return nil
    }
}
