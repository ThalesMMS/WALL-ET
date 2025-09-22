import Foundation

struct Wallet: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: WalletType
    let createdAt: Date
    var accounts: [Account]
    var isWatchOnly: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        type: WalletType,
        createdAt: Date = Date(),
        accounts: [Account] = [],
        isWatchOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.createdAt = createdAt
        self.accounts = accounts
        self.isWatchOnly = isWatchOnly
    }
}

enum WalletType: String, Codable, CaseIterable {
    case bitcoin = "Bitcoin"
    case testnet = "Testnet"
    
    var symbol: String {
        switch self {
        case .bitcoin: return "BTC"
        case .testnet: return "tBTC"
        }
    }
}

struct Account: Identifiable, Codable, Equatable {
    let id: UUID
    let index: Int
    let address: String
    let publicKey: String
    var balance: Balance
    var transactions: [Transaction]
    
    init(id: UUID = UUID(), index: Int, address: String, publicKey: String, balance: Balance = Balance()) {
        self.id = id
        self.index = index
        self.address = address
        self.publicKey = publicKey
        self.balance = balance
        self.transactions = []
    }
}

struct Balance: Codable, Equatable {
    var confirmed: Int64
    var unconfirmed: Int64
    var total: Int64 {
        confirmed + unconfirmed
    }
    
    init(confirmed: Int64 = 0, unconfirmed: Int64 = 0) {
        self.confirmed = confirmed
        self.unconfirmed = unconfirmed
    }
    
    var btcValue: Double {
        Double(total).satoshisToBitcoin()
    }
}