import Foundation

struct Transaction: Identifiable, Codable, Equatable {
    let id: String
    let hash: String
    let type: TransactionType
    let amount: Int64
    let fee: Int64
    let timestamp: Date
    let confirmations: Int
    let status: TransactionStatus
    let fromAddress: String?
    let toAddress: String
    let memo: String?
    
    init(
        id: String,
        hash: String,
        type: TransactionType,
        amount: Int64,
        fee: Int64,
        timestamp: Date = Date(),
        confirmations: Int = 0,
        status: TransactionStatus = .pending,
        fromAddress: String? = nil,
        toAddress: String,
        memo: String? = nil
    ) {
        self.id = id
        self.hash = hash
        self.type = type
        self.amount = amount
        self.fee = fee
        self.timestamp = timestamp
        self.confirmations = confirmations
        self.status = status
        self.fromAddress = fromAddress
        self.toAddress = toAddress
        self.memo = memo
    }
}

enum TransactionType: String, Codable {
    case send
    case receive
    case swap
}

enum TransactionStatus: String, Codable {
    case pending
    case confirmed
    case failed
    
    var displayText: String {
        switch self {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        }
    }
    
    var iconName: String {
        switch self {
        case .pending: return "clock.arrow.circlepath"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}