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
            await calculateTotalBalance()
        } catch {
            errorMessage = error.localizedDescription
            logError("Failed to load wallets: \(error)")
        }
        
        isLoading = false
    }
    
    func refreshBalances() async {
        for wallet in wallets {
            if let firstAccount = wallet.accounts.first {
                do {
                    let balance = try await walletRepository.getBalance(for: firstAccount.address)
                    updateWalletBalance(walletId: wallet.id, balance: balance)
                } catch {
                    logError("Failed to refresh balance for wallet \(wallet.id): \(error)")
                }
            }
        }
        await calculateTotalBalance()
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
    
    private func calculateTotalBalance() async {
        totalBalance = wallets.reduce(0) { total, wallet in
            let walletBalance = wallet.accounts.reduce(0) { acc, account in
                acc + account.balance.btcValue
            }
            return total + walletBalance
        }
        
        // Mock exchange rate - in real app, fetch from API
        let btcToUsd = 37000.0
        totalFiatBalance = totalBalance * btcToUsd
    }
}