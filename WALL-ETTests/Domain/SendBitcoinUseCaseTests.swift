import XCTest
@testable import WALL_ET

final class SendBitcoinUseCaseTests: XCTestCase {

    func testExecuteAggregatesBalancesAcrossAllAddresses() async throws {
        let wallet = Wallet(
            name: "Test Wallet",
            type: .testnet,
            accounts: [
                Account(index: 0, address: "addr-external-1", publicKey: "pub1"),
                Account(index: 1, address: "addr-external-2", publicKey: "pub2")
            ]
        )

        let repository = WalletRepositoryMock()
        repository.addressesByWallet[wallet.id] = ["addr-external-1", "addr-external-2", "addr-change-1"]
        repository.balances = [
            "addr-external-1": Balance(confirmed: 25_000),
            "addr-external-2": Balance(confirmed: 15_000),
            "addr-change-1": Balance(confirmed: 10_000)
        ]

        let transactionService = TransactionServiceMock()
        let feeService = FeeServiceMock()
        let sut = SendBitcoinUseCase(
            walletRepository: repository,
            transactionService: transactionService,
            feeService: feeService
        )

        let request = SendTransactionRequest(
            fromWallet: wallet,
            toAddress: "tb1q1234567890abcdef1234567890abcdef1234",
            amount: 45_000,
            feeRate: 5,
            memo: "Test memo"
        )

        let transaction = try await sut.execute(request: request)

        XCTAssertTrue(transactionService.sendCalled)
        XCTAssertEqual(transaction.amount, request.amount)
        XCTAssertEqual(transaction.toAddress, request.toAddress)
        XCTAssertEqual(repository.lastRequestedAddresses?.sorted(), ["addr-change-1", "addr-external-1", "addr-external-2"])
    }
}

private final class WalletRepositoryMock: WalletRepositoryProtocol {
    var addressesByWallet: [UUID: [String]] = [:]
    var balances: [String: Balance] = [:]
    private(set) var lastRequestedAddresses: [String]?

    func createWallet(name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func getAllWallets() async throws -> [Wallet] { fatalError("Not implemented") }
    func getWallet(by id: UUID) async throws -> Wallet? { fatalError("Not implemented") }
    func updateWallet(_ wallet: Wallet) async throws { fatalError("Not implemented") }
    func deleteWallet(by id: UUID) async throws { fatalError("Not implemented") }

    func getBalance(for address: String) async throws -> Balance {
        balances[address] ?? Balance()
    }

    func getBalances(for addresses: [String]) async throws -> [String: Balance] {
        lastRequestedAddresses = addresses
        var result: [String: Balance] = [:]
        for address in addresses {
            result[address] = balances[address] ?? Balance()
        }
        return result
    }

    func getTransactions(for address: String) async throws -> [Transaction] { fatalError("Not implemented") }

    func listAddresses(for walletId: UUID) -> [String] {
        addressesByWallet[walletId] ?? []
    }
}

private final class TransactionServiceMock: TransactionServiceProtocol {
    private(set) var sendCalled = false

    func fetchTransactions(page: Int, pageSize: Int) async throws -> [TransactionModel] { fatalError("Not implemented") }
    func fetchRecentTransactions(limit: Int) async throws -> [TransactionModel] { fatalError("Not implemented") }
    func fetchTransaction(by id: String) async throws -> TransactionModel { fatalError("Not implemented") }

    func sendBitcoin(to address: String, amount: Double, fee: Double, note: String?) async throws -> TransactionModel {
        sendCalled = true
        return TransactionModel(
            id: "tx-id",
            type: .sent,
            amount: amount,
            fee: fee,
            address: address,
            date: Date(),
            status: .pending,
            confirmations: 0
        )
    }

    func speedUpTransaction(_ transactionId: String) async throws { fatalError("Not implemented") }
    func cancelTransaction(_ transactionId: String) async throws { fatalError("Not implemented") }
    func exportTransactions(_ transactions: [TransactionModel], format: TransactionsViewModel.ExportFormat) async throws -> URL { fatalError("Not implemented") }
}

private final class FeeServiceMock: FeeServiceProtocol {
    func estimateFee(amount: Double, feeRate: Int) async throws -> Double {
        0.0001
    }

    func getFeeRates() async throws -> FeeRates { fatalError("Not implemented") }
    func getRecommendedFeeRate() async throws -> Int { fatalError("Not implemented") }
}
