import SwiftUI

struct TransactionsView: View {
    @State private var searchText = ""
    @State private var filterType: TransactionFilter = .all
    @State private var selectedTransaction: TransactionItem?
    
    enum TransactionFilter: String, CaseIterable {
        case all = "All"
        case sent = "Sent"
        case received = "Received"
        case pending = "Pending"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(TransactionFilter.allCases, id: \.self) { filter in
                            FilterPill(
                                title: filter.rawValue,
                                isSelected: filterType == filter,
                                action: { filterType = filter }
                            )
                        }
                    }
                    .padding()
                }
                
                // Transactions List
                List {
                    // Group by date
                    Section {
                        TransactionListItem(
                            transaction: TransactionItem(
                                id: "1",
                                type: .received,
                                amount: 0.00234567,
                                fiatAmount: 145.67,
                                address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
                                date: Date(),
                                status: .confirmed,
                                confirmations: 6,
                                fee: 0.00001234
                            )
                        )
                        
                        TransactionListItem(
                            transaction: TransactionItem(
                                id: "2",
                                type: .sent,
                                amount: 0.00100000,
                                fiatAmount: 62.00,
                                address: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
                                date: Date().addingTimeInterval(-3600),
                                status: .pending,
                                confirmations: 0,
                                fee: 0.00000546
                            )
                        )
                    } header: {
                        Text("Today")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Section {
                        TransactionListItem(
                            transaction: TransactionItem(
                                id: "3",
                                type: .received,
                                amount: 0.05000000,
                                fiatAmount: 3100.00,
                                address: "bc1q7g8u9w5z3qw7zyxkjmnf6rc02uxzwqg8l5a5n5",
                                date: Date().addingTimeInterval(-86400),
                                status: .confirmed,
                                confirmations: 144,
                                fee: 0.00001000
                            )
                        )
                        
                        TransactionListItem(
                            transaction: TransactionItem(
                                id: "4",
                                type: .sent,
                                amount: 0.00500000,
                                fiatAmount: 310.00,
                                address: "bc1qm34lsc65zpw79lxkyj4u5qt5qm7z9thx0wqh",
                                date: Date().addingTimeInterval(-86400 * 2),
                                status: .confirmed,
                                confirmations: 288,
                                fee: 0.00000800
                            )
                        )
                    } header: {
                        Text("Yesterday")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    Section {
                        ForEach(0..<10) { index in
                            TransactionListItem(
                                transaction: TransactionItem(
                                    id: "older-\(index)",
                                    type: index % 2 == 0 ? .received : .sent,
                                    amount: Double.random(in: 0.001...0.1),
                                    fiatAmount: Double.random(in: 60...6000),
                                    address: "bc1q\(String(repeating: "x", count: 39))",
                                    date: Date().addingTimeInterval(-86400 * Double(index + 3)),
                                    status: .confirmed,
                                    confirmations: 1000 + index * 144,
                                    fee: 0.00000500
                                )
                            )
                        }
                    } header: {
                        Text("This Week")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .searchable(text: $searchText, prompt: "Search transactions")
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "arrow.down.doc")
                    }
                }
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
    
    enum TransactionStatus {
        case pending, confirmed, failed
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
                    
                    HStack {
                        Text(formatDate(transaction.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if transaction.status == .confirmed {
                            Text("• \(transaction.confirmations) confirmations")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
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
                        
                        Text("\(transaction.type == .received ? "+" : "-")\(transaction.amount, specifier: "%.8f") BTC")
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                        
                        Text("$\(transaction.fiatAmount, specifier: "%.2f") USD")
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
                        DetailRow(label: "Transaction ID", value: "f4184fc596403b9d638783cf57adfe4c75c605f6", copyable: true)
                        DetailRow(label: "Network Fee", value: "\(transaction.fee, specifier: "%.8f") BTC")
                        if transaction.status == .confirmed {
                            DetailRow(label: "Confirmations", value: "\(transaction.confirmations)")
                            DetailRow(label: "Block", value: "808,185")
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
    let status: TransactionItem.TransactionStatus
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