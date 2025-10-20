import Foundation

struct SendTransactionRequest {
    let fromWallet: Wallet
    let toAddress: String
    let amount: Int64 // in satoshis
    let feeRate: Int // sat/vByte
    let memo: String?
}

protocol SendBitcoinUseCaseProtocol {
    func execute(request: SendTransactionRequest) async throws -> Transaction
}

final class SendBitcoinUseCase: SendBitcoinUseCaseProtocol {
    private let walletRepository: WalletRepositoryProtocol
    private let transactionService: TransactionServiceProtocol
    private let feeService: FeeServiceProtocol

    init(
        walletRepository: WalletRepositoryProtocol,
        transactionService: TransactionServiceProtocol,
        feeService: FeeServiceProtocol
    ) {
        self.walletRepository = walletRepository
        self.transactionService = transactionService
        self.feeService = feeService
    }

    func execute(request: SendTransactionRequest) async throws -> Transaction {
        // Validate address
        guard request.toAddress.isValidBitcoinAddress else {
            throw WalletError.invalidAddress
        }

        // Validate amount
        guard request.amount > Constants.Bitcoin.minimumDustAmount else {
            throw WalletError.amountTooSmall
        }

        // Check balance
        let accountAddresses = request.fromWallet.accounts.map { $0.address }
        let repositoryAddresses = walletRepository.listAddresses(for: request.fromWallet.id)
        let uniqueAddresses = Array(Set(accountAddresses + repositoryAddresses).filter { !$0.isEmpty })
        let balances = try await walletRepository.getBalances(for: uniqueAddresses)
        let confirmedTotal = uniqueAddresses.reduce(into: Int64(0)) { total, address in
            total += balances[address]?.confirmed ?? 0
        }

        guard confirmedTotal >= request.amount else {
            throw WalletError.insufficientBalance
        }

        let amountInBTC = Double(request.amount) / Double(Constants.Bitcoin.satoshisPerBitcoin)
        let feeInBTC = try await feeService.estimateFee(amount: amountInBTC, feeRate: request.feeRate)

        let transactionModel = try await transactionService.sendBitcoin(
            to: request.toAddress,
            amount: amountInBTC,
            fee: feeInBTC,
            note: request.memo
        )

        logInfo("Transaction broadcasted: \(transactionModel.id)")

        return Transaction(
            id: transactionModel.id,
            hash: transactionModel.id,
            type: mapTransactionType(transactionModel.type),
            amount: transactionModel.amount.bitcoinToSatoshis(),
            fee: transactionModel.fee.bitcoinToSatoshis(),
            timestamp: transactionModel.date,
            confirmations: transactionModel.confirmations,
            status: transactionModel.status,
            fromAddress: request.fromWallet.accounts.first?.address,
            toAddress: transactionModel.address,
            memo: request.memo
        )
    }

    private func mapTransactionType(_ type: TransactionModel.TransactionType) -> TransactionType {
        switch type {
        case .sent:
            return .send
        case .received:
            return .receive
        }
    }
}

enum WalletError: LocalizedError {
    case invalidAddress
    case amountTooSmall
    case insufficientBalance
    case transactionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "Invalid Bitcoin address"
        case .amountTooSmall:
            return "Amount is below minimum dust threshold"
        case .insufficientBalance:
            return "Insufficient balance"
        case .transactionFailed:
            return "Transaction failed"
        }
    }
}