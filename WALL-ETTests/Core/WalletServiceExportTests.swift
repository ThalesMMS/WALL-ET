import XCTest
@testable import WALL_ET

final class WalletServiceExportTests: XCTestCase {
    func testExportWalletProducesExpectedPayloadForSoftwareWallet() async throws {
        let walletId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_695_000_000)
        let accounts = [Account(index: 0, address: "tb1qexampleaddress", publicKey: "pub", balance: Balance())]
        let wallet = Wallet(
            id: walletId,
            name: "Primary",
            type: .testnet,
            createdAt: createdAt,
            accounts: accounts,
            isWatchOnly: false
        )

        let repository = WalletRepositoryStub(wallet: wallet)
        let keychain = KeychainServiceStub()
        try keychain.saveString("abandon abandon abandon", for: "\(Constants.Keychain.walletSeed)_Primary")

        let service = WalletService(repository: repository, keychainService: keychain)
        let exportString = try await service.exportWallet(walletId)
        let data = exportString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WalletExportPayload.self, from: data)

        XCTAssertEqual(payload.version, 1)
        XCTAssertEqual(payload.metadata.id, walletId.uuidString)
        XCTAssertEqual(payload.metadata.name, "Primary")
        XCTAssertEqual(payload.metadata.kind, .software)
        XCTAssertEqual(payload.metadata.network, "testnet")
        XCTAssertEqual(payload.metadata.derivationPath, "m/84'/1'/0'")
        XCTAssertEqual(payload.metadata.createdAt, createdAt)
        XCTAssertFalse(payload.addresses.isEmpty)
        XCTAssertEqual(payload.addresses[0], .init(index: 0, address: "tb1qexampleaddress"))
        XCTAssertEqual(payload.mnemonic, "abandon abandon abandon")
    }

    func testExportWalletOmitsMnemonicForWatchOnlyWallet() async throws {
        let walletId = UUID()
        let wallet = Wallet(
            id: walletId,
            name: "Watch",
            type: .testnet,
            createdAt: Date(),
            accounts: [Account(index: 0, address: "tb1qwatchaddress", publicKey: "")],
            isWatchOnly: true
        )

        let service = WalletService(
            repository: WalletRepositoryStub(wallet: wallet),
            keychainService: KeychainServiceStub()
        )

        let exportString = try await service.exportWallet(walletId)
        let data = exportString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WalletExportPayload.self, from: data)

        XCTAssertEqual(payload.metadata.kind, .watchOnly)
        XCTAssertNil(payload.mnemonic)
    }

    func testExportWalletThrowsWhenMnemonicMissing() async {
        let walletId = UUID()
        let wallet = Wallet(
            id: walletId,
            name: "Primary",
            type: .bitcoin,
            createdAt: Date(),
            accounts: [Account(index: 0, address: "bc1qexample", publicKey: "")],
            isWatchOnly: false
        )

        let service = WalletService(
            repository: WalletRepositoryStub(wallet: wallet),
            keychainService: KeychainServiceStub()
        )

        await XCTAssertThrowsError(try await service.exportWallet(walletId)) { error in
            XCTAssertEqual(error as? WalletExportError, .mnemonicMissing)
        }
    }
}

private final class WalletRepositoryStub: WalletDataRepository {
    var storedWallet: Wallet?

    init(wallet: Wallet?) {
        self.storedWallet = wallet
    }

    func fetchWallets() async throws -> [Wallet] { storedWallet.map { [$0] } ?? [] }
    func createWallet(name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func deleteWallet(by id: UUID) async throws {}
    func getWallet(by id: UUID) async throws -> Wallet? { storedWallet?.id == id ? storedWallet : nil }
    func listAllAddresses() -> [String] { [] }
    func getActiveWallet() -> Wallet? { nil }
    func setActiveWallet(id: UUID) {}
    func ensureGapLimit(for walletId: UUID, gap: Int) async {}
    func getNextReceiveAddress(for walletId: UUID, gap: Int) async -> String? { nil }
}

private final class KeychainServiceStub: KeychainServiceProtocol {
    private var storage: [String: Data] = [:]

    func save(_ data: Data, for key: String) throws {
        storage[key] = data
    }

    func load(for key: String) throws -> Data? {
        storage[key]
    }

    func delete(for key: String) throws {
        storage.removeValue(forKey: key)
    }

    func saveString(_ string: String, for key: String) throws {
        storage[key] = Data(string.utf8)
    }

    func loadString(for key: String) throws -> String? {
        guard let data = storage[key] else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
