import XCTest
@testable import WALL_ET

final class CreateWalletUseCaseTests: XCTestCase {

    func testExecuteReturnsWalletAndMnemonicPersistedInKeychain() async throws {
        let expectedWallet = Wallet(name: "Test Wallet", type: .testnet)
        let walletRepository = WalletRepositoryStub(wallet: expectedWallet)
        let keychainService = KeychainServiceSpy()
        let sut = CreateWalletUseCase(walletRepository: walletRepository, keychainService: keychainService)

        let result = try await sut.execute(name: expectedWallet.name, type: expectedWallet.type)

        XCTAssertEqual(result.wallet, expectedWallet)
        XCTAssertFalse(result.mnemonic.isEmpty, "Mnemonic should not be empty")

        let key = "\(Constants.Keychain.walletSeed)_\(expectedWallet.name)"
        XCTAssertEqual(keychainService.savedStrings[key], result.mnemonic)
    }
}

private final class WalletRepositoryStub: WalletRepositoryProtocol {
    private let wallet: Wallet

    init(wallet: Wallet) {
        self.wallet = wallet
    }

    func createWallet(name: String, type: WalletType) async throws -> Wallet {
        XCTAssertEqual(name, wallet.name)
        XCTAssertEqual(type, wallet.type)
        return wallet
    }

    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet {
        fatalError("Not implemented")
    }

    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet {
        fatalError("Not implemented")
    }

    func getAllWallets() async throws -> [Wallet] { fatalError("Not implemented") }
    func getWallet(by id: UUID) async throws -> Wallet? { fatalError("Not implemented") }
    func updateWallet(_ wallet: Wallet) async throws { fatalError("Not implemented") }
    func deleteWallet(by id: UUID) async throws { fatalError("Not implemented") }
    func getActiveWallet() -> Wallet? { nil }
    func getBalance(for address: String) async throws -> Balance { fatalError("Not implemented") }
    func getTransactions(for address: String) async throws -> [Transaction] { fatalError("Not implemented") }
    func listAddresses(for walletId: UUID) -> [String] { [] }
}

private final class KeychainServiceSpy: KeychainServiceProtocol {
    private(set) var savedStrings: [String: String] = [:]
    private var savedData: [String: Data] = [:]

    func save(_ data: Data, for key: String) throws {
        savedData[key] = data
    }

    func load(for key: String) throws -> Data? {
        savedData[key]
    }

    func delete(for key: String) throws {
        savedData.removeValue(forKey: key)
        savedStrings.removeValue(forKey: key)
    }

    func saveString(_ string: String, for key: String) throws {
        savedStrings[key] = string
    }

    func loadString(for key: String) throws -> String? {
        savedStrings[key]
    }
}
