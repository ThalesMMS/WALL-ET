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
                    Button(action: { coordinator.selectTab(.settings) }) {
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
            Button(action: { coordinator.showSend() }) {
                QuickActionButton(
                    icon: "arrow.up.circle.fill",
                    title: "Send",
                    color: Color.Wallet.send
                )
            }
            
            Button(action: { coordinator.showReceive() }) {
                QuickActionButton(
                    icon: "arrow.down.circle.fill",
                    title: "Receive",
                    color: Color.Wallet.receive
                )
            }
            
            Button(action: { coordinator.showScanQR() }) {
                QuickActionButton(
                    icon: "qrcode.viewfinder",
                    title: "Scan",
                    color: Color.Wallet.info
                )
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
                
                Button(action: { coordinator.showCreateWallet() }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(Color.Wallet.bitcoinOrange)
                }
            }
            
            ForEach(viewModel.wallets) { wallet in
                BalanceWalletRowView(wallet: wallet, showBalance: viewModel.showBalance)
                    .onTapGesture { coordinator.selectTab(.transactions) }
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
                    coordinator.showCreateWallet()
                }
                
                SecondaryButton(title: "Import Wallet") {
                    coordinator.showImportWallet()
                }
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct BalanceQuickActionButton: View {
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

struct BalanceWalletRowView: View {
    @StateObject private var viewModel: BalanceWalletRowViewModel
    let showBalance: Bool

    init(
        wallet: Wallet,
        showBalance: Bool,
        currencyCode: String = "USD",
        priceService: PriceDataServiceType = PriceDataService.shared
    ) {
        _viewModel = StateObject(
            wrappedValue: BalanceWalletRowViewModel(
                wallet: wallet,
                currencyCode: currencyCode,
                priceService: priceService
            )
        )
        self.showBalance = showBalance
    }

    var body: some View {
        HStack {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(Color.Wallet.bitcoinOrange)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.wallet.name)
                    .font(.headline)
                    .foregroundColor(Color.Wallet.primaryText)

                Text(viewModel.wallet.type.symbol)
                    .font(.caption)
                    .foregroundColor(Color.Wallet.secondaryText)
            }

            Spacer()

            Group {
                if showBalance {
                    if viewModel.isLoading && viewModel.fiatBalance == nil {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.trailing)
                    } else if let fiatBalance = viewModel.fiatBalance {
                        CompactBalanceView(
                            btcAmount: viewModel.totalBalance,
                            fiatAmount: fiatBalance,
                            currencyCode: viewModel.currencyCode
                        )
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                } else {
                    CompactBalanceView(
                        btcAmount: viewModel.totalBalance,
                        fiatAmount: viewModel.fiatBalance ?? 0,
                        currencyCode: viewModel.currencyCode
                    )
                    .redacted(reason: .placeholder)
                }
            }
        }
        .padding()
        .background(Color.Wallet.secondaryBackground)
        .cornerRadius(Constants.UI.cornerRadius)
        .onAppear {
            let addr = viewModel.wallet.accounts.first?.address ?? ""
            logInfo("Wallet row appear: name=\(viewModel.wallet.name), firstAddress=\(addr.isEmpty ? "<empty>" : addr)")
        }
    }
}

#Preview {
    BalanceScreen()
        .environmentObject(AppCoordinator())
}
