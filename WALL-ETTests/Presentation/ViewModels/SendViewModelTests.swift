import XCTest
@testable import WALL_ET

@MainActor
final class SendViewModelTests: XCTestCase {

    func testHandleScannedCodeAcceptsBitcoinURI() {
        let viewModel = SendViewModel(initialBalance: 1.0, initialPrice: 20000, skipInitialLoad: true)
        viewModel.showScanner = true

        viewModel.handleScannedCode("bitcoin:tb1qexampleaddress123?amount=0.5")

        XCTAssertEqual(viewModel.recipientAddress, "tb1qexampleaddress123")
        XCTAssertEqual(viewModel.btcAmount, "0.50000000")
        XCTAssertEqual(viewModel.fiatAmount, "10000.00")
        XCTAssertFalse(viewModel.showScanner)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testHandleScannedCodeAcceptsPlainAddress() {
        let viewModel = SendViewModel(initialPrice: 20000, skipInitialLoad: true)
        viewModel.showScanner = true

        viewModel.handleScannedCode("tb1qplainaddress456")

        XCTAssertEqual(viewModel.recipientAddress, "tb1qplainaddress456")
        XCTAssertTrue(viewModel.btcAmount.isEmpty)
        XCTAssertTrue(viewModel.fiatAmount.isEmpty)
        XCTAssertFalse(viewModel.showScanner)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testHandleScannedCodeRejectsInvalidFormat() {
        let viewModel = SendViewModel(initialPrice: 20000, skipInitialLoad: true)
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
}
