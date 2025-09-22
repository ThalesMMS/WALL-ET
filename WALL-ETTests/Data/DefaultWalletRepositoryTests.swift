import XCTest
import Combine
@testable import WALL_ET

final class DefaultWalletRepositoryTests: XCTestCase {
    func testGetTransactionsReturnsSortedTransactionsFromAdapter() async throws {
        let satoshisPerBitcoin = Double(Constants.Bitcoin.satoshisPerBitcoin)
        let walletAddress = "tb1qwalletaddress"
        let receivedAmountSats: Int64 = 25_000
        let sentAmountSats: Int64 = 10_000

        let newerDate = Date()
        let olderDate = newerDate.addingTimeInterval(-3600)

        let models: [TransactionModel] = [
            TransactionModel(
                id: "tx-old",
                type: .sent,
                amount: Double(sentAmountSats) / satoshisPerBitcoin,
                fee: Double(500) / satoshisPerBitcoin,
                address: "tb1qdestination",
                date: olderDate,
                status: .confirmed,
                confirmations: 12
            ),
            TransactionModel(
                id: "tx-new",
                type: .received,
                amount: Double(receivedAmountSats) / satoshisPerBitcoin,
                fee: 0,
                address: walletAddress,
                date: newerDate,
                status: .pending,
                confirmations: 2
            )
        ]

        let adapter = TransactionsAdapterStub(models: models)
        let repository = DefaultWalletRepository(
            keychainService: KeychainServiceStub(),
            transactionsAdapter: adapter
        )

        let transactions = try await repository.getTransactions(for: walletAddress)

        XCTAssertEqual(adapter.requestedLimit, 50)
        XCTAssertEqual(transactions.map { $0.hash }, ["tx-new", "tx-old"])
        XCTAssertEqual(transactions[0].amount, receivedAmountSats)
        XCTAssertEqual(transactions[0].fee, 0)
        XCTAssertNil(transactions[0].fromAddress)
        XCTAssertEqual(transactions[0].toAddress, walletAddress)
        XCTAssertEqual(transactions[0].status, .pending)
        XCTAssertEqual(transactions[0].confirmations, 2)

        XCTAssertEqual(transactions[1].amount, sentAmountSats)
        XCTAssertEqual(transactions[1].fee, 500)
        XCTAssertEqual(transactions[1].fromAddress, walletAddress)
        XCTAssertEqual(transactions[1].toAddress, "tb1qdestination")
        XCTAssertEqual(transactions[1].status, .confirmed)
        XCTAssertEqual(transactions[1].confirmations, 12)
    }

    func testWalletDerivationServiceSavesAndLoadsMnemonic() throws {
        let keychain = KeychainServiceStub()
        let service = WalletDerivationService(keychain: keychain)
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

        try service.saveMnemonic(mnemonic, walletName: "Primary")

        XCTAssertEqual(try service.mnemonic(for: "Primary"), mnemonic)
    }

    func testWalletDerivationServiceDerivesFirstAccount() throws {
        let keychain = KeychainServiceStub()
        let service = WalletDerivationService(keychain: keychain)
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

        try service.saveMnemonic(mnemonic, walletName: "Primary")

        let derivation = try service.deriveFirstAccount(for: "Primary", type: .testnet)
        XCTAssertEqual(derivation.accountBasePath, "m/84'/1'/0'")
        XCTAssertEqual(derivation.network, .testnet)
        XCTAssertEqual(derivation.coinType, 1)

        let expectedSeed = MnemonicService.shared.mnemonicToSeed(mnemonic)
        let (_, expectedAddress) = MnemonicService.shared.deriveAddress(
            from: expectedSeed,
            path: "m/84'/1'/0'/0/0",
            network: .testnet
        )

        XCTAssertEqual(derivation.address, expectedAddress)
    }

    func testWalletDerivationServiceThrowsWhenMnemonicMissing() {
        let service = WalletDerivationService(keychain: KeychainServiceStub())

        XCTAssertThrowsError(
            try service.deriveAddress(
                for: "Unknown",
                path: "m/84'/1'/0'/0/0",
                network: .testnet
            )
        ) { error in
            XCTAssertEqual(error as? WalletDerivationError, .mnemonicNotFound(name: "Unknown"))
        }
    }
}

private final class TransactionsAdapterStub: TransactionsAdapterProtocol {
    private let itemsSubject = PassthroughSubject<[TransactionModel], Never>()
    private let blockSubject = PassthroughSubject<Void, Never>()
    private let models: [TransactionModel]

    private(set) var requestedLimit: Int?

    init(models: [TransactionModel]) {
        self.models = models
    }

    var itemsUpdatedPublisher: AnyPublisher<[TransactionModel], Never> {
        itemsSubject.eraseToAnyPublisher()
    }

    var lastBlockUpdatedPublisher: AnyPublisher<Void, Never> {
        blockSubject.eraseToAnyPublisher()
    }

    var lastBlockInfo: (height: Int, timestamp: Int)? { nil }

    func transactionsSingle(paginationData: String?, limit: Int) async throws -> [TransactionModel] {
        requestedLimit = limit
        return Array(models.prefix(limit))
    }
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
