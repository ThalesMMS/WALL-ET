import XCTest
@testable import WALL_ET

@MainActor
final class SendViewModelTests: XCTestCase {

    func testHandleScannedCodeAcceptsBitcoinURI() {
        let walletRepository = MockWalletRepository()
        let useCase = MockSendBitcoinUseCase()
        let viewModel = SendViewModel(
            walletRepository: walletRepository,
            sendBitcoinUseCase: useCase,
            initialBalance: 1.0,
            initialPrice: 20000,
            skipInitialLoad: true
        )
        viewModel.showScanner = true

        viewModel.handleScannedCode("bitcoin:tb1qexampleaddress123?amount=0.5")

        XCTAssertEqual(viewModel.recipientAddress, "tb1qexampleaddress123")
        XCTAssertEqual(viewModel.btcAmount, "0.50000000")
        XCTAssertEqual(viewModel.fiatAmount, "10000.00")
        XCTAssertFalse(viewModel.showScanner)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testHandleScannedCodeAcceptsPlainAddress() {
        let walletRepository = MockWalletRepository()
        let useCase = MockSendBitcoinUseCase()
        let viewModel = SendViewModel(
            walletRepository: walletRepository,
            sendBitcoinUseCase: useCase,
            initialPrice: 20000,
            skipInitialLoad: true
        )
        viewModel.showScanner = true

        viewModel.handleScannedCode("tb1qplainaddress456")

        XCTAssertEqual(viewModel.recipientAddress, "tb1qplainaddress456")
        XCTAssertTrue(viewModel.btcAmount.isEmpty)
        XCTAssertTrue(viewModel.fiatAmount.isEmpty)
        XCTAssertFalse(viewModel.showScanner)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testHandleScannedCodeRejectsInvalidFormat() {
        let walletRepository = MockWalletRepository()
        let useCase = MockSendBitcoinUseCase()
        let viewModel = SendViewModel(
            walletRepository: walletRepository,
            sendBitcoinUseCase: useCase,
            initialPrice: 20000,
            skipInitialLoad: true
        )
        viewModel.showScanner = true
        viewModel.handleScannedCode("bitcoin:tb1qoriginal?amount=0.25")
        viewModel.showScanner = true
        viewModel.errorMessage = nil

        viewModel.handleScannedCode("invalid:code")

        XCTAssertEqual(viewModel.recipientAddress, "tb1qoriginal")
        XCTAssertEqual(viewModel.btcAmount, "0.25000000")
        XCTAssertEqual(viewModel.fiatAmount, "5000.00")
        XCTAssertFalse(viewModel.showScanner)
        XCTAssertEqual(viewModel.errorMessage, "Unsupported QR code content.")
    }

    func testConfirmTransactionSuccess() async throws {
        let wallet = Wallet(
            name: "Test Wallet",
            type: .testnet,
            accounts: [
                Account(index: 0, address: "tb1qrecipient0000000000000000000000000000000", publicKey: "pubkey")
            ]
        )

        let walletRepository = MockWalletRepository()
        walletRepository.wallets = [wallet]
        walletRepository.balance = Balance(confirmed: 5_000_000_000)

        let useCase = MockSendBitcoinUseCase()
        let expectedTransaction = Transaction(
            id: "txid",
            hash: "hash",
            type: .send,
            amount: 10_000_000,
            fee: 1_000,
            toAddress: "tb1qrecipient0000000000000000000000000000000",
            memo: "Test memo"
        )
        useCase.result = .success(expectedTransaction)

        let viewModel = SendViewModel(
            walletRepository: walletRepository,
            sendBitcoinUseCase: useCase,
            initialBalance: 5.0,
            initialPrice: 20000,
            skipInitialLoad: true
        )

        viewModel.recipientAddress = "tb1qrecipient0000000000000000000000000000000"
        viewModel.btcAmount = "0.10000000"
        viewModel.memo = "Test memo"
        viewModel.showConfirmation = true

        let expectation = expectation(forNotification: .transactionSent, object: nil)

        await viewModel.confirmTransaction()

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(useCase.executeCalled)
        XCTAssertEqual(useCase.capturedRequest?.amount, 10_000_000)
        XCTAssertEqual(useCase.capturedRequest?.memo, "Test memo")
        XCTAssertFalse(viewModel.showConfirmation)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSending)
    }

    func testConfirmTransactionFailureSetsError() async {
        enum TestError: LocalizedError {
            case sendFailed

            var errorDescription: String? { "Unable to send" }
        }

        let wallet = Wallet(
            name: "Test Wallet",
            type: .testnet,
            accounts: [
                Account(index: 0, address: "tb1qrecipient0000000000000000000000000000000", publicKey: "pubkey")
            ]
        )

        let walletRepository = MockWalletRepository()
        walletRepository.wallets = [wallet]
        walletRepository.balance = Balance(confirmed: 5_000_000_000)

        let useCase = MockSendBitcoinUseCase()
        useCase.result = .failure(TestError.sendFailed)

        let viewModel = SendViewModel(
            walletRepository: walletRepository,
            sendBitcoinUseCase: useCase,
            initialBalance: 5.0,
            initialPrice: 20000,
            skipInitialLoad: true
        )

        viewModel.recipientAddress = "tb1qrecipient0000000000000000000000000000000"
        viewModel.btcAmount = "0.10000000"
        viewModel.showConfirmation = true

        await viewModel.confirmTransaction()

        XCTAssertTrue(useCase.executeCalled)
        XCTAssertEqual(viewModel.errorMessage, "Unable to send")
        XCTAssertTrue(viewModel.showConfirmation)
        XCTAssertFalse(viewModel.isSending)
    }
}

// MARK: - Test Doubles

private final class MockSendBitcoinUseCase: SendBitcoinUseCaseProtocol {
    var executeCalled = false
    var capturedRequest: SendTransactionRequest?
    var result: Result<Transaction, Error> = .success(
        Transaction(
            id: "placeholder",
            hash: "placeholder",
            type: .send,
            amount: 0,
            fee: 0,
            toAddress: "",
            memo: nil
        )
    )

    func execute(request: SendTransactionRequest) async throws -> Transaction {
        executeCalled = true
        capturedRequest = request

        switch result {
        case .success(let transaction):
            return transaction
        case .failure(let error):
            throw error
        }
    }
}

private final class MockWalletRepository: WalletRepositoryProtocol {
    var wallets: [Wallet] = []
    var balance: Balance = Balance()

    func createWallet(name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func getAllWallets() async throws -> [Wallet] { wallets }
    func getWallet(by id: UUID) async throws -> Wallet? { fatalError("Not implemented") }
    func updateWallet(_ wallet: Wallet) async throws { fatalError("Not implemented") }
    func deleteWallet(by id: UUID) async throws { fatalError("Not implemented") }
    func getBalance(for address: String) async throws -> Balance { balance }
    func getTransactions(for address: String) async throws -> [Transaction] { fatalError("Not implemented") }
}
