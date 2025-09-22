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
    @Published var selectedTimeRange: PriceHistoryRange = .day

    // MARK: - Services
    private let walletService: WalletServiceProtocol
    private let priceService: PriceServiceProtocol
    private let transactionService: TransactionServiceProtocol
    private let userDefaults: UserDefaults
    private var priceHistoryCache: [PriceHistoryRange: [PricePoint]] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Cache Keys
    private let historyCacheKeyPrefix = "HomeViewModel.PriceHistory."

    // MARK: - Initialization
    init(walletService: WalletServiceProtocol? = nil,
         priceService: PriceServiceProtocol? = nil,
         transactionService: TransactionServiceProtocol? = nil,
         userDefaults: UserDefaults = .standard,
         shouldLoadOnInit: Bool = true) {
        self.walletService = walletService ?? WalletService()
        self.priceService = priceService ?? PriceService()
        self.transactionService = transactionService ?? TransactionService()
        self.userDefaults = userDefaults

        restoreCachedHistory()
        setupBindings()
        if shouldLoadOnInit {
            loadData()
        }
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
            await loadPriceHistory(for: selectedTimeRange)
            await loadRecentTransactions()
            calculateTotalBalance()
            isLoading = false
        }
    }

    func refreshData() async {
        await loadWallets()
        await loadPrice()
        await loadPriceHistory(for: selectedTimeRange)
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
        } catch {
            // Use cached price if fetch fails
            print("Failed to fetch price: \(error)")
        }
    }

    func loadPriceHistory(for range: PriceHistoryRange) async {
        if let cached = cachedHistory(for: range) {
            chartData = cached
        }

        do {
            let history = try await priceService.fetchPriceHistory(days: range.days)
                .sorted { $0.date < $1.date }

            guard !history.isEmpty else {
                if let cached = cachedHistory(for: range) {
                    chartData = cached
                }
                return
            }

            chartData = history
            cacheHistory(history, for: range)
        } catch {
            if let cached = cachedHistory(for: range) {
                chartData = cached
            } else {
                handleError(error)
            }
        }
    }

    private func cacheHistory(_ history: [PricePoint], for range: PriceHistoryRange) {
        priceHistoryCache[range] = history
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(history) {
            userDefaults.set(data, forKey: cacheKey(for: range))
        }
    }

    private func cachedHistory(for range: PriceHistoryRange) -> [PricePoint]? {
        if let cached = priceHistoryCache[range] {
            return cached
        }

        if let data = userDefaults.data(forKey: cacheKey(for: range)) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            if let history = try? decoder.decode([PricePoint].self, from: data) {
                priceHistoryCache[range] = history
                return history
            }
        }

        return nil
    }

    private func restoreCachedHistory() {
        if let cached = cachedHistory(for: selectedTimeRange) {
            chartData = cached
        }
    }

    private func cacheKey(for range: PriceHistoryRange) -> String {
        historyCacheKeyPrefix + range.rawValue
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

extension HomeViewModel {
    enum PriceHistoryRange: String, CaseIterable {
        case day = "1D"
        case week = "1W"
        case month = "1M"
        case year = "1Y"
        case all = "All"

        var days: Int {
            switch self {
            case .day:
                return 1
            case .week:
                return 7
            case .month:
                return 30
            case .year:
                return 365
            case .all:
                return 365 * 5
            }
        }
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
