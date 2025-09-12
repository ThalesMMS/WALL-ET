import Foundation

// MARK: - Mock Wallet Service
class WalletService: WalletServiceProtocol {
    private var wallets: [WalletModel] = [
        WalletModel(
            id: UUID(),
            name: "Main Wallet",
            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
            balance: 0.75432100,
            isTestnet: false,
            derivationPath: "m/84'/0'/0'",
            createdAt: Date()
        ),
        WalletModel(
            id: UUID(),
            name: "Savings",
            address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
            balance: 0.48024689,
            isTestnet: false,
            derivationPath: "m/84'/0'/1'",
            createdAt: Date()
        )
    ]
    
    func fetchWallets() async throws -> [WalletModel] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        return wallets
    }
    
    func createWallet(name: String, type: WalletType) async throws -> WalletModel {
        let wallet = WalletModel(
            id: UUID(),
            name: name,
            address: generateMockAddress(),
            balance: 0,
            isTestnet: type == .testnet,
            derivationPath: "m/84'/0'/\(wallets.count)'",
            createdAt: Date()
        )
        wallets.append(wallet)
        return wallet
    }
    
    func importWallet(seedPhrase: String, name: String) async throws -> WalletModel {
        return try await createWallet(name: name, type: .bitcoin)
    }
    
    func deleteWallet(_ walletId: UUID) async throws {
        wallets.removeAll { $0.id == walletId }
    }
    
    func getAvailableBalance() async throws -> Double {
        return wallets.reduce(0) { $0 + $1.balance }
    }
    
    func getWalletDetails(_ walletId: UUID) async throws -> WalletModel {
        guard let wallet = wallets.first(where: { $0.id == walletId }) else {
            throw WalletError.notFound
        }
        return wallet
    }
    
    func updateWallet(_ wallet: WalletModel) async throws {
        if let index = wallets.firstIndex(where: { $0.id == wallet.id }) {
            wallets[index] = wallet
        }
    }
    
    func exportWallet(_ walletId: UUID) async throws -> String {
        return "abandon ability able about above absent absorb abstract absurd abuse access accident"
    }
    
    private func generateMockAddress() -> String {
        let chars = "0123456789abcdef"
        let suffix = String((0..<39).map { _ in chars.randomElement()! })
        return "bc1q" + suffix
    }
}

// MARK: - Mock Transaction Service
class TransactionService: TransactionServiceProtocol {
    private var transactions: [TransactionModel] = []
    
    init() {
        // Generate mock transactions
        for i in 0..<50 {
            let daysAgo = Double(i * 2)
            transactions.append(
                TransactionModel(
                    id: UUID().uuidString,
                    type: i % 2 == 0 ? .received : .sent,
                    amount: Double.random(in: 0.001...0.1),
                    fee: 0.00001,
                    address: "bc1q\(String((0..<39).map { _ in "0123456789abcdef".randomElement()! }))",
                    date: Date().addingTimeInterval(-86400 * daysAgo),
                    status: i < 3 ? .pending : .confirmed,
                    confirmations: i < 3 ? i : 100 + i
                )
            )
        }
    }
    
    func fetchTransactions(page: Int, pageSize: Int) async throws -> [TransactionModel] {
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, transactions.count)
        
        guard startIndex < transactions.count else { return [] }
        
        return Array(transactions[startIndex..<endIndex])
    }
    
    func fetchRecentTransactions(limit: Int) async throws -> [TransactionModel] {
        return Array(transactions.prefix(limit))
    }
    
    func fetchTransaction(by id: String) async throws -> TransactionModel {
        guard let transaction = transactions.first(where: { $0.id == id }) else {
            throw TransactionError.notFound
        }
        return transaction
    }
    
    func sendBitcoin(to address: String, amount: Double, fee: Double, note: String?) async throws -> TransactionModel {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        let transaction = TransactionModel(
            id: UUID().uuidString,
            type: .sent,
            amount: amount,
            fee: fee,
            address: address,
            date: Date(),
            status: .pending,
            confirmations: 0
        )
        
        transactions.insert(transaction, at: 0)
        return transaction
    }
    
    func speedUpTransaction(_ transactionId: String) async throws {
        if let index = transactions.firstIndex(where: { $0.id == transactionId }) {
            // Simulate fee replacement
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    func cancelTransaction(_ transactionId: String) async throws {
        transactions.removeAll { $0.id == transactionId }
    }
    
    func exportTransactions(_ transactions: [TransactionModel], format: TransactionsViewModel.ExportFormat) async throws -> URL {
        let fileName = "transactions.\(format.rawValue.lowercased())"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        // Create mock export file
        let data = "Mock export data".data(using: .utf8)!
        try data.write(to: url)
        
        return url
    }
}

// MARK: - Mock Price Service
class PriceService: PriceServiceProtocol {
    func fetchBTCPrice() async throws -> PriceData {
        try await Task.sleep(nanoseconds: 300_000_000)
        
        return PriceData(
            price: 62000 + Double.random(in: -1000...1000),
            change24h: Double.random(in: -10...10),
            volume24h: 28_000_000_000,
            marketCap: 1_200_000_000_000
        )
    }
    
    func fetchPriceHistory(days: Int) async throws -> [PricePoint] {
        var history: [PricePoint] = []
        let basePrice = 62000.0
        
        for i in 0..<days {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let price = basePrice + Double.random(in: -5000...5000)
            history.append(PricePoint(date: date, price: price))
        }
        
        return history.reversed()
    }
    
    func subscribeToPriceUpdates(completion: @escaping (PriceData) -> Void) {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task {
                if let price = try? await self.fetchBTCPrice() {
                    completion(price)
                }
            }
        }
    }
}

// MARK: - Mock Fee Service
class FeeService: FeeServiceProtocol {
    func estimateFee(amount: Double, feeRate: Int) async throws -> Double {
        // Mock fee calculation (satoshis per byte * estimated transaction size)
        let txSize = 250 // bytes (typical transaction size)
        let feeInSatoshis = Double(feeRate * txSize)
        return feeInSatoshis / 100_000_000 // Convert to BTC
    }
    
    func getFeeRates() async throws -> FeeRates {
        try await Task.sleep(nanoseconds: 200_000_000)
        
        return FeeRates(
            slow: 5,
            normal: 20,
            fast: 50,
            fastest: 100
        )
    }
    
    func getRecommendedFeeRate() async throws -> Int {
        return 20 // sat/byte
    }
}

// MARK: - Error Types
enum WalletError: LocalizedError {
    case notFound
    case invalidSeed
    case insufficientBalance
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Wallet not found"
        case .invalidSeed:
            return "Invalid seed phrase"
        case .insufficientBalance:
            return "Insufficient balance"
        }
    }
}

enum TransactionError: LocalizedError {
    case notFound
    case invalidAddress
    case failed
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Transaction not found"
        case .invalidAddress:
            return "Invalid Bitcoin address"
        case .failed:
            return "Transaction failed"
        }
    }
}