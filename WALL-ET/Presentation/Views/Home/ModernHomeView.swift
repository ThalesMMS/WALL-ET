import SwiftUI
import Charts

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

struct ModernHomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var viewModel: HomeViewModel

    init(viewModel: HomeViewModel = HomeViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: ModernTheme.Spacing.lg) {
                headerSection
                balanceCard
                priceChart
                quickActions
                recentTransactions
            }
            .padding()
        }
        .background(ModernTheme.Colors.background)
        .navigationBarHidden(true)
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Good \(timeOfDay)")
                    .font(ModernTheme.Typography.caption)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
                
                Text("Your Wallet")
                    .font(ModernTheme.Typography.title)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 22))
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                    .overlay(
                        Circle()
                            .fill(ModernTheme.Colors.error)
                            .frame(width: 10, height: 10)
                            .offset(x: 8, y: -8),
                        alignment: .topTrailing
                    )
            }
        }
    }
    
    private var balanceCard: some View {
        VStack(spacing: ModernTheme.Spacing.md) {
            HStack {
                Text("Total Balance")
                    .font(ModernTheme.Typography.subheadline)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
                
                Spacer()
                
                Button(action: { viewModel.toggleBalanceVisibility() }) {
                    Image(systemName: viewModel.showBalance ? "eye" : "eye.slash")
                        .font(.system(size: 16))
                        .foregroundColor(ModernTheme.Colors.textSecondary)
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.showBalance ? String(format: "$%.2f", viewModel.totalBalanceUSD) : "****")
                    .font(ModernTheme.Typography.balance)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Text("USD")
                    .font(ModernTheme.Typography.title3)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: ModernTheme.Spacing.md) {
                HStack(spacing: 4) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(ModernTheme.Colors.primary)
                    Text(viewModel.showBalance ? String(format: "%.8f", viewModel.totalBalanceBTC) : "****")
                        .font(ModernTheme.Typography.callout)
                        .foregroundColor(ModernTheme.Colors.textPrimary)
                    Text("BTC")
                        .font(ModernTheme.Typography.caption)
                        .foregroundColor(ModernTheme.Colors.textSecondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: viewModel.priceChange24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12))
                    Text("\(abs(viewModel.priceChange24h), specifier: "%.2f")%")
                        .font(ModernTheme.Typography.callout)
                }
                .foregroundColor(viewModel.priceChange24h >= 0 ? ModernTheme.Colors.positive : ModernTheme.Colors.negative)
            }
        }
        .padding(ModernTheme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [
                    ModernTheme.Colors.primary.opacity(0.1),
                    ModernTheme.Colors.primary.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .modernCard()
    }
    
    private var priceChart: some View {
        VStack(spacing: ModernTheme.Spacing.md) {
            HStack {
                Text("Price Chart")
                    .font(ModernTheme.Typography.headline)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    ForEach(HomeViewModel.PriceHistoryRange.allCases, id: \.self) { range in
                        Button(action: {
                            guard viewModel.selectedTimeRange != range else { return }
                            viewModel.selectedTimeRange = range
                            Task {
                                await viewModel.loadPriceHistory(for: range)
                            }
                        }) {
                            Text(range.rawValue)
                                .font(ModernTheme.Typography.caption)
                                .foregroundColor(
                                    viewModel.selectedTimeRange == range ?
                                        .white : ModernTheme.Colors.textSecondary
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    viewModel.selectedTimeRange == range ?
                                        ModernTheme.Colors.primary :
                                        Color.clear
                                )
                                .cornerRadius(ModernTheme.Radius.small)
                        }
                    }
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: ModernTheme.Radius.medium)
                    .fill(ModernTheme.Colors.secondaryBackground)

                if viewModel.chartData.isEmpty {
                    VStack(spacing: ModernTheme.Spacing.sm) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(ModernTheme.Colors.textTertiary)
                        Text("No price data available")
                            .font(ModernTheme.Typography.caption)
                            .foregroundColor(ModernTheme.Colors.textSecondary)
                    }
                } else {
                    Chart {
                        ForEach(viewModel.chartData, id: \.date) { point in
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Price", point.price)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        ModernTheme.Colors.primary.opacity(0.35),
                                        ModernTheme.Colors.primary.opacity(0.05)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Price", point.price)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(ModernTheme.Colors.primary)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                                .foregroundStyle(ModernTheme.Colors.textTertiary.opacity(0.15))
                            if let date = value.as(Date.self) {
                                AxisValueLabel {
                                    Text(formattedLabel(for: date))
                                        .font(ModernTheme.Typography.caption2)
                                        .foregroundColor(ModernTheme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                                .foregroundStyle(ModernTheme.Colors.textTertiary.opacity(0.15))
                            if let price = value.as(Double.self) {
                                AxisValueLabel {
                                    Text(formattedPriceLabel(for: price))
                                        .font(ModernTheme.Typography.caption2)
                                        .foregroundColor(ModernTheme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea
                            .background(ModernTheme.Colors.background.opacity(0.2))
                            .cornerRadius(ModernTheme.Radius.small)
                    }
                    .padding(.horizontal, ModernTheme.Spacing.md)
                    .padding(.vertical, ModernTheme.Spacing.sm)
                }
            }
            .frame(height: 220)
        }
        .padding(ModernTheme.Spacing.lg)
        .modernCard()
    }
    
    private var quickActions: some View {
        HStack(spacing: ModernTheme.Spacing.md) {
            HomeActionButton(
                icon: "arrow.down.circle.fill",
                title: "Receive",
                color: ModernTheme.Colors.success
            ) {
                coordinator.showReceive()
            }

            HomeActionButton(
                icon: "arrow.up.circle.fill",
                title: "Send",
                color: ModernTheme.Colors.info
            ) {
                coordinator.showSend()
            }

            // Removed Exchange (swap) per requirements

            HomeActionButton(
                icon: "qrcode",
                title: "Scan",
                color: ModernTheme.Colors.primary
            ) {
                coordinator.showScanQR()
            }
        }
    }
    
    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: ModernTheme.Spacing.md) {
            HStack {
                Text("Recent Transactions")
                    .font(ModernTheme.Typography.headline)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Spacer()
                
                NavigationLink(destination: TransactionsView()) {
                    Text("See All")
                        .font(ModernTheme.Typography.caption)
                        .foregroundColor(ModernTheme.Colors.primary)
                }
            }
            
            if viewModel.recentTransactions.isEmpty {
                EmptyTransactionView()
            } else {
                VStack(spacing: ModernTheme.Spacing.sm) {
                    ForEach(viewModel.recentTransactions.prefix(3)) { transaction in
                        ModernTransactionRow(transaction: transaction)
                    }
                }
            }
        }
        .padding(ModernTheme.Spacing.lg)
        .modernCard()
    }

    private func formattedLabel(for date: Date) -> String {
        switch viewModel.selectedTimeRange {
        case .day:
            return date.formatted(.dateTime.hour().minute())
        case .week, .month:
            return date.formatted(.dateTime.month(.abbreviated).day())
        case .year:
            return date.formatted(.dateTime.month(.abbreviated))
        case .all:
            return date.formatted(.dateTime.year().month(.abbreviated))
        }
    }

    private func formattedPriceLabel(for price: Double) -> String {
        String(format: "$%.0f", price)
    }

    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Morning"
        case 12..<17: return "Afternoon"
        default: return "Evening"
        }
    }
}

struct HomeActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(color.opacity(0.1))
                    )
                
                Text(title)
                    .font(ModernTheme.Typography.caption)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
            }
        }
    }
}

struct ModernTransactionRow: View {
    let transaction: TransactionModel
    
    var body: some View {
        HStack(spacing: ModernTheme.Spacing.md) {
            Image(systemName: transaction.type == .received ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(transaction.type == .received ? ModernTheme.Colors.success : ModernTheme.Colors.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(transaction.type == .received ?
                              ModernTheme.Colors.success.opacity(0.1) :
                              ModernTheme.Colors.secondaryBackground)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.type == .received ? "Received" : "Sent")
                    .font(ModernTheme.Typography.callout)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Text(transaction.date, formatter: DateFormatter.shortDate)
                    .font(ModernTheme.Typography.caption)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(transaction.type == .received ? "+" : "-")\(transaction.amount, specifier: "%.8f") BTC")
                    .font(ModernTheme.Typography.callout)
                    .foregroundColor(transaction.type == .received ? ModernTheme.Colors.success : ModernTheme.Colors.textPrimary)
                
                Text("\(transaction.confirmations) confirmations")
                    .font(ModernTheme.Typography.caption2)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
            }
        }
        .padding(.vertical, ModernTheme.Spacing.xs)
    }
}

struct EmptyTransactionView: View {
    var body: some View {
        VStack(spacing: ModernTheme.Spacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(ModernTheme.Colors.textTertiary)

            Text("No transactions yet")
                .font(ModernTheme.Typography.callout)
                .foregroundColor(ModernTheme.Colors.textSecondary)

            Text("Your transactions will appear here")
                .font(ModernTheme.Typography.caption)
                .foregroundColor(ModernTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ModernTheme.Spacing.xl)
    }
}

#Preview {
    let previewViewModel = HomeViewModel(shouldLoadOnInit: false)
    previewViewModel.totalBalanceUSD = 12345.67
    previewViewModel.totalBalanceBTC = 0.45678901
    previewViewModel.priceChange24h = 2.34
    previewViewModel.selectedTimeRange = .day
    previewViewModel.chartData = stride(from: 0, through: 12, by: 1).map { hour -> PricePoint in
        let date = Calendar.current.date(byAdding: .hour, value: -hour, to: Date()) ?? Date()
        let base = 62000.0
        let variation = Double(hour * hour) * -12 + Double(hour) * 140
        return PricePoint(date: date, price: base + variation)
    }.sorted { $0.date < $1.date }

    return ModernHomeView(viewModel: previewViewModel)
        .environmentObject(AppCoordinator())
}
