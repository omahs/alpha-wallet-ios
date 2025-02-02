// Copyright © 2020 Stormbird PTE. LTD.

import Foundation
import BigInt
import PromiseKit 
import AlphaWalletWeb3

public class GetBlockTimestamp {
    private static var blockTimestampCache = AtomicDictionary<RPCServer, [BigUInt: Promise<Date>]>()

    public func getBlockTimestamp(_ blockNumber: BigUInt, onServer server: RPCServer) -> Promise<Date> {
        var cacheForServer = Self.blockTimestampCache[server] ?? .init()
        if let datePromise = cacheForServer[blockNumber] {
            return datePromise
        }

        guard let web3 = try? Web3.instance(for: server, timeout: 6) else {
            return Promise(error: Web3Error(description: "Error creating web3 for: \(server.rpcURL) + \(server.chainID)"))
        }

        let promise: Promise<Date> = firstly {
            Web3.Eth(web3: web3).getBlockByNumberPromise(blockNumber)
        }.map(on: web3.queue, { $0.timestamp })

        cacheForServer[blockNumber] = promise
        Self.blockTimestampCache[server] = cacheForServer

        return promise
    }
}

