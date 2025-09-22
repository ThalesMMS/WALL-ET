import SwiftUI

struct TransactionsView: View {
    @State private var selectedTransaction: TransactionItem?
    @State private var wallets: [Wallet] = []
    @State private var isLoadingWallets = false
    @State private var showCreateSheet = false
    @State private var showImportSheet = false
    
    @StateObject private var txvm = TransactionsViewModel()
    
    var body: some View {
        NavigationView {
            List {
                Section { filterBar }

                // Sempre renderiza a lista de transações quando houver dados
                ForEach(txvm.groupedTransactions(), id: \.0) { section in
                    Section(section.0) {
                        ForEach(section.1, id: \.id) { model in
                            TransactionListItem(transaction: toItem(model))
                                .onAppear { txvm.loadMoreIfNeeded(currentItem: model) }
                        }
                    }
                }

                // Spinner
                if txvm.isLoading {
                    Section { ProgressView("Loading…") }
                }

                // Empty state guiado pelos dados
                if !txvm.isLoading && txvm.filteredTransactions.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "clock.arrow.circlepath").font(.system(size: 40)).foregroundColor(.secondary)
                            Text(wallets.isEmpty ? "No transactions yet" : "No transactions match your filters")
                                .font(.headline)
                            if wallets.isEmpty && !isLoadingWallets {
                                Text("Create or import a wallet to see history.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 12) {
                                    Button(action: { showCreateSheet = true }) { Text("Create Wallet").frame(maxWidth: .infinity) }
                                        .buttonStyle(.borderedProminent).tint(.orange)
                                    Button(action: { showImportSheet = true }) { Text("Import Wallet").frame(maxWidth: .infinity) }
                                        .buttonStyle(.bordered)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Transactions")
            .searchable(text: $txvm.searchText, prompt: "Search transactions")
            .onAppear {
                // manter o carregamento de wallets (para exibir CTAs)
                loadWallets()
                // atualização rápida ao entrar
                if txvm.transactions.isEmpty { txvm.refresh() }
            }
            .sheet(isPresented: $showCreateSheet, onDismiss: { loadWallets() }) { CreateWalletView() }
            .sheet(isPresented: $showImportSheet, onDismiss: { loadWallets() }) { ImportWalletView() }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { txvm.errorMessage != nil },
                    set: { if !$0 { txvm.errorMessage = nil } }
                )
            ) {
                Button("OK") { txvm.errorMessage = nil }
            } message: {
                Text(txvm.errorMessage ?? "")
            }
            .alert(
                "Success",
                isPresented: Binding(
                    get: { txvm.successMessage != nil },
                    set: { if !$0 { txvm.successMessage = nil } }
                )
            ) {
                Button("OK") { txvm.successMessage = nil }
            } message: {
                Text(txvm.successMessage ?? "")
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(TransactionsViewModel.TransactionFilter.allCases), id: \.self) { filter in
                    FilterPill(
                        title: filter.rawValue,
                        isSelected: txvm.selectedFilter == filter,
                        action: { txvm.selectedFilter = filter }
                    )
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
        }
    }

    // content now rendered inside List

    private func toItem(_ m: TransactionModel) -> TransactionItem {
        // Fiat mapping can be added with live price
        return TransactionItem(
            id: m.id,
            type: m.type == .sent ? .sent : .received,
            amount: m.amount,
            fiatAmount: 0,
            address: m.address,
            date: m.date,
            status: m.status,
            confirmations: m.confirmations,
            fee: m.fee
        )
    }
}

private extension TransactionsView {
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

struct FilterPill: View {
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

struct TransactionItem: Identifiable {
    let id: String
    let type: TransactionType
    let amount: Double
    let fiatAmount: Double
    let address: String
    let date: Date
    let status: TransactionStatus
    let confirmations: Int
    let fee: Double
    
    enum TransactionType {
        case sent, received
    }
}

struct TransactionListItem: View {
    let transaction: TransactionItem
    @State private var showDetails = false
    
    var body: some View {
        Button(action: { showDetails = true }) {
            HStack {
                // Icon
                Circle()
                    .fill(transaction.type == .received ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: transaction.type == .received ? "arrow.down" : "arrow.up")
                            .foregroundColor(transaction.type == .received ? .green : .red)
                    )
                
                // Details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(transaction.type == .received ? "Received" : "Sent")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if transaction.status == .pending {
                            Image(systemName: "clock.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text(formatAddress(transaction.address))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Text(formatDate(transaction.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        confirmationsBadge
                    }
                }
                
                Spacer()
                
                // Amount
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(transaction.type == .received ? "+" : "-")\(transaction.amount, specifier: "%.8f") BTC")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("$\(transaction.fiatAmount, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetails) {
            TransactionDetailView(transaction: transaction)
        }
    }
    
    private func formatAddress(_ address: String) -> String {
        String(address.prefix(10)) + "..." + String(address.suffix(6))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private var confirmationsBadge: some View {
        let conf = transaction.confirmations
        let shown = min(conf, 6)
        let text = "\(shown)/6"
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

struct TransactionDetailView: View {
    let transaction: TransactionItem
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Circle()
                            .fill(transaction.type == .received ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: transaction.type == .received ? "arrow.down" : "arrow.up")
                                    .font(.largeTitle)
                                    .foregroundColor(transaction.type == .received ? .green : .red)
                            )
                        
                        Text("\(transaction.type == .received ? "+" : "-")\(String(format: "%.8f", transaction.amount)) BTC")
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                        
                        Text("$\(String(format: "%.2f", transaction.fiatAmount)) USD")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        StatusBadge(status: transaction.status, confirmations: transaction.confirmations)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Details
                    VStack(alignment: .leading, spacing: 20) {
                        DetailRow(label: "Type", value: transaction.type == .received ? "Received" : "Sent")
                        DetailRow(label: "Date", value: formatFullDate(transaction.date))
                        DetailRow(label: "Address", value: transaction.address, copyable: true)
                        DetailRow(label: "Transaction ID", value: transaction.id, copyable: true)
                        DetailRow(label: "Network Fee", value: String(format: "%.8f BTC", transaction.fee))
                        if transaction.status == .confirmed {
                            DetailRow(label: "Confirmations", value: "\(transaction.confirmations)")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Actions
                    VStack(spacing: 12) {
                        Button(action: {}) {
                            Label("View on Blockchain Explorer", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        if transaction.status == .pending && transaction.type == .sent {
                            Button(action: {}) {
                                Label("Speed Up Transaction", systemImage: "hare")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Transaction Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct StatusBadge: View {
    let status: TransactionStatus
    let confirmations: Int
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
            Text(statusText)
        }
        .font(.subheadline)
        .fontWeight(.semibold)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .foregroundColor(statusColor)
        .cornerRadius(8)
    }
    
    private var statusIcon: String {
        switch status {
        case .pending: return "clock.fill"
        case .confirmed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var statusText: String {
        switch status {
        case .pending: return "Pending"
        case .confirmed: return confirmations >= 6 ? "Confirmed" : "\(confirmations)/6 Confirmations"
        case .failed: return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .confirmed: return .green
        case .failed: return .red
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var copyable: Bool = false
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text(value)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if copyable {
                    Button(action: {
                        UIPasteboard.general.string = value
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
        }
    }
}

#Preview {
    TransactionsView()
}
