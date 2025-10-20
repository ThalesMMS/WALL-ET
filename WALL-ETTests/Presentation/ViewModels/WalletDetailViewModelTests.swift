import XCTest
@testable import WALL_ET

@MainActor
final class WalletDetailViewModelTests: XCTestCase {
    func testExportWalletPostsShareNotificationWithFileURL() async throws {
        let walletId = UUID()
        let expectedContent = "{\"test\":true}"
        let walletService = WalletServiceStub(result: expectedContent, walletId: walletId)
        let viewModel = WalletDetailViewModel(
            walletId: walletId.uuidString,
            walletService: walletService,
            transactionService: TransactionServiceStub()
        )

        let expectation = expectation(forNotification: .shareFile, object: nil) { notification in
            guard let url = notification.userInfo?["url"] as? URL else { return false }
            guard let data = try? Data(contentsOf: url),
                  let fileContents = String(data: data, encoding: .utf8) else { return false }
            return fileContents == expectedContent
        }

        viewModel.exportWallet()
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(walletService.lastExportedId, walletId)
    }

    func testExportWalletSetsErrorMessageOnFailure() async {
        let walletService = WalletServiceStub(error: WalletExportError.walletNotFound)
        let viewModel = WalletDetailViewModel(
            walletId: UUID().uuidString,
            walletService: walletService,
            transactionService: TransactionServiceStub()
        )

        viewModel.exportWallet()
        await Task.yield()
        XCTAssertEqual(viewModel.errorMessage, WalletExportError.walletNotFound.localizedDescription)
    }
}

private final class WalletServiceStub: WalletServiceProtocol {
    var result: String?
    var error: Error?
    var lastExportedId: UUID?

    init(result: String? = nil, walletId: UUID? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
        self.targetWalletId = walletId
    }

    private let targetWalletId: UUID?

    func fetchWallets() async throws -> [WalletModel] { [] }
    func createWallet(name: String, type: WalletType) async throws -> WalletModel { fatalError("Not implemented") }
    func importWallet(seedPhrase: String, name: String, type: WalletType) async throws -> WalletModel { fatalError("Not implemented") }
    func deleteWallet(_ walletId: UUID) async throws {}
    func getAvailableBalance() async throws -> Double { 0 }
    func getWalletDetails(_ walletId: UUID) async throws -> WalletModel {
        WalletModel(
            id: walletId,
            name: "Test",
            address: "",
            confirmedBalance: 0,
            unconfirmedBalance: 0,
            isTestnet: true,
            derivationPath: "m/84'/1'/0'",
            createdAt: Date()
        )
    }
    func updateWallet(_ wallet: WalletModel) async throws {}
    func refreshWalletBalances() async throws -> [WalletModel] { [] }

    func exportWallet(_ walletId: UUID) async throws -> String {
        lastExportedId = walletId
        if let error = error {
            throw error
        }
        guard targetWalletId == nil || targetWalletId == walletId else {
            throw WalletExportError.walletNotFound
        }
        guard let result = result else {
            throw WalletExportError.serializationFailed
        }
        return result
    }
}

private final class TransactionServiceStub: TransactionServiceProtocol {
    func fetchTransactions(page: Int, pageSize: Int) async throws -> [TransactionModel] { [] }
    func fetchRecentTransactions(limit: Int) async throws -> [TransactionModel] { [] }
    func fetchTransaction(by id: String) async throws -> TransactionModel { fatalError("Not implemented") }
    func sendBitcoin(to address: String, amount: Double, fee: Double, note: String?) async throws -> TransactionModel { fatalError("Not implemented") }
    func speedUpTransaction(_ transactionId: String) async throws {}
    func cancelTransaction(_ transactionId: String) async throws {}
    func exportTransactions(_ transactions: [TransactionModel], format: TransactionsViewModel.ExportFormat) async throws -> URL { fatalError("Not implemented") }
}
