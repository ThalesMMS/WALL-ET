import XCTest
@testable import WALL_ET

final class BackupViewModelTests: XCTestCase {

    func testLoadSeedPhraseReturnsPersistedWords() {
        let repository = MockWalletRepository()
        let keychain = MockKeychainService()
        let wallet = Wallet(name: "Primary", type: .testnet)
        repository.activeWallet = wallet
        let mnemonic = "abandon ability able about above absent absorb abstract"
        keychain.strings["\(Constants.Keychain.walletSeed)_\(wallet.name)"] = mnemonic
        let viewModel = BackupViewModel(walletRepository: repository, keychainService: keychain)

        viewModel.loadSeedPhrase()

        guard case .loaded(let words) = viewModel.state else {
            return XCTFail("Expected loaded state")
        }

        XCTAssertEqual(words, mnemonic.split(separator: " ").map(String.init))
    }

    func testLoadSeedPhraseHandlesWatchOnlyWallet() {
        let repository = MockWalletRepository()
        let keychain = MockKeychainService()
        repository.activeWallet = Wallet(name: "Watcher", type: .bitcoin, isWatchOnly: true)
        let viewModel = BackupViewModel(walletRepository: repository, keychainService: keychain)

        viewModel.loadSeedPhrase()

        guard case .noSeed(let message) = viewModel.state else {
            return XCTFail("Expected noSeed state")
        }

        XCTAssertEqual(message, "Watch-only wallets do not have a seed phrase.")
    }

    func testLoadSeedPhraseHandlesKeychainErrors() {
        let repository = MockWalletRepository()
        let keychain = MockKeychainService()
        repository.activeWallet = Wallet(name: "Primary", type: .testnet)
        keychain.error = TestError.keychainFailure
        let viewModel = BackupViewModel(walletRepository: repository, keychainService: keychain)

        viewModel.loadSeedPhrase()

        guard case .noSeed(let message) = viewModel.state else {
            return XCTFail("Expected noSeed state")
        }

        XCTAssertEqual(message, "Failed to load seed phrase: Keychain failure")
    }
}

private final class MockWalletRepository: WalletRepositoryProtocol, BackupActiveWalletProviding {
    var activeWallet: Wallet?

    func createWallet(name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func getAllWallets() async throws -> [Wallet] { fatalError("Not implemented") }
    func getWallet(by id: UUID) async throws -> Wallet? { fatalError("Not implemented") }
    func updateWallet(_ wallet: Wallet) async throws { fatalError("Not implemented") }
    func deleteWallet(by id: UUID) async throws { fatalError("Not implemented") }
    func getBalance(for address: String) async throws -> Balance { fatalError("Not implemented") }
    func getTransactions(for address: String) async throws -> [Transaction] { fatalError("Not implemented") }

    func getActiveWallet() -> Wallet? {
        activeWallet
    }
}

private final class MockKeychainService: KeychainServiceProtocol {
    var strings: [String: String] = [:]
    var error: Error?

    func save(_ data: Data, for key: String) throws {
        fatalError("Not implemented")
    }

    func load(for key: String) throws -> Data? {
        fatalError("Not implemented")
    }

    func delete(for key: String) throws {
        strings.removeValue(forKey: key)
    }

    func saveString(_ string: String, for key: String) throws {
        strings[key] = string
    }

    func loadString(for key: String) throws -> String? {
        if let error { throw error }
        return strings[key]
    }
}

private enum TestError: Error, LocalizedError {
    case keychainFailure

    var errorDescription: String? {
        "Keychain failure"
    }
}
