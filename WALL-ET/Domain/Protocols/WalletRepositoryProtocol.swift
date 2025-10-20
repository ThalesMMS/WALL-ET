import Foundation
import Combine

protocol WalletRepositoryProtocol {
    func createWallet(name: String, type: WalletType) async throws -> Wallet
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet
    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet
    func getAllWallets() async throws -> [Wallet]
    func getWallet(by id: UUID) async throws -> Wallet?
    func updateWallet(_ wallet: Wallet) async throws
    func deleteWallet(by id: UUID) async throws
    func getActiveWallet() -> Wallet?
    func getBalance(for address: String) async throws -> Balance
    func getBalances(for addresses: [String]) async throws -> [String: Balance]
    func getTransactions(for address: String) async throws -> [Transaction]
    func listAddresses(for walletId: UUID) -> [String]
}

extension WalletRepositoryProtocol {
    func getActiveWallet() -> Wallet? { nil }

    func getBalances(for addresses: [String]) async throws -> [String: Balance] {
        var results: [String: Balance] = [:]
        for address in addresses {
            results[address] = try await getBalance(for: address)
        }
        return results
    }

    func listAddresses(for walletId: UUID) -> [String] {
        []
    }
}
