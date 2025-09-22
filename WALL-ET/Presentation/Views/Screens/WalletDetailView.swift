import SwiftUI
import Charts
import Combine

struct WalletDetailView: View {
    @StateObject private var viewModel: WalletDetailViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var selectedTimeRange = TimeRange.week
    
    init(walletId: String) {
        self._viewModel = StateObject(wrappedValue: WalletDetailViewModel(walletId: walletId))
    }
    
    enum TimeRange: String, CaseIterable {
        case day = "1D"
        case week = "1W"
        case month = "1M"
        case threeMonths = "3M"
        case year = "1Y"
        case all = "All"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Balance Card
                WalletBalanceCard(
                    wallet: viewModel.wallet,
                    showBalance: viewModel.showBalance,
                    btcPrice: viewModel.currentBTCPrice
                )
                
                // Price Chart
                VStack(alignment: .leading, spacing: 12) {
                    Text("Balance History")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    // Time Range Selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(TimeRange.allCases, id: \.self) { range in
                                TimeRangeButton(
                                    title: range.rawValue,
                                    isSelected: selectedTimeRange == range,
                                    action: {
                                        selectedTimeRange = range
                                        viewModel.loadChartData(for: range)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Chart
                    if !viewModel.chartData.isEmpty {
                        Chart(viewModel.chartData) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Balance", point.value)
                            )
                            .foregroundStyle(Color.orange.gradient)
                            
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Balance", point.value)
                            )
                            .foregroundStyle(Color.orange.opacity(0.1).gradient)
                        }
                        .frame(height: 200)
                        .padding(.horizontal)
                    }
                }
                
                // Quick Actions
                HStack(spacing: 12) {
                    BalanceQuickActionButton(
                        title: "Send",
                        icon: "arrow.up",
                        color: .orange,
                        action: {
                            coordinator.showSend()
                        }
                    )
                    BalanceQuickActionButton(
                        title: "Receive",
                        icon: "arrow.down",
                        color: .blue,
                        action: {
                            coordinator.showReceive()
                        }
                    )
                    BalanceQuickActionButton(
                        title: "Backup",
                        icon: "key",
                        color: .purple,
                        action: {
                            if let wallet = viewModel.wallet {
                                coordinator.showBackup(for: wallet)
                            }
                        }
                    )
                }
                .padding(.horizontal)
                
                // Addresses
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Addresses")
                            .font(.headline)
                        Spacer()
                        Button("Generate New") {
                            viewModel.generateNewAddress()
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                    
                    ForEach(viewModel.addresses) { address in
                        AddressCard(address: address)
                    }
                }
                
