// Copyright © 2018 Stormbird PTE. LTD.

import Foundation
import PromiseKit
import AlphaWalletCore
import AlphaWalletOpenSea

public typealias Stats = AlphaWalletOpenSea.Stats

public final class OpenSea {
    private let analytics: AnalyticsLogger
    private let storage: Storage<[AddressAndRPCServer: OpenSeaAddressesToNonFungibles]> = .init(fileName: "OpenSea", defaultValue: [:])
    private let queue: DispatchQueue
    private lazy var networkProvider: OpenSeaNetworkProvider = OpenSeaNetworkProvider(analytics: analytics, queue: queue)

    public init(analytics: AnalyticsLogger, queue: DispatchQueue) {
        self.analytics = analytics
        self.queue = queue
    }

    public static func isServerSupported(_ server: RPCServer) -> Bool {
        switch server.serverWithEnhancedSupport {
        case .main, .rinkeby:
            return true
        case .xDai, .candle, .polygon, .binance_smart_chain, .heco, .arbitrum, .klaytnCypress, .klaytnBaobabTestnet, nil:
            return false

        }
    }

    public func nonFungible(wallet: Wallet, server: RPCServer) -> Promise<OpenSeaAddressesToNonFungibles> {
        let key: AddressAndRPCServer = .init(address: wallet.address, server: server)

        guard OpenSea.isServerSupported(key.server) else {
            return .value([:])
        }

        return fetchFromLocalAndRemotePromise(key: key)
    }

    private func fetchFromLocalAndRemotePromise(key: AddressAndRPCServer) -> Promise<OpenSeaAddressesToNonFungibles> {
        return networkProvider
            .fetchAssetsPromise(address: key.address, server: key.server)
            .map(on: queue, { [weak storage] result in
                if result.hasError {
                    let merged = (storage?.value[key] ?? [:])
                        .merging(result.result) { Array(Set($0 + $1)) }

                    if merged.isEmpty {
                        //no-op
                    } else {
                        storage?.value[key] = merged
                    }
                } else {
                    storage?.value[key] = result.result
                }

                return storage?.value[key] ?? result.result
            })
    }

    public func fetchAssetImageUrl(for value: Eip155URL, server: RPCServer) -> Promise<URL> {
        networkProvider.fetchAssetImageUrl(for: value, server: server)
    }

    public func collectionStats(slug: String, server: RPCServer) -> Promise<Stats> {
        networkProvider.collectionStats(slug: slug, server: server)
    }
}
