import Foundation

struct WalletAddressInfo {
    let address: String
    let isChange: Bool
    let index: Int
}

@MainActor
protocol TransactionAccelerationRepository: AnyObject {
    func addressInfos(for walletId: UUID) -> [WalletAddressInfo]
    func walletMeta(for walletId: UUID) -> (name: String, basePath: String, network: BitcoinService.Network)?
    func changeAddress(for walletId: UUID) async -> String?
    func ensureGapLimit(for walletId: UUID, gap: Int) async
    func listAllAddresses() -> [String]
}

protocol ElectrumClientProtocol: AnyObject {
    var currentNetwork: BitcoinService.Network { get }
    func getUTXOs(for address: String) async throws -> [ElectrumUTXO]
    func getTransaction(_ txid: String) async throws -> String
    func broadcastTransaction(_ rawTx: String) async throws -> String
    func getCurrentBlockHeight() async throws -> Int
    func getAddressHistory(for address: String) async throws -> [[String: Any]]
    func getBlockTimestamp(height: Int) async throws -> Int
}

protocol FeeOptimizationServicing {
    func estimateFees(for transaction: BitcoinTransaction?) async throws -> [FeeOptimizationService.FeeEstimate]
}
