import Foundation
import Combine

@MainActor
final class BalanceViewModel: ObservableObject {
    @Published var wallets: [Wallet] = []
    @Published var totalBalance: Double = 0.0
    @Published var totalFiatBalance: Double = 0.0
    @Published var isLoading = false
    @Published var showBalance = true
    @Published var errorMessage: String?
    
    private let walletRepository: WalletRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(walletRepository: WalletRepositoryProtocol) {
        self.walletRepository = walletRepository
    }
    
    func loadWallets() async {
        isLoading = true
        errorMessage = nil
        
        do {
            wallets = try await walletRepository.getAllWallets()
            await refreshBalances()
        } catch {
            errorMessage = error.localizedDescription
            logError("Failed to load wallets: \(error)")
        }
        
        isLoading = false
    }
    
    
    
    func toggleBalanceVisibility() {
        showBalance.toggle()
    }
    
    private func updateWalletBalance(walletId: UUID, balance: Balance) {
        if let index = wallets.firstIndex(where: { $0.id == walletId }),
           var account = wallets[index].accounts.first {
            account.balance = balance
            wallets[index].accounts[0] = account
        }
    }
    
    private func calculateTotals(currentPrice: Double) async {
        totalBalance = wallets.reduce(0) { total, wallet in
            let walletBalance = wallet.accounts.reduce(0) { acc, account in acc + account.balance.btcValue }
            return total + walletBalance
        }
        totalFiatBalance = totalBalance * currentPrice
    }

    func refreshBalances() async {
        // Fetch price first
        let price = (try? await PriceService().fetchBTCPrice().price) ?? 0
        for i in wallets.indices {
            if let addr = wallets[i].accounts.first?.address {
                if let bal = try? await walletRepository.getBalance(for: addr) {
                    var account = wallets[i].accounts[0]
                    account.balance = bal
                    wallets[i].accounts[0] = account
                }
            }
        }
        await calculateTotals(currentPrice: price)
    }
}
