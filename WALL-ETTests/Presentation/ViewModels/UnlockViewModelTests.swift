import XCTest
@testable import WALL_ET

final class UnlockViewModelTests: XCTestCase {

    func testUnlockWithValidPINUnlocksAndClearsPassword() {
        let authenticator = MockUnlockAuthenticator(isPINConfigured: true, result: true)
        let viewModel = UnlockViewModel(authenticator: authenticator)
        viewModel.password = "1234"

        let expectation = expectation(description: "Unlock completion")

        viewModel.unlock { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertEqual(authenticator.lastPIN, "1234")
        XCTAssertEqual(viewModel.password, "")
        XCTAssertFalse(viewModel.showError)
    }

    func testUnlockWithInvalidPINShowsError() {
        let authenticator = MockUnlockAuthenticator(isPINConfigured: true, result: false)
        let viewModel = UnlockViewModel(authenticator: authenticator)
        viewModel.password = "0000"

        let expectation = expectation(description: "Unlock failure")

        viewModel.unlock { success in
            XCTAssertFalse(success)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertEqual(authenticator.lastPIN, "0000")
        XCTAssertTrue(viewModel.showError)
        XCTAssertEqual(viewModel.errorMessage, "Incorrect PIN. Please try again.")
        XCTAssertEqual(viewModel.password, "")
    }

    func testUnlockWithoutConfiguredPINNotifiesUser() {
        let authenticator = MockUnlockAuthenticator(isPINConfigured: false, result: false)
        let viewModel = UnlockViewModel(authenticator: authenticator)
        viewModel.password = "1111"

        var completionCalled = false

        viewModel.unlock { success in
            completionCalled = true
            XCTAssertFalse(success)
        }

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(authenticator.authenticateCallCount, 0)
        XCTAssertTrue(viewModel.showError)
        XCTAssertEqual(viewModel.errorMessage, "No PIN configured. Please set one up in Settings.")
        XCTAssertEqual(viewModel.password, "")
    }

    func testUnlockWithEmptyPINRequestsInput() {
        let authenticator = MockUnlockAuthenticator(isPINConfigured: true, result: true)
        let viewModel = UnlockViewModel(authenticator: authenticator)
        viewModel.password = "   "

        var completionCalled = false

        viewModel.unlock { success in
            completionCalled = true
            XCTAssertFalse(success)
        }

        XCTAssertTrue(completionCalled)
        XCTAssertEqual(authenticator.authenticateCallCount, 0)
        XCTAssertTrue(viewModel.showError)
        XCTAssertEqual(viewModel.errorMessage, "Please enter your PIN.")
        XCTAssertEqual(viewModel.password, "")
    }
}

private final class MockUnlockAuthenticator: UnlockAuthenticating {
    var isPINConfigured: Bool
    var result: Bool
    private(set) var lastPIN: String?
    private(set) var authenticateCallCount: Int = 0

    init(isPINConfigured: Bool, result: Bool) {
        self.isPINConfigured = isPINConfigured
        self.result = result
    }

    func authenticateWithPIN(pin: String?, completion: ((Bool) -> Void)?) {
        authenticateCallCount += 1
        lastPIN = pin
        completion?(result)
    }
}

