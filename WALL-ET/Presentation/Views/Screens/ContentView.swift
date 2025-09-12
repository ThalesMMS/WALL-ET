import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        TabView(selection: .constant(0)) {
            BalanceScreen()
                .tabItem {
                    Label("Balance", systemImage: "bitcoinsign.circle")
                }
                .tag(0)
            
            TransactionsView()
                .tabItem {
                    Label("Transactions", systemImage: "arrow.left.arrow.right")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        // TODO: Add modal support
        // .sheet(isPresented: $coordinator.isShowingModal) {
        //     modalContent
        // }
    }
    
    // TODO: Add modal content support
    // @ViewBuilder
    // private var modalContent: some View {
    //     EmptyView()
    // }
}

struct PlaceholderTransactionsView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("Transactions")
                    .font(.largeTitle)
                    .padding()
                
                Spacer()
                
                Text("Coming Soon")
                    .foregroundColor(Color.Wallet.secondaryText)
                
                Spacer()
            }
            .navigationTitle("Transactions")
        }
    }
}

struct PlaceholderSettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section("Wallets") {
                    NavigationLink(destination: EmptyView()) {
                        Label("Manage Wallets", systemImage: "wallet.pass")
                    }
                }
                
                Section("Security") {
                    NavigationLink(destination: EmptyView()) {
                        Label("Password", systemImage: "lock")
                    }
                    
                    NavigationLink(destination: EmptyView()) {
                        Label("Biometric Authentication", systemImage: "faceid")
                    }
                }
                
                Section("Appearance") {
                    NavigationLink(destination: EmptyView()) {
                        Label("Theme", systemImage: "paintbrush")
                    }
                    
                    NavigationLink(destination: EmptyView()) {
                        Label("Base Currency", systemImage: "dollarsign.circle")
                    }
                }
                
                Section("About") {
                    NavigationLink(destination: EmptyView()) {
                        Label("Version", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct PlaceholderSendView: View {
    let wallet: Wallet
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Send Bitcoin")
                    .font(.largeTitle)
                    .padding()
                
                Text("From: \(wallet.name)")
                    .padding()
                
                Spacer()
                
                Text("Coming Soon")
                    .foregroundColor(Color.Wallet.secondaryText)
                
                Spacer()
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PlaceholderReceiveView: View {
    let wallet: Wallet
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Receive Bitcoin")
                    .font(.largeTitle)
                    .padding()
                
                if let address = wallet.accounts.first?.address {
                    VStack(spacing: 16) {
                        // QR Code placeholder
                        RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                            .fill(Color.Wallet.secondaryBackground)
                            .frame(width: 200, height: 200)
                            .overlay(
                                Image(systemName: "qrcode")
                                    .font(.system(size: 100))
                                    .foregroundColor(Color.Wallet.primaryText)
                            )
                        
                        Text(address)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.Wallet.primaryText)
                            .padding()
                            .background(Color.Wallet.secondaryBackground)
                            .cornerRadius(Constants.UI.smallCornerRadius)
                        
                        Button(action: {
                            UIPasteboard.general.string = address
                        }) {
                            Label("Copy Address", systemImage: "doc.on.doc")
                                .foregroundColor(Color.Wallet.bitcoinOrange)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Receive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppCoordinator())
}