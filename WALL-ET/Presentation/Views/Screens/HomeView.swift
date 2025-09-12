import SwiftUI

struct HomeView: View {
    @State private var showBalance = true
    @State private var bitcoinBalance: Double = 1.23456789
    @State private var fiatBalance: Double = 76543.21
    @State private var priceChange: Double = 5.67
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
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
                    
                    // Quick Actions
                    HStack(spacing: 12) {
                        QuickActionButton(
                            icon: "arrow.up",
                            title: "Send",
                            color: .orange
                        )
                        
                        QuickActionButton(
                            icon: "arrow.down",
                            title: "Receive",
                            color: .blue
                        )
                        
                        QuickActionButton(
                            icon: "arrow.2.squarepath",
                            title: "Swap",
                            color: .purple
                        )
                        
                        QuickActionButton(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Buy",
                            color: .green
                        )
                    }
                    
                    // Wallet Cards
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Wallets")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        WalletCard(
                            walletName: "Main Wallet",
                            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                            balance: 0.75432100,
                            fiatValue: 46543.21,
                            isTestnet: false
                        )
                        
                        WalletCard(
                            walletName: "Savings Wallet",
                            address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                            balance: 0.48024689,
                            fiatValue: 30000.00,
                            isTestnet: false
                        )
                        
                        WalletCard(
                            walletName: "Test Wallet",
                            address: "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx",
                            balance: 10.5,
                            fiatValue: 0,
                            isTestnet: true
                        )
                    }
                    
                    // Recent Transactions
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Recent Transactions")
                                .font(.headline)
                            Spacer()
                            Button("See All") {
                                // Navigate to transactions
                            }
                            .foregroundColor(.orange)
                        }
                        .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            TransactionRow(
                                type: .received,
                                amount: 0.00234567,
                                fiatAmount: 145.67,
                                address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                                date: Date(),
                                status: .confirmed
                            )
                            
                            TransactionRow(
                                type: .sent,
                                amount: 0.00100000,
                                fiatAmount: 62.00,
                                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                                date: Date().addingTimeInterval(-3600),
                                status: .pending
                            )
                            
                            TransactionRow(
                                type: .received,
                                amount: 0.05000000,
                                fiatAmount: 3100.00,
                                address: "bc1q7g8u9w5z3qw7zyxkjmnf6rc02uxzwqg8l5a5n5",
                                date: Date().addingTimeInterval(-86400),
                                status: .confirmed
                            )
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
                HStack(spacing: 4) {
                    Text("\(type == .received ? "+" : "-")\(amount, specifier: "%.8f") BTC")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                    
                    if status == .pending {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Text("$\(fiatAmount, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    HomeView()
}