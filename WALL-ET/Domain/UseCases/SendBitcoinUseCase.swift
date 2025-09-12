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
    
    init(walletRepository: WalletRepositoryProtocol) {
        self.walletRepository = walletRepository
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
        let balance = try await walletRepository.getBalance(for: request.fromWallet.accounts.first?.address ?? "")
        guard balance.confirmed >= request.amount else {
            throw WalletError.insufficientBalance
        }
        
        // Create and broadcast transaction
        // In a real implementation, this would create a proper Bitcoin transaction
        let transaction = Transaction(
            id: UUID().uuidString,
            hash: UUID().uuidString,
            type: .send,
            amount: request.amount,
            fee: Int64(request.feeRate * 250), // Estimated fee
            toAddress: request.toAddress,
            memo: request.memo
        )
        
        logInfo("Transaction created: \(transaction.hash)")
        
        return transaction
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