//
//  NetworkInfoService.swift
//  wolfwave
//

import Darwin
import Foundation

/// Off-main helper for resolving the device's primary non-loopback IPv4 address.
///
/// `getifaddrs` walks every network interface and was previously invoked from a SwiftUI view's
/// computed property — meaning it ran on every body render. This actor isolates the syscall and
/// callers cache the result in `@State`, refreshing only on network path changes.
actor NetworkInfoService {
    static let shared = NetworkInfoService()

    /// Returns the first non-loopback, up, running IPv4 address, or `nil` if not connected.
    func primaryIPv4() -> String? {
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
                return String(cString: host)
            }
            ptr = interface.pointee.ifa_next
        }
        return nil
    }
}
