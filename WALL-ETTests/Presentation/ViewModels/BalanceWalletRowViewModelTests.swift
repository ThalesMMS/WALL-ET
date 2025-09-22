import Combine
import XCTest

@testable import WALL_ET

@MainActor
final class BalanceWalletRowViewModelTests: XCTestCase {
    func testLoadCurrentPriceUpdatesFiatBalance() async {
        let wallet = makeWallet(totalBTC: 0.0025)
        let mockService = MockPriceDataService()
        mockService.fetchCurrentPriceResult = PriceData(
            price: 30_000,
            change24h: 0,
            changePercentage24h: 0,
            volume24h: 0,
            marketCap: 0,
            currency: "USD",
            timestamp: Date()
        )

        let expectedBTC = wallet.accounts.reduce(0) { $0 + $1.balance.btcValue }
        let expectedFiat = expectedBTC * 30_000

        let viewModel = BalanceWalletRowViewModel(
            wallet: wallet,
            currencyCode: "USD",
            priceService: mockService
        )

        let expectation = expectation(description: "Fiat balance updated")
        let cancellable = viewModel.$fiatBalance
            .dropFirst()
            .sink { value in
                if value != nil {
                    expectation.fulfill()
                }
            }

        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(viewModel.fiatBalance, expectedFiat, accuracy: 0.0001)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadCurrentPriceFailureSetsError() async {
        let wallet = makeWallet(totalBTC: 0.001)
        let mockService = MockPriceDataService()
        mockService.fetchCurrentPriceResult = nil

        let viewModel = BalanceWalletRowViewModel(
            wallet: wallet,
            currencyCode: "USD",
            priceService: mockService
        )

        let expectation = expectation(description: "Error message set")
        let cancellable = viewModel.$errorMessage
            .dropFirst()
            .sink { message in
                if message != nil {
                    expectation.fulfill()
                }
            }

        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertNil(viewModel.fiatBalance)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testPriceUpdatesAdjustFiatBalance() async {
        let wallet = makeWallet(totalBTC: 0.005)
        let mockService = MockPriceDataService()
        mockService.fetchCurrentPriceResult = PriceData(
            price: 35_000,
            change24h: 0,
            changePercentage24h: 0,
            volume24h: 0,
            marketCap: 0,
            currency: "USD",
            timestamp: Date()
        )

        let viewModel = BalanceWalletRowViewModel(
            wallet: wallet,
            currencyCode: "USD",
            priceService: mockService
        )

        let initialExpectation = expectation(description: "Initial fiat balance loaded")
        var cancellable = viewModel.$fiatBalance
            .dropFirst()
            .sink { value in
                if value != nil {
                    initialExpectation.fulfill()
                }
            }

        await fulfillment(of: [initialExpectation], timeout: 1.0)
        cancellable.cancel()

        let expectedBTC = wallet.accounts.reduce(0) { $0 + $1.balance.btcValue }
        let expectedUpdatedFiat = expectedBTC * 40_000.0

        let updateExpectation = expectation(description: "Fiat balance updated from publisher")
        cancellable = viewModel.$fiatBalance
            .dropFirst()
            .sink { value in
                guard let value else { return }
                if abs(value - expectedUpdatedFiat) < 0.0001 {
                    updateExpectation.fulfill()
                }
            }

        mockService.sendPriceUpdate(
            PriceData(
                price: 40_000,
                change24h: 0,
                changePercentage24h: 0,
                volume24h: 0,
                marketCap: 0,
                currency: "USD",
                timestamp: Date()
            )
        )

        await fulfillment(of: [updateExpectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertEqual(viewModel.fiatBalance, expectedUpdatedFiat, accuracy: 0.0001)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makeWallet(totalBTC: Double) -> Wallet {
        let satoshis = Int64(totalBTC * 100_000_000)
        let account = Account(
            index: 0,
            address: "tb1qtestaddress",
            publicKey: "pubkey",
            balance: Balance(confirmed: satoshis)
        )

        return Wallet(
            name: "Test Wallet",
            type: .testnet,
            accounts: [account]
        )
    }
}

private final class MockPriceDataService: PriceDataServiceType {
    var fetchCurrentPriceResult: PriceData?
    let priceUpdatePublisher = PassthroughSubject<PriceData, Never>()

    func fetchCurrentPrice(for currency: String) async -> PriceData? {
        fetchCurrentPriceResult
    }

    func sendPriceUpdate(_ data: PriceData) {
        priceUpdatePublisher.send(data)
    }
}
