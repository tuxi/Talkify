//
//  NetworkPolicy.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/1.
//

import Foundation
import Network

@MainActor
@Observable
public final class PreviewNetworkPolicy {
    public enum ConnectionKind: Sendable, Equatable {
        case unavailable
        case wifi
        case cellular
        case wiredEthernet
        case other
    }

    public private(set) var isConnected: Bool = true
    public private(set) var connectionKind: ConnectionKind = .other

    public var allowAutoPlayOnCellular: Bool
    public var allowPreloadOnCellular: Bool

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "preview.network.policy")

    public init(
        allowAutoPlayOnCellular: Bool = true,
        allowPreloadOnCellular: Bool = false
    ) {
        self.allowAutoPlayOnCellular = allowAutoPlayOnCellular
        self.allowPreloadOnCellular = allowPreloadOnCellular

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied

                if path.usesInterfaceType(.wifi) {
                    self.connectionKind = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionKind = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionKind = .wiredEthernet
                } else if path.status != .satisfied {
                    self.connectionKind = .unavailable
                } else {
                    self.connectionKind = .other
                }
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    public var canAutoPlay: Bool {
        guard isConnected else { return false }
        if connectionKind == .cellular {
            return allowAutoPlayOnCellular
        }
        return true
    }

    public var canPreload: Bool {
        guard isConnected else { return false }
        if connectionKind == .cellular {
            return allowPreloadOnCellular
        }
        return true
    }
}
