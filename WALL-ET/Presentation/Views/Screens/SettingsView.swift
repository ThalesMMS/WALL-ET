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
                    
                    NavigationLink(destination: CreateWalletView()) {
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

// Real Wallet Management (Core Data via repository)
struct WalletManagementView: View {
    @State private var wallets: [Wallet] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activeId: UUID?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading wallets…")
            } else if wallets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bitcoinsign.circle")
                        .font(.system(size: 56))
                        .foregroundColor(.orange)
                    Text("No Wallets Found").font(.headline)
                    Text("Create or import a wallet from Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        NavigationLink(destination: CreateWalletView()) {
                            Text("Create Wallet").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        NavigationLink(destination: ImportWalletView()) {
                            Text("Import Wallet").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(wallets, id: \.id) { wallet in
                        NavigationLink(destination: WalletDetailView(walletId: wallet.id.uuidString)) {
                            WalletListRow(wallet: wallet, isActive: wallet.id == activeId)
                        }
                        .task { await DefaultWalletRepository(keychainService: KeychainService()).ensureGapLimit(for: wallet.id) }
                        .swipeActions(edge: .trailing) {
                            Button("Set Active") { setActive(wallet.id) }
                                .tint(.orange)
                        }
                    }
                    .onDelete(perform: deleteWallets)
                }
        }
        }
        .navigationTitle("Manage Wallets")
        .onAppear(perform: loadWallets)
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
    
    private func loadWallets() {
        isLoading = true
        Task {
            if let repo: WalletRepositoryProtocol = DIContainer.shared.resolve(WalletRepositoryProtocol.self) {
                let list = (try? await repo.getAllWallets()) ?? []
                await MainActor.run {
                    self.wallets = list
                    self.isLoading = false
                }
                // Determine active wallet id
                let active = DefaultWalletRepository(keychainService: KeychainService()).getActiveWallet()
                await MainActor.run { self.activeId = active?.id }
            } else {
                await MainActor.run {
                    self.errorMessage = "Repository unavailable"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func deleteWallets(at offsets: IndexSet) {
        let ids = offsets.map { wallets[$0].id }
        Task {
            if let repo: WalletRepositoryProtocol = DIContainer.shared.resolve(WalletRepositoryProtocol.self) {
                for id in ids { try? await repo.deleteWallet(by: id) }
                await MainActor.run {
                    wallets.remove(atOffsets: offsets)
                }
            }
        }
    }

    private func setActive(_ id: UUID) {
        Task {
            await WalletService().setActiveWallet(id)
            await MainActor.run { self.activeId = id }
        }
    }
}

struct WalletListRow: View {
    let wallet: Wallet
    var isActive: Bool = false
    
    private var isTestnet: Bool { wallet.type == .testnet }
    private var btcBalance: Double {
        wallet.accounts.reduce(0) { $0 + $1.balance.btcValue }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(wallet.name).font(.headline)
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
                Text("\(btcBalance, specifier: "%.8f") BTC")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.green)
            }
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 6)
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
    @State private var walletName = "Imported Wallet"
    @AppStorage("network_type") private var networkType = "mainnet"
    @State private var errorMessage: String?
    @State private var isImporting = false
    @Environment(\.dismiss) private var dismiss
    
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
                TextField("Wallet Name", text: $walletName)
            }
            Section {
                Picker("Network", selection: $networkType) {
                    Text("Mainnet").tag("mainnet")
                    Text("Testnet").tag("testnet")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section {
                Button(isImporting ? "Importing…" : "Import Wallet", action: importWallet)
                .frame(maxWidth: .infinity)
                .disabled(isImporting || seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Import Wallet")
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private func importWallet() {
        let phrase = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        isImporting = true
        Task { @MainActor in
            do {
                let valid = try MnemonicService.shared.validateMnemonic(phrase)
                guard valid else { errorMessage = "Invalid recovery phrase"; isImporting = false; return }
                let type: WalletType = (networkType == "mainnet") ? .bitcoin : .testnet
                if let repo: WalletRepositoryProtocol = DIContainer.shared.resolve(WalletRepositoryProtocol.self) {
                    let _ = try await repo.importWallet(mnemonic: phrase, name: walletName, type: type)
                    dismiss()
                } else {
                    errorMessage = "Repository unavailable"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
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
    @AppStorage("network_type") private var networkType = "mainnet"
    @AppStorage("electrum_host") private var host = "electrum.blockstream.info"
    @AppStorage("electrum_port") private var port: Int = 50002
    @AppStorage("electrum_ssl") private var useSSL: Bool = true
    @AppStorage("gap_limit") private var gapLimit: Int = 20
    @AppStorage("auto_rotate_receive") private var autoRotate: Bool = true
    @State private var reconnecting = false
    @State private var portText: String = ""
    
    var body: some View {
        Form {
            Section {
                Picker("Network", selection: $networkType) {
                    Text("Mainnet").tag("mainnet")
                    Text("Testnet").tag("testnet")
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: networkType) { val in
                    // Adjust default port when switching networks if using default host
                    if host == "electrum.blockstream.info" {
                        port = (val == "mainnet") ? 50002 : 60002
                        portText = String(port)
                        useSSL = true
                    }
                }
            } header: {
                Text("Bitcoin Network")
            }
            
            Section {
                TextField("Host", text: $host)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: portText) { s in
                            let cleaned = s.filter { $0.isNumber }
                            if cleaned != s { portText = cleaned }
                            if let v = Int(cleaned), v >= 1 && v <= 65535 { port = v }
                        }
                        .frame(maxWidth: 100)
                }
                Toggle("Use SSL", isOn: $useSSL)
            } header: {
                Text("Electrum Server")
            }

            Section {
                HStack {
                    Text("Gap Limit")
                    Spacer()
                    TextField("20", text: Binding(
                        get: { String(gapLimit) },
                        set: { s in if let v = Int(s.filter { $0.isNumber }), v >= 1 && v <= 1000 { gapLimit = v } }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                }
                Toggle("Auto-rotate receive address", isOn: $autoRotate)
            } header: {
                Text("Addresses")
            } footer: {
                Text("Gap limit is how many future receive addresses are pre-scanned to detect funds. 20 is standard.")
            }
            
            Section {
                Button(action: applyAndReconnect) {
                    if reconnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Apply and Reconnect")
                    }
                }
                .disabled(reconnecting)
            }
        }
        .navigationTitle("Network Settings")
        .onAppear { portText = String(port) }
    }
    
    private func applyAndReconnect() {
        reconnecting = true
        let net: BitcoinService.Network = (networkType == "mainnet") ? .mainnet : .testnet
        ElectrumService.shared.updateServer(host: host, port: port, useSSL: useSSL, network: net)
        ElectrumService.shared.disconnect()
        ElectrumService.shared.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            reconnecting = false
        }
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
