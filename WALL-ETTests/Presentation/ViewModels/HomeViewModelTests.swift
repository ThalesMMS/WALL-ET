import XCTest
@testable import WALL_ET

@MainActor
final class HomeViewModelTests: XCTestCase {

    func testLoadPriceHistoryRequestsCorrectDays() async {
        let priceService = MockPriceService()
        priceService.historyToReturn = [
            PricePoint(date: Date(), price: 100)
        ]

        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let viewModel = HomeViewModel(
            walletService: MockWalletService(),
            priceService: priceService,
            transactionService: MockTransactionService(),
            userDefaults: userDefaults,
            shouldLoadOnInit: false
        )

        await viewModel.loadPriceHistory(for: .month)

        XCTAssertEqual(priceService.requestedDays, [HomeViewModel.PriceHistoryRange.month.days])
        XCTAssertEqual(viewModel.chartData, priceService.historyToReturn)
    }

    func testLoadPriceHistoryUsesCachedDataOnFailure() async {
        let priceService = MockPriceService()

        let suiteName = UUID().uuidString
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let viewModel = HomeViewModel(
            walletService: MockWalletService(),
            priceService: priceService,
            transactionService: MockTransactionService(),
            userDefaults: userDefaults,
            shouldLoadOnInit: false
        )

        let history = (0..<5).map { index in
            PricePoint(
                date: Date().addingTimeInterval(Double(index) * -3600),
                price: Double(index) * 10
            )
        }

        let sortedHistory = history.sorted { $0.date < $1.date }

        priceService.historyToReturn = history
        await viewModel.loadPriceHistory(for: .week)

        XCTAssertEqual(viewModel.chartData, sortedHistory)

        priceService.shouldThrow = true
        viewModel.chartData = []

        await viewModel.loadPriceHistory(for: .week)

        XCTAssertEqual(viewModel.chartData, sortedHistory)
        XCTAssertEqual(
            priceService.requestedDays,
            [HomeViewModel.PriceHistoryRange.week.days, HomeViewModel.PriceHistoryRange.week.days]
        )
    }
}

// MARK: - Mocks

private final class MockPriceService: PriceServiceProtocol {
    var historyToReturn: [PricePoint] = []
    var shouldThrow = false
    var requestedDays: [Int] = []

    func fetchBTCPrice() async throws -> PriceData {
        PriceData(
            price: 0,
            change24h: 0,
            changePercentage24h: 0,
            volume24h: 0,
            marketCap: 0,
            currency: "USD",
            timestamp: Date()
        )
    }

    func fetchPriceHistory(days: Int) async throws -> [PricePoint] {
        requestedDays.append(days)
        if shouldThrow {
            throw NSError(domain: "MockPriceService", code: -1)
        }
        return historyToReturn
    }

    func subscribeToPriceUpdates(completion: @escaping (PriceData) -> Void) {}
}

private final class MockWalletService: WalletServiceProtocol {
    var storedWallets: [WalletModel] = []

    func fetchWallets() async throws -> [WalletModel] { storedWallets }
    func createWallet(name: String, type: WalletType) async throws -> WalletModel {
        throw NSError(domain: "MockWalletService", code: -1)
    }
    func importWallet(seedPhrase: String, name: String, type: WalletType) async throws -> WalletModel {
        throw NSError(domain: "MockWalletService", code: -1)
    }
    func deleteWallet(_ walletId: UUID) async throws {}
    func getAvailableBalance() async throws -> Double { 0 }
    func getWalletDetails(_ walletId: UUID) async throws -> WalletModel {
        throw NSError(domain: "MockWalletService", code: -1)
    }
    func updateWallet(_ wallet: WalletModel) async throws {}
    func exportWallet(_ walletId: UUID) async throws -> String {
        throw NSError(domain: "MockWalletService", code: -1)
    }
}

private final class MockTransactionService: TransactionServiceProtocol {
    func fetchTransactions(page: Int, pageSize: Int) async throws -> [TransactionModel] { [] }
    func fetchRecentTransactions(limit: Int) async throws -> [TransactionModel] { [] }
    func fetchTransaction(by id: String) async throws -> TransactionModel {
        throw NSError(domain: "MockTransactionService", code: -1)
    }
    func sendBitcoin(to address: String, amount: Double, fee: Double, note: String?) async throws -> TransactionModel {
        throw NSError(domain: "MockTransactionService", code: -1)
    }
    func speedUpTransaction(_ transactionId: String) async throws {}
    func cancelTransaction(_ transactionId: String) async throws {}
    func exportTransactions(_ transactions: [TransactionModel], format: TransactionsViewModel.ExportFormat) async throws -> URL {
        throw NSError(domain: "MockTransactionService", code: -1)
    }
}
