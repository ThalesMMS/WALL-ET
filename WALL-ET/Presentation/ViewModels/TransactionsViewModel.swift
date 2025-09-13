import Foundation
import Combine

@MainActor
class TransactionsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var transactions: [TransactionModel] = []
    @Published var filteredTransactions: [TransactionModel] = []
    @Published var searchText = ""
    @Published var selectedFilter: TransactionFilter = .all
    @Published var isLoading = false
    @Published var selectedTransaction: TransactionModel?
    @Published var showTransactionDetail = false
    @Published var errorMessage: String?
    
    // MARK: - Pagination
    @Published var currentPage = 1
    @Published var hasMorePages = true
    private let pageSize = 20
    
    // MARK: - Services
    private let transactionService: TransactionServiceProtocol
    private var useNewPipeline: Bool = UserDefaults.standard.bool(forKey: "useNewTxPipeline")
    // New pipeline components
    private var poolGroup: PoolGroup?
    private var poolCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case received = "Received"
        case pending = "Pending"
        case confirmed = "Confirmed"
    }
    
    // MARK: - Initialization
    init(transactionService: TransactionServiceProtocol? = nil) {
        self.transactionService = transactionService ?? TransactionService()
        setupBindings()
        if useNewPipeline {
            setupNewPipeline()
            refresh()
        } else {
            // Wait for Electrum connectivity; still attempt an initial load (will no-op if empty)
            loadTransactions()
        }
        ElectrumService.shared.connectionStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .connected:
                    // Refetch when connection becomes ready
                    self.refresh()
                case .failed, .disconnected:
                    // Stop spinner if we were waiting endlessly
                    self.isLoading = false
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Search and filter binding
        Publishers.CombineLatest($searchText, $selectedFilter)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] searchText, filter in
                self?.applyFilters(searchText: searchText, filter: filter)
            }
            .store(in: &cancellables)
        
        // Listen for new transactions
        NotificationCenter.default.publisher(for: .transactionReceived)
            .sink { [weak self] notification in
                if let transaction = notification.object as? TransactionModel {
                    self?.handleNewTransaction(transaction)
                }
            }
            .store(in: &cancellables)

        ElectrumService.shared.transactionUpdatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] update in
                self?.applyUpdate(update)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    func loadTransactions() {
        if useNewPipeline {
            Task {
                isLoading = true
                let targetCount = currentPage * pageSize
                if let items = try? await poolGroup?.itemsSingle(count: targetCount) {
                    transactions = items
                    applyFilters(searchText: searchText, filter: selectedFilter)
                }
                isLoading = false
            }
            return
        }
        Task {
            isLoading = true
            do {
                let fetchedTransactions = try await transactionService.fetchTransactions(
                    page: currentPage,
                    pageSize: pageSize
                )
                
                if currentPage == 1 {
                    transactions = fetchedTransactions
                } else {
                    transactions.append(contentsOf: fetchedTransactions)
                }
                
                hasMorePages = fetchedTransactions.count == pageSize
                applyFilters(searchText: searchText, filter: selectedFilter)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    func loadMoreIfNeeded(currentItem: TransactionModel) {
        guard let lastItem = filteredTransactions.last,
              lastItem.id == currentItem.id,
              hasMorePages,
              !isLoading else { return }
        
        currentPage += 1
        loadTransactions()
    }
    
    func refresh() {
        currentPage = 1
        hasMorePages = true
        loadTransactions()
    }
    
    // MARK: - Filtering
    private func applyFilters(searchText: String, filter: TransactionFilter) {
        var filtered = transactions
        
        // Apply filter
        switch filter {
        case .all:
            break
        case .sent:
            filtered = filtered.filter { $0.type == .sent }
        case .received:
            filtered = filtered.filter { $0.type == .received }
        case .pending:
            filtered = filtered.filter { $0.status == .pending }
        case .confirmed:
            filtered = filtered.filter { $0.status == .confirmed }
        }
        
        // Apply search
        if !searchText.isEmpty {
            filtered = filtered.filter { transaction in
                transaction.address.lowercased().contains(searchText.lowercased()) ||
                transaction.id.lowercased().contains(searchText.lowercased()) ||
                String(format: "%.8f", transaction.amount).contains(searchText)
            }
        }
        
        filteredTransactions = filtered
    }
    
    // MARK: - Transaction Actions
    func selectTransaction(_ transaction: TransactionModel) {
        selectedTransaction = transaction
        showTransactionDetail = true
    }
    
    func speedUpTransaction(_ transaction: TransactionModel) {
        guard transaction.status == .pending else { return }
        
        Task {
            do {
                try await transactionService.speedUpTransaction(transaction.id)
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func cancelTransaction(_ transaction: TransactionModel) {
        guard transaction.status == .pending else { return }
        
        Task {
            do {
                try await transactionService.cancelTransaction(transaction.id)
                refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Export
    func exportTransactions(format: ExportFormat) {
        Task {
            do {
                let exportURL = try await transactionService.exportTransactions(
                    filteredTransactions,
                    format: format
                )
                
                NotificationCenter.default.post(
                    name: .shareFile,
                    object: nil,
                    userInfo: ["url": exportURL]
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case pdf = "PDF"
        case json = "JSON"
    }
    
    // MARK: - Grouping
    func groupedTransactions() -> [(String, [TransactionModel])] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            formatDateSection(transaction.date)
        }
        
        return grouped.sorted { $0.value[0].date > $1.value[0].date }
            .map { ($0.key, $0.value) }
    }
    
    private func formatDateSection(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Real-time Updates
    private func handleNewTransaction(_ transaction: TransactionModel) {
        transactions.insert(transaction, at: 0)
        applyFilters(searchText: searchText, filter: selectedFilter)
    }

    private func applyUpdate(_ update: ElectrumService.TransactionUpdate) {
        func updated(_ t: TransactionModel) -> TransactionModel {
            var status = t.status
            if update.confirmations >= 6 { status = .confirmed }
            else if update.confirmations >= 1 { status = .pending }
            return TransactionModel(
                id: t.id,
                type: t.type,
                amount: t.amount,
                fee: t.fee,
                address: t.address,
                date: t.date,
                status: status,
                confirmations: update.confirmations
            )
        }
        if let idx = transactions.firstIndex(where: { $0.id == update.txid }) {
            transactions[idx] = updated(transactions[idx])
            applyFilters(searchText: searchText, filter: selectedFilter)
        }
    }
}

private extension TransactionsViewModel {
    func setupNewPipeline() {
        // Build adapter + pool group
        let adapter = ElectrumTransactionsAdapter()
        let provider = PoolProvider(adapter: adapter)
        let pool = Pool(provider: provider)
        self.poolGroup = PoolGroup(pools: [pool])
        // Listen for updates and re-apply filters
        poolGroup?.itemsUpdatedPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] partial in
                guard let self = self else { return }
                // Merge partials into current list and reapply filters
                var ids = Set(self.transactions.map { $0.id })
                var changed = false
                for m in partial where !ids.contains(m.id) {
                    self.transactions.append(m)
                    ids.insert(m.id)
                    changed = true
                }
                if changed {
                    // Keep sorted by date desc
                    self.transactions.sort { $0.date > $1.date }
                    self.applyFilters(searchText: self.searchText, filter: self.selectedFilter)
                }
            }
            .store(in: &poolCancellables)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let transactionReceived = Notification.Name("transactionReceived")
    static let shareFile = Notification.Name("shareFile")
}
