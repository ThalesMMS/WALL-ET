import SwiftUI

struct BalanceScreen: View {
    @StateObject private var viewModel: BalanceViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    
    init() {
        let repository = DIContainer.shared.resolve(WalletRepositoryProtocol.self)!
        _viewModel = StateObject(wrappedValue: BalanceViewModel(walletRepository: repository))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.Wallet.background
                    .ignoresSafeArea()
                
                if viewModel.isLoading && viewModel.wallets.isEmpty {
                    ProgressView("Loading wallets...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else if viewModel.wallets.isEmpty {
                    EmptyWalletView()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Total Balance Header
                            totalBalanceHeader
                            
                            // Quick Actions
                            quickActionsView
                            
                            // Wallets List
                            walletsListView
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.refreshBalances()
                    }
                }
            }
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { viewModel.toggleBalanceVisibility() }) {
                        Image(systemName: viewModel.showBalance ? "eye" : "eye.slash")
                            .foregroundColor(Color.Wallet.primaryText)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { coordinator.navigate(to: .settings) }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(Color.Wallet.primaryText)
                    }
                }
            }
        }
        .task {
            await viewModel.loadWallets()
        }
    }
    
    private var totalBalanceHeader: some View {
        VStack(spacing: 16) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundColor(Color.Wallet.secondaryText)
            
            BalanceCard(
                btcAmount: viewModel.totalBalance,
                fiatAmount: viewModel.totalFiatBalance,
                currencyCode: "USD",
                showBalance: viewModel.showBalance
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.Wallet.secondaryBackground)
        .cornerRadius(Constants.UI.cornerRadius)
    }
    
    private var quickActionsView: some View {
        HStack(spacing: 16) {
            QuickActionButton(
                title: "Send",
                icon: "arrow.up.circle.fill",
                color: Color.Wallet.send
            ) {
                if let wallet = viewModel.wallets.first {
                    coordinator.presentModal(.send(wallet: wallet))
                }
            }
            
            QuickActionButton(
                title: "Receive",
                icon: "arrow.down.circle.fill",
                color: Color.Wallet.receive
            ) {
                if let wallet = viewModel.wallets.first {
                    coordinator.presentModal(.receive(wallet: wallet))
                }
            }
            
            QuickActionButton(
                title: "Scan",
                icon: "qrcode.viewfinder",
                color: Color.Wallet.info
            ) {
                // Handle QR scan
            }
        }
    }
    
    private var walletsListView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("My Wallets")
                    .font(.headline)
                    .foregroundColor(Color.Wallet.primaryText)
                
                Spacer()
                
                Button(action: { coordinator.presentModal(.createWallet) }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(Color.Wallet.bitcoinOrange)
                }
            }
            
            ForEach(viewModel.wallets) { wallet in
                WalletRowView(wallet: wallet, showBalance: viewModel.showBalance)
                    .onTapGesture {
                        coordinator.navigate(to: .transactions)
                    }
            }
        }
    }
}

struct EmptyWalletView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "bitcoinsign.circle")
                .font(.system(size: 80))
                .foregroundColor(Color.Wallet.bitcoinOrange)
            
            Text("No Wallets Yet")
                .font(.title2)
                .bold()
            
            Text("Create or import a wallet to get started")
                .font(.body)
                .foregroundColor(Color.Wallet.secondaryText)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                PrimaryButton(title: "Create New Wallet") {
                    coordinator.presentModal(.createWallet)
                }
                
                SecondaryButton(title: "Import Wallet") {
                    coordinator.presentModal(.importWallet)
                }
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(Color.Wallet.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.Wallet.secondaryBackground)
            .cornerRadius(Constants.UI.cornerRadius)
        }
    }
}

struct WalletRowView: View {
    let wallet: Wallet
    let showBalance: Bool
    
    private var totalBalance: Double {
        wallet.accounts.reduce(0) { $0 + $1.balance.btcValue }
    }
    
    private var fiatBalance: Double {
        totalBalance * 37000 // Mock exchange rate
    }
    
    var body: some View {
        HStack {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(Color.Wallet.bitcoinOrange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(wallet.name)
                    .font(.headline)
                    .foregroundColor(Color.Wallet.primaryText)
                
                Text(wallet.type.symbol)
                    .font(.caption)
                    .foregroundColor(Color.Wallet.secondaryText)
            }
            
            Spacer()
            
            CompactBalanceView(
                btcAmount: totalBalance,
                fiatAmount: fiatBalance,
                currencyCode: "USD"
            )
        }
        .padding()
        .background(Color.Wallet.secondaryBackground)
        .cornerRadius(Constants.UI.cornerRadius)
    }
}

#Preview {
    BalanceScreen()
        .environmentObject(AppCoordinator())
}