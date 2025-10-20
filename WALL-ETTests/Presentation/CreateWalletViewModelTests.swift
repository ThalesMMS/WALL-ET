import XCTest
@testable import WALL_ET

@MainActor
final class CreateWalletViewModelTests: XCTestCase {

    func testCreateWalletPublishesMnemonicFromUseCaseResult() async throws {
        let expectedWallet = Wallet(name: "Sample", type: .bitcoin)
        let expectedMnemonic = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        let useCase = CreateWalletUseCaseStub(result: CreateWalletResult(wallet: expectedWallet, mnemonic: expectedMnemonic))
        let repository = WalletRepositoryDummy()
        let sut = CreateWalletViewModel(createWalletUseCase: useCase, walletRepository: repository)
        sut.walletName = expectedWallet.name
        sut.walletType = expectedWallet.type

        await sut.createWallet()

        XCTAssertEqual(useCase.received?.name, expectedWallet.name)
        XCTAssertEqual(useCase.received?.type, expectedWallet.type)
        XCTAssertEqual(sut.createdWallet, expectedWallet)
        XCTAssertEqual(sut.mnemonic, expectedMnemonic)
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.isCreating)
    }
}

private final class CreateWalletUseCaseStub: CreateWalletUseCaseProtocol {
    private let result: CreateWalletResult
    private(set) var received: (name: String, type: WalletType)?

    init(result: CreateWalletResult) {
        self.result = result
    }

    func execute(name: String, type: WalletType) async throws -> CreateWalletResult {
        received = (name, type)
        return result
    }
}

private final class WalletRepositoryDummy: WalletRepositoryProtocol {
    func createWallet(name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet { fatalError("Not implemented") }
    func getAllWallets() async throws -> [Wallet] { fatalError("Not implemented") }
    func getWallet(by id: UUID) async throws -> Wallet? { fatalError("Not implemented") }
    func updateWallet(_ wallet: Wallet) async throws { fatalError("Not implemented") }
    func deleteWallet(by id: UUID) async throws { fatalError("Not implemented") }
    func getActiveWallet() -> Wallet? { nil }
    func getBalance(for address: String) async throws -> Balance { fatalError("Not implemented") }
    func getTransactions(for address: String) async throws -> [Transaction] { fatalError("Not implemented") }
    func listAddresses(for walletId: UUID) -> [String] { [] }
}
