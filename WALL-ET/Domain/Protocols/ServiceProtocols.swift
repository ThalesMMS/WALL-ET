import Foundation

// MARK: - Wallet Service Protocol
protocol WalletServiceProtocol {
    func fetchWallets() async throws -> [WalletModel]
    func refreshWalletBalances() async throws -> [WalletModel]
    func createWallet(name: String, type: WalletType) async throws -> WalletModel
    func importWallet(seedPhrase: String, name: String, type: WalletType) async throws -> WalletModel
    func deleteWallet(_ walletId: UUID) async throws
    func getAvailableBalance() async throws -> Double
    func getWalletDetails(_ walletId: UUID) async throws -> WalletModel
    func updateWallet(_ wallet: WalletModel) async throws
    func exportWallet(_ walletId: UUID) async throws -> String
}

// MARK: - Transaction Service Protocol
protocol TransactionServiceProtocol {
    func fetchTransactions(page: Int, pageSize: Int) async throws -> [TransactionModel]
    func fetchRecentTransactions(limit: Int) async throws -> [TransactionModel]
    func fetchTransaction(by id: String) async throws -> TransactionModel
    func sendBitcoin(to address: String, amount: Double, fee: Double, note: String?) async throws -> TransactionModel
    func speedUpTransaction(_ transactionId: String) async throws
    func cancelTransaction(_ transactionId: String) async throws
    func exportTransactions(_ transactions: [TransactionModel], format: TransactionsViewModel.ExportFormat) async throws -> URL
}

// MARK: - Price Service Protocol
protocol PriceServiceProtocol {
    func fetchBTCPrice() async throws -> PriceData
    func fetchPriceHistory(days: Int) async throws -> [PricePoint]
    func subscribeToPriceUpdates(completion: @escaping (PriceData) -> Void)
}

// MARK: - Fee Service Protocol
protocol FeeServiceProtocol {
    func estimateFee(amount: Double, feeRate: Int) async throws -> Double
    func getFeeRates() async throws -> FeeRates
    func getRecommendedFeeRate() async throws -> Int
}

// MARK: - Address Service Protocol
protocol AddressServiceProtocol {
    func validateAddress(_ address: String) -> Bool
    func generateAddress(for wallet: WalletModel) async throws -> String
    func getAddressBalance(_ address: String) async throws -> Double
    func getAddressTransactions(_ address: String) async throws -> [TransactionModel]
}

// MARK: - Keychain Service Protocol is defined in KeychainServiceProtocol.swift

// MARK: - Network Service Protocol
protocol NetworkServiceProtocol {
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    func download(_ url: URL) async throws -> Data
    func upload(_ data: Data, to endpoint: Endpoint) async throws
}

// MARK: - Notification Service Protocol
protocol NotificationServiceProtocol {
    func requestPermission() async -> Bool
    func scheduleNotification(title: String, body: String, date: Date)
    func cancelNotification(identifier: String)
    func registerForPushNotifications()
}

// MARK: - Supporting Types
struct FeeRates {
    let slow: Int
    let normal: Int
    let fast: Int
    let fastest: Int
}

struct PricePoint: Codable, Equatable {
    let date: Date
    let price: Double
}

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let parameters: [String: Any]?
    let headers: [String: String]?
    
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }
}