                // Recent Transactions
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Recent Transactions")
                            .font(.headline)
                        Spacer()
                        Button("See All") {
                            coordinator.selectedTab = .transactions
                        }
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                    
                    if viewModel.transactions.isEmpty {
                        EmptyStateView(
                            icon: "arrow.left.arrow.right",
                            title: "No Transactions",
                            message: "Your transaction history will appear here"
                        )
                        .padding()
                    } else {
                        ForEach(viewModel.transactions.prefix(5)) { transaction in
                            TransactionRow(
                                type: transaction.type == .received ? .received : .sent,
                                amount: transaction.amount,
                                fiatAmount: transaction.amount * viewModel.currentBTCPrice,
                                address: transaction.address,
                                date: transaction.date,
                                status: transaction.status == .confirmed ? .confirmed : .pending,
                                confirmations: transaction.confirmations
                            )
                            .onTapGesture {
                                coordinator.showTransactionDetail(transaction)
                            }
                        }
                    }
                }
                
                // UTXOs
                if viewModel.showAdvancedFeatures {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("UTXOs")
                            .font(.headline)
                            Spacer()
                            Text("\(viewModel.utxos.count) outputs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        ForEach(viewModel.utxos) { utxo in
                            UTXOCard(utxo: utxo)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(viewModel.wallet?.name ?? "Wallet")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { viewModel.toggleBalanceVisibility() }) {
                        Label(viewModel.showBalance ? "Hide Balance" : "Show Balance",
                              systemImage: viewModel.showBalance ? "eye.slash" : "eye")
                    }
                    
                    Button(action: { viewModel.toggleAdvancedFeatures() }) {
                        Label(viewModel.showAdvancedFeatures ? "Hide Advanced" : "Show Advanced",
                              systemImage: "gearshape")
                    }
                    
                    Divider()
                    
                    Button(action: { viewModel.exportWallet() }) {
                        Label("Export Wallet", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(role: .destructive, action: { viewModel.showDeleteConfirmation() }) {
                        Label("Delete Wallet", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .onAppear {
            viewModel.loadData()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct WalletBalanceCard: View {
    let wallet: WalletModel?
    let showBalance: Bool
    let btcPrice: Double
    
    var body: some View {
        VStack(spacing: 16) {
            // Wallet Icon and Name
            HStack {
                Image(systemName: wallet?.isTestnet ?? false ? "testtube.2" : "bitcoinsign.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(wallet?.name ?? "Wallet")
                        .font(.headline)
                    
                    if wallet?.isTestnet ?? false {
                        Text("TESTNET")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Balance
            VStack(alignment: .leading, spacing: 8) {
                Text("Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .bottom, spacing: 4) {
                    if showBalance {
                        Text("\(wallet?.balance ?? 0, specifier: "%.8f")")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    } else {
                        Text("••••••••")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Text("BTC")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                }
                
                if !(wallet?.isTestnet ?? false) {
                    Text(showBalance ? "$\((wallet?.balance ?? 0) * btcPrice, specifier: "%.2f") USD" : "$••••••")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Address
            VStack(alignment: .leading, spacing: 8) {
                Text("Primary Address")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(wallet?.displayAddress ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    
                    Button(action: {
                        UIPasteboard.general.string = wallet?.address
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

struct AddressCard: View {
    let address: AddressModel
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(address.label ?? "Address #\(address.index)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(address.derivationPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(address.balance, specifier: "%.8f") BTC")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                    
                    Text("\(address.transactionCount) txs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text(address.address)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Button(action: {
                    UIPasteboard.general.string = address.address
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct UTXOCard: View {
    let utxo: UTXOModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UTXO")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(utxo.value, specifier: "%.8f") BTC")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
            }
            
            HStack {
                Text("\(utxo.txid.prefix(10))...")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text(":\(utxo.vout)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(utxo.confirmations) conf")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct TimeRangeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.orange : Color(.systemGray5))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
    }
}

struct WalletActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .cornerRadius(12)
        }
    }
}

// MARK: - View Model
@MainActor
class WalletDetailViewModel: ObservableObject {
    @Published var wallet: WalletModel?
    @Published var addresses: [AddressModel] = []
    @Published var transactions: [TransactionModel] = []
    @Published var utxos: [UTXOModel] = []
    @Published var chartData: [ChartDataPoint] = []
    @Published var showBalance = true
    @Published var showAdvancedFeatures = false
    @Published var currentBTCPrice: Double = 62000
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let walletId: String
    private let walletService: WalletServiceProtocol
    private let transactionService: TransactionServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    init(walletId: String,
         walletService: WalletServiceProtocol? = nil,
         transactionService: TransactionServiceProtocol? = nil) {
        self.walletId = walletId
        self.walletService = walletService ?? WalletService()
        self.transactionService = transactionService ?? TransactionService()
        ElectrumService.shared.transactionUpdatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] update in self?.applyUpdate(update) }
            .store(in: &cancellables)
    }
    
    func loadData() {
        Task {
            isLoading = true
            
            if let uuid = UUID(uuidString: walletId) {
                wallet = try? await walletService.getWalletDetails(uuid)
            }
            
            // Load addresses with live balances + tx counts
            if let uuid = UUID(uuidString: walletId) {
                addresses = await loadAddresses(for: uuid)
            }
            
            // Load transactions
            transactions = (try? await transactionService.fetchRecentTransactions(limit: 10)) ?? []
            
            // Load UTXOs (aggregated)
            if let uuid = UUID(uuidString: walletId) {
                utxos = await loadUTXOs(for: uuid)
            }
            
            // Load chart data
            loadChartData(for: .week)
            
            isLoading = false
        }
    }
    
    private func applyUpdate(_ update: ElectrumService.TransactionUpdate) {
        if let idx = transactions.firstIndex(where: { $0.id == update.txid }) {
            let t = transactions[idx]
            let newStatus: TransactionStatus = update.confirmations >= 6 ? .confirmed : .pending
            let updated = TransactionModel(
                id: t.id,
                type: t.type,
                amount: t.amount,
                fee: t.fee,
                address: t.address,
                date: t.date,
                status: newStatus,
                confirmations: update.confirmations
            )
            transactions[idx] = updated
        }
    }
    
    func refresh() async {
        loadData()
    }
    
    func loadChartData(for range: WalletDetailView.TimeRange) {
        // Build a running balance series from transactions
        let horizon: TimeInterval = {
            switch range {
            case .day: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .month: return 30 * 24 * 3600
            case .threeMonths: return 90 * 24 * 3600
            case .year: return 365 * 24 * 3600
            case .all: return 10 * 365 * 24 * 3600
            }
        }()
        let cutoff = Date().addingTimeInterval(-horizon)
        let txs = transactions.sorted { $0.date < $1.date }
        var running: Double = 0
        var points: [ChartDataPoint] = []
        for t in txs {
            running += (t.type == .received ? t.amount : -t.amount)
            if t.date >= cutoff { points.append(ChartDataPoint(date: t.date, value: running)) }
        }
        if points.isEmpty { points = [ChartDataPoint(date: Date(), value: 0)] }
        chartData = points
    }
    
    private func daysForRange(_ range: WalletDetailView.TimeRange) -> Int {
        switch range {
        case .day: return 24
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .year: return 365
        case .all: return 730
        }
    }
    
    func toggleBalanceVisibility() {
        showBalance.toggle()
    }
    
    func toggleAdvancedFeatures() {
        showAdvancedFeatures.toggle()
    }
    
    func generateNewAddress() {
        // Generate new address logic
    }
    
    func exportWallet() {
        guard let uuid = UUID(uuidString: walletId) else {
            errorMessage = "Invalid wallet identifier"
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let exportContent = try await walletService.exportWallet(uuid)
                let fileURL = try writeExportFile(named: wallet?.name ?? "wallet", contents: exportContent)
                NotificationCenter.default.post(name: .shareFile, object: nil, userInfo: ["url": fileURL])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func writeExportFile(named walletName: String, contents: String) throws -> URL {
        guard let data = contents.data(using: .utf8) else {
            throw WalletExportError.serializationFailed
        }

        let sanitizedBase = walletName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()

        let fileName = (sanitizedBase.isEmpty ? "wallet" : sanitizedBase) + "-export.wallet"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
    
    func showDeleteConfirmation() {
        // Show delete confirmation
    }
    
    // Live data helpers
    private func loadAddresses(for walletId: UUID) async -> [AddressModel] {
        let repo = DefaultWalletRepository(keychainService: KeychainService())
        let addrs = repo.listAddresses(for: walletId)
        if addrs.isEmpty { return [] }
        return await withTaskGroup(of: AddressModel?.self, returning: [AddressModel].self) { group in
            for (i, addr) in addrs.enumerated() {
                group.addTask {
                    // Fetch balance
                    let balance: Double = await withCheckedContinuation { (cont: CheckedContinuation<Double, Never>) in
                        ElectrumService.shared.getBalance(for: addr) { result in
                            switch result {
                            case .success(let ab): cont.resume(returning: Double(ab.confirmed + ab.unconfirmed) / 100_000_000.0)
                            case .failure: cont.resume(returning: 0)
                            }
                        }
                    }
                    // Fetch tx count
                    let txCount: Int = await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
                        ElectrumService.shared.getAddressHistory(for: addr) { result in
                            switch result { case .success(let hist): cont.resume(returning: hist.count); case .failure: cont.resume(returning: 0) }
                        }
                    }
                    return AddressModel(index: i, address: addr, label: i == 0 ? "Primary" : nil, balance: balance, transactionCount: txCount, derivationPath: "")
                }
            }
            var result: [AddressModel] = []
            for await m in group { if let m { result.append(m) } }
            return result.sorted { $0.index < $1.index }
        }
    }

    private func loadUTXOs(for walletId: UUID) async -> [UTXOModel] {
        let repo = DefaultWalletRepository(keychainService: KeychainService())
        let addrs = repo.listAddresses(for: walletId)
        if addrs.isEmpty { return [] }
        return await withTaskGroup(of: [UTXOModel].self, returning: [UTXOModel].self) { group in
            for addr in addrs {
                group.addTask {
                    let res: [UTXOModel] = await withCheckedContinuation { (cont: CheckedContinuation<[UTXOModel], Never>) in
                        ElectrumService.shared.getUTXOs(for: addr) { result in
                            switch result {
                            case .success(let utxos):
                                let mapped = utxos.map { UTXOModel(txid: $0.txHash, vout: $0.txPos, value: Double($0.value) / 100_000_000.0, confirmations: max(0, $0.height)) }
                                cont.resume(returning: mapped)
                            case .failure:
                                cont.resume(returning: [])
                            }
                        }
                    }
                    return res
                }
            }
            var all: [UTXOModel] = []
            for await arr in group { all.append(contentsOf: arr) }
            return all
        }
    }
}

// MARK: - Supporting Models
struct AddressModel: Identifiable {
    let id = UUID()
    let index: Int
    let address: String
    let label: String?
    let balance: Double
    let transactionCount: Int
    let derivationPath: String
}

struct UTXOModel: Identifiable {
    let id = UUID()
    let txid: String
    let vout: Int
    let value: Double
    let confirmations: Int
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

#Preview {
    NavigationView {
        WalletDetailView(walletId: UUID().uuidString)
            .environmentObject(AppCoordinator())
    }
}
