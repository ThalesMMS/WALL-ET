import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedCurrency") private var selectedCurrency = "USD"
    @AppStorage("enableBiometrics") private var enableBiometrics = true
    @AppStorage("hideBalance") private var hideBalance = false
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("darkMode") private var darkMode = false
    @State private var showingBackupAlert = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                // Wallets Section
                Section {
                    NavigationLink(destination: WalletManagementView()) {
                        Label("Manage Wallets", systemImage: "wallet.pass")
                    }
                    
                    NavigationLink(destination: CreateWalletOptionsView()) {
                        Label("Create New Wallet", systemImage: "plus.circle")
                    }
                    
                    NavigationLink(destination: ImportWalletView()) {
                        Label("Import Wallet", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Wallets")
                }
                
                // Security Section
                Section {
                    Toggle(isOn: $enableBiometrics) {
                        Label("Face ID / Touch ID", systemImage: "faceid")
                    }
                    
                    NavigationLink(destination: ChangePasswordView()) {
                        Label("Change Password", systemImage: "lock.rotation")
                    }
                    
                    Toggle(isOn: $hideBalance) {
                        Label("Hide Balances", systemImage: "eye.slash")
                    }
                    
                    NavigationLink(destination: BackupView()) {
                        Label("Backup Seed Phrase", systemImage: "key")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Enable biometric authentication for quick and secure access to your wallet.")
                }
                
                // Preferences Section
                Section {
                    Picker(selection: $selectedCurrency, label: Label("Currency", systemImage: "dollarsign.circle")) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("BRL").tag("BRL")
                        Text("JPY").tag("JPY")
                        Text("CNY").tag("CNY")
                    }
                    
                    Toggle(isOn: $darkMode) {
                        Label("Dark Mode", systemImage: "moon")
                    }
                    
                    Toggle(isOn: $enableNotifications) {
                        Label("Push Notifications", systemImage: "bell")
                    }
                    
                    NavigationLink(destination: NetworkSettingsView()) {
                        Label("Network Settings", systemImage: "network")
                    }
                } header: {
                    Text("Preferences")
                }
                
                // Advanced Section
                Section {
                    NavigationLink(destination: TransactionHistoryExportView()) {
                        Label("Export Transaction History", systemImage: "square.and.arrow.up")
                    }
                    
                    NavigationLink(destination: AddressBookView()) {
                        Label("Address Book", systemImage: "person.2")
                    }
                    
                    NavigationLink(destination: UTXOManagementView()) {
                        Label("UTXO Management", systemImage: "cube.box")
                    }
                    
                    NavigationLink(destination: ElectrumServerView()) {
                        Label("Electrum Server", systemImage: "server.rack")
                    }
                } header: {
                    Text("Advanced")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Text("Privacy Policy")
                    }
                    
                    NavigationLink(destination: TermsOfServiceView()) {
                        Text("Terms of Service")
                    }
                    
                    Link(destination: URL(string: "https://github.com/wallet")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Link(destination: URL(string: "https://twitter.com/wallet")!) {
                        HStack {
                            Text("Twitter")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
                
                // Danger Zone
                Section {
                    Button(action: { showingDeleteAlert = true }) {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will permanently delete all wallets and data from this device. Make sure you have backed up your seed phrases.")
                }
            }
            .navigationTitle("Settings")
            .alert("Delete All Data", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    // Delete all data
                }
            } message: {
                Text("Are you sure you want to delete all wallets and data? This action cannot be undone.")
            }
        }
    }
}

// Placeholder Views for Navigation Destinations
struct WalletManagementView: View {
    var body: some View {
        List {
            WalletRowView(name: "Main Wallet", balance: 1.23456789, isMainnet: true)
            WalletRowView(name: "Savings", balance: 0.48024689, isMainnet: true)
            WalletRowView(name: "Test Wallet", balance: 10.5, isMainnet: false)
        }
        .navigationTitle("Manage Wallets")
    }
}

struct WalletRowView: View {
    let name: String
    let balance: Double
    let isMainnet: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Text(name)
                        .font(.headline)
                    if !isMainnet {
                        Text("TESTNET")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                Text("\(balance, specifier: "%.8f") BTC")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct CreateWalletOptionsView: View {
    var body: some View {
        List {
            NavigationLink(destination: EmptyView()) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Create New Seed", systemImage: "key.fill")
                        .font(.headline)
                    Text("Generate a new 12 or 24 word seed phrase")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            NavigationLink(destination: EmptyView()) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Hardware Wallet", systemImage: "cpu")
                        .font(.headline)
                    Text("Connect Ledger, Trezor, or other hardware wallet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            NavigationLink(destination: EmptyView()) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Watch-Only", systemImage: "eye")
                        .font(.headline)
                    Text("Monitor addresses without private keys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Create Wallet")
    }
}

struct ImportWalletView: View {
    @State private var seedPhrase = ""
    
    var body: some View {
        Form {
            Section {
                TextEditor(text: $seedPhrase)
                    .frame(minHeight: 100)
            } header: {
                Text("Enter Seed Phrase")
            } footer: {
                Text("Enter your 12 or 24 word seed phrase separated by spaces.")
            }
            
            Section {
                Button("Import Wallet") {
                    // Import wallet logic
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Import Wallet")
    }
}

struct ChangePasswordView: View {
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    
    var body: some View {
        Form {
            Section {
                SecureField("Current Password", text: $currentPassword)
                SecureField("New Password", text: $newPassword)
                SecureField("Confirm New Password", text: $confirmPassword)
            }
            
            Section {
                Button("Change Password") {
                    // Change password logic
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Change Password")
    }
}

struct BackupView: View {
    @State private var showSeedPhrase = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "key.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                
                Text("Backup Your Seed Phrase")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Your seed phrase is the master key to your wallet. Write it down and store it in a safe place.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                if showSeedPhrase {
                    VStack(spacing: 12) {
                        ForEach(Array(mockSeedPhrase().enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text("\(index + 1).")
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                                Text(word)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                } else {
                    Button("Show Seed Phrase") {
                        showSeedPhrase = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Never share your seed phrase", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Label("Store it offline in a secure location", systemImage: "lock.shield.fill")
                        .foregroundColor(.orange)
                    Label("Anyone with your seed can access your funds", systemImage: "hand.raised.fill")
                        .foregroundColor(.orange)
                }
                .font(.caption)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("Backup")
    }
    
    func mockSeedPhrase() -> [String] {
        ["abandon", "ability", "able", "about", "above", "absent",
         "absorb", "abstract", "absurd", "abuse", "access", "accident"]
    }
}

struct NetworkSettingsView: View {
    @State private var network = "Mainnet"
    @State private var customNode = ""
    
    var body: some View {
        Form {
            Section {
                Picker("Network", selection: $network) {
                    Text("Mainnet").tag("Mainnet")
                    Text("Testnet").tag("Testnet")
                    Text("Regtest").tag("Regtest")
                }
            } header: {
                Text("Bitcoin Network")
            }
            
            Section {
                TextField("Custom Node URL", text: $customNode)
                Toggle("Use Tor", isOn: .constant(false))
            } header: {
                Text("Connection")
            }
        }
        .navigationTitle("Network Settings")
    }
}

struct TransactionHistoryExportView: View {
    var body: some View {
        List {
            Button("Export as CSV") {}
            Button("Export as PDF") {}
            Button("Export as JSON") {}
        }
        .navigationTitle("Export History")
    }
}

struct AddressBookView: View {
    var body: some View {
        List {
            HStack {
                VStack(alignment: .leading) {
                    Text("Alice")
                        .font(.headline)
                    Text("bc1q...wlh")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Bob")
                        .font(.headline)
                    Text("bc1q...mdq")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .navigationTitle("Address Book")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {}) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct UTXOManagementView: View {
    var body: some View {
        Text("UTXO Management")
            .navigationTitle("UTXO Management")
    }
}

struct ElectrumServerView: View {
    var body: some View {
        Text("Electrum Server Settings")
            .navigationTitle("Electrum Server")
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            Text("Privacy Policy content...")
                .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            Text("Terms of Service content...")
                .padding()
        }
        .navigationTitle("Terms of Service")
    }
}

#Preview {
    SettingsView()
}