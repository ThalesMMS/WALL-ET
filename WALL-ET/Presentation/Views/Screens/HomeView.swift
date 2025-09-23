import SwiftUI

struct HomeView: View {
    @State private var wallets: [Wallet] = []
    @State private var isLoadingWallets = false
    @State private var showCreateSheet = false
    @State private var showImportSheet = false
    @State private var showSendSheet = false
    @State private var showReceiveSheet = false
    @State private var showBalance = true
    @State private var bitcoinBalance: Double = 0
    @State private var fiatBalance: Double = 0
    @State private var priceChange: Double = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if wallets.isEmpty && !isLoadingWallets {
                        VStack(spacing: 16) {
                            Image(systemName: "bitcoinsign.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.orange)
                            Text("No Wallets Yet")
                                .font(.title2).bold()
                            Text("Create or import a wallet to get started")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            PrimaryButton(title: "Create Wallet") { showCreateSheet = true }
                            SecondaryButton(title: "Import Wallet") { showImportSheet = true }
                        }
                        .padding(.vertical, 40)
                    } else {
                        // Balance Card
                        VStack(spacing: 16) {
                        HStack {
                            Text("Total Balance")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: { showBalance.toggle() }) {
                                Image(systemName: showBalance ? "eye" : "eye.slash")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // BTC Balance
                            HStack(alignment: .bottom, spacing: 4) {
                                if showBalance {
                                    Text("\(bitcoinBalance, specifier: "%.8f")")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                } else {
                                    Text("••••••••")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                }
                                Text("BTC")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 4)
                            }
                            
                            // Fiat Balance
                            HStack {
                                if showBalance {
                                    Text("$\(fiatBalance, specifier: "%.2f")")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("$••••••")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                
                                // Price change
                                HStack(spacing: 2) {
                                    Image(systemName: priceChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                                        .font(.caption)
                                    Text("\(abs(priceChange), specifier: "%.2f")%")
                                        .font(.caption)
                                }
                                .foregroundColor(priceChange >= 0 ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill((priceChange >= 0 ? Color.green : Color.red).opacity(0.1))
                                )
                            }
                        }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                        
                        // Quick Actions (send/receive only)
                        HStack(spacing: 12) {
                            Button(action: { showSendSheet = true }) {
                                QuickActionButton(icon: "arrow.up", title: "Send", color: .orange)
                            }
                            Button(action: { showReceiveSheet = true }) {
                                QuickActionButton(icon: "arrow.down", title: "Receive", color: .blue)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("WALL-ET")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "bell")
                    }
                }
            }
            .onAppear { loadWallets() }
            .sheet(isPresented: $showCreateSheet, onDismiss: { loadWallets() }) {
                CreateWalletView()
            }
            .sheet(isPresented: $showImportSheet, onDismiss: { loadWallets() }) {
                ImportWalletView()
            }
            .sheet(isPresented: $showSendSheet) {
                SendView(viewModel: SendViewModel())
            }
            .sheet(isPresented: $showReceiveSheet) {
                ReceiveView(viewModel: ReceiveViewModel())
            }
        }
    }
}

private extension HomeView {
    func loadWallets() {
        isLoadingWallets = true
        Task {
            if let repo: WalletRepositoryProtocol = DIContainer.shared.resolve(WalletRepositoryProtocol.self) {
                let list = (try? await repo.getAllWallets()) ?? []
                await MainActor.run {
                    self.wallets = list
                    self.isLoadingWallets = false
                }
            } else {
                await MainActor.run { self.isLoadingWallets = false }
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                )
            
            Text(title)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WalletCard: View {
    let walletName: String
    let address: String
    let balance: Double
    let fiatValue: Double
    let isTestnet: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(walletName)
                            .font(.headline)
                        if isTestnet {
                            Text("TESTNET")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(String(address.prefix(20)) + "..." + String(address.suffix(6)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(balance, specifier: "%.8f") BTC")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                    
                    if !isTestnet {
                        Text("$\(fiatValue, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TransactionRow: View {
    enum TransactionType {
        case sent, received
    }
    
    enum Status {
        case pending, confirmed, failed
    }
    
    let type: TransactionType
    let amount: Double
    let fiatAmount: Double
    let address: String
    let date: Date
    let status: Status
    let confirmations: Int
    
    var body: some View {
        HStack {
            Circle()
                .fill(type == .received ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: type == .received ? "arrow.down" : "arrow.up")
                        .foregroundColor(type == .received ? .green : .red)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type == .received ? "Received" : "Sent")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(String(address.prefix(10)) + "..." + String(address.suffix(6)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(type == .received ? "+" : "-")\(amount, specifier: "%.8f") BTC")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                    
                    confirmationsBadge
                }
                
                Text("$\(fiatAmount, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
    
    private var confirmationsBadge: some View {
        let conf = confirmations
        let shown = min(conf, 6)
        let text = conf >= 6 ? "6/6" : "\(shown)/6"
        let color: Color = conf >= 6 ? .green : .orange
        return Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

#Preview {
    HomeView()
}
