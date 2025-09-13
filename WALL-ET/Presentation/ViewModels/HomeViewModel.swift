import Foundation
import Combine
import SwiftUI

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var wallets: [WalletModel] = []
    @Published var totalBalanceBTC: Double = 0
    @Published var totalBalanceUSD: Double = 0
    @Published var recentTransactions: [TransactionModel] = []
    @Published var isLoading = false
    @Published var showBalance = true
    @Published var currentBTCPrice: Double = 62000
    @Published var priceChange24h: Double = 5.67
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var chartData: [PricePoint] = []
    
    // MARK: - Services
    private let walletService: WalletServiceProtocol
    private let priceService: PriceServiceProtocol
    private let transactionService: TransactionServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(walletService: WalletServiceProtocol? = nil,
         priceService: PriceServiceProtocol? = nil,
         transactionService: TransactionServiceProtocol? = nil) {
        self.walletService = walletService ?? WalletService()
        self.priceService = priceService ?? PriceService()
        self.transactionService = transactionService ?? TransactionService()
        
        setupBindings()
        loadData()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Auto-refresh every 30 seconds
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.refreshData()
                }
            }
            .store(in: &cancellables)
        
        // Listen for wallet updates
        NotificationCenter.default.publisher(for: .walletUpdated)
            .sink { [weak self] _ in
                Task {
                    await self?.loadWallets()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    func loadData() {
        Task {
            isLoading = true
            await loadWallets()
            await loadPrice()
            await loadRecentTransactions()
            calculateTotalBalance()
            isLoading = false
        }
    }
    
    func refreshData() async {
        await loadWallets()
        await loadPrice()
        await loadRecentTransactions()
        calculateTotalBalance()
    }
    
    private func loadWallets() async {
        do {
            wallets = try await walletService.fetchWallets()
        } catch {
            handleError(error)
        }
    }
    
    private func loadPrice() async {
        do {
            let priceData = try await priceService.fetchBTCPrice()
            currentBTCPrice = priceData.price
            priceChange24h = priceData.change24h
            // Placeholder sparkline points (optional)
            if chartData.isEmpty {
                let now = Date()
                chartData = (0..<24).map { i in
                    let d = Calendar.current.date(byAdding: .hour, value: -i, to: now) ?? now
                    let jitter = Double(Int.random(in: -150...150)) / 100.0
                    return PricePoint(date: d, price: max(0, priceData.price + jitter))
                }.sorted { $0.date < $1.date }
            }
        } catch {
            // Use cached price if fetch fails
            print("Failed to fetch price: \(error)")
        }
    }
    
    private func loadRecentTransactions() async {
        do {
            recentTransactions = try await transactionService.fetchRecentTransactions(limit: 5)
        } catch {
            handleError(error)
        }
    }
    
    // MARK: - Business Logic
    private func calculateTotalBalance() {
        totalBalanceBTC = wallets.reduce(0) { $0 + $1.balance }
        totalBalanceUSD = totalBalanceBTC * currentBTCPrice
    }
    
    func toggleBalanceVisibility() {
        showBalance.toggle()
        UserDefaults.standard.set(showBalance, forKey: "showBalance")
    }
    
    func formatBTCAmount(_ amount: Double) -> String {
        if showBalance {
            return String(format: "%.8f", amount)
        } else {
            return "••••••••"
        }
    }
    
    func formatUSDAmount(_ amount: Double) -> String {
        if showBalance {
            return String(format: "$%.2f", amount)
        } else {
            return "$••••••"
        }
    }
    
    // MARK: - Navigation
    func navigateToWallet(_ wallet: WalletModel) {
        NotificationCenter.default.post(
            name: .navigateToWallet,
            object: nil,
            userInfo: ["wallet": wallet]
        )
    }
    
    func navigateToSend() {
        NotificationCenter.default.post(name: .navigateToSend, object: nil)
    }
    
    func navigateToReceive() {
        NotificationCenter.default.post(name: .navigateToReceive, object: nil)
    }
    
    // MARK: - Error Handling
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Models
struct WalletModel: Identifiable, Codable {
    let id: UUID
    let name: String
    let address: String
    let balance: Double
    let isTestnet: Bool
    let derivationPath: String
    let createdAt: Date
    
    var displayAddress: String {
        String(address.prefix(10)) + "..." + String(address.suffix(6))
    }
}

struct TransactionModel: Identifiable, Codable {
    let id: String
    let type: TransactionType
    let amount: Double
    let fee: Double
    let address: String
    let date: Date
    let status: TransactionStatus
    let confirmations: Int
    
    enum TransactionType: String, Codable {
        case sent, received
    }
}


// MARK: - Notification Names
extension Notification.Name {
    static let walletUpdated = Notification.Name("walletUpdated")
    static let navigateToWallet = Notification.Name("navigateToWallet")
    static let navigateToSend = Notification.Name("navigateToSend")
    static let navigateToReceive = Notification.Name("navigateToReceive")
}
