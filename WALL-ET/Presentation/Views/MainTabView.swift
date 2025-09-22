import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        NavigationStack(path: navigationPathBinding) {
            TabView(selection: tabSelectionBinding) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(AppCoordinator.Tab.home.rawValue)

                TransactionsView()
                    .tabItem {
                        Label("Transactions", systemImage: "arrow.left.arrow.right")
                    }
                    .tag(AppCoordinator.Tab.transactions.rawValue)

                SendReceiveView()
                    .tabItem {
                        Label("Send/Receive", systemImage: "qrcode")
                    }
                    .tag(AppCoordinator.Tab.sendReceive.rawValue)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(AppCoordinator.Tab.settings.rawValue)
            }
            .tint(.orange)
        }
        .navigationDestination(for: AppCoordinator.Destination.self) { destination in
            destinationView(for: destination)
        }
        .sheet(item: $coordinator.sheet, content: sheetContent)
        .fullScreenCover(item: $coordinator.fullScreenCover, content: fullScreenContent)
        .alert(item: $coordinator.alert, content: alertContent)
        .onAppear {
            coordinator.restoreState()
        }
    }

    private var tabSelectionBinding: Binding<Int> {
        Binding(
            get: { coordinator.selectedTab.rawValue },
            set: { rawValue in
                guard let tab = AppCoordinator.Tab(rawValue: rawValue) else { return }
                coordinator.selectTab(tab)
                coordinator.saveState()
            }
        )
    }

    private var navigationPathBinding: Binding<NavigationPath> {
        Binding(
            get: { coordinator.navigationPath },
            set: { newValue in
                coordinator.navigationPath = newValue
            }
        )
    }

    @ViewBuilder
    private func destinationView(for destination: AppCoordinator.Destination) -> some View {
        switch destination {
        case .walletDetail(let id):
            WalletDetailView(walletId: id)
        case .transactionDetail(let id):
            if let transaction = coordinator.selectedTransaction, transaction.id == id {
                TransactionDetailView(transaction: transaction.asTransactionItem())
            } else {
                TransactionDetailFallbackView(transactionId: id)
            }
        case .addressBook:
            AddressBookView()
        case .importWallet:
            ImportWalletView()
        case .createWallet:
            CreateWalletView()
        case .backup:
            BackupView()
        case .security:
            ChangePasswordView()
        case .about:
            AboutView()
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: AppCoordinator.Sheet) -> some View {
        switch sheet {
        case .send:
            SendView()
        case .receive:
            ReceiveView()
        case .scanQR:
            QRScannerView(
                isPresented: Binding(
                    get: {
                        if case .scanQR? = coordinator.sheet { return true }
                        return false
                    },
                    set: { isPresented in
                        if !isPresented {
                            coordinator.dismissSheet()
                        }
                    }
                ),
                onScan: { scanned in
                    coordinator.dismissSheet()
                    NotificationCenter.default.post(
                        name: .bitcoinURIReceived,
                        object: nil,
                        userInfo: ["uri": scanned]
                    )
                    DispatchQueue.main.async {
                        coordinator.showSend()
                    }
                }
            )
        case .createWallet:
            CreateWalletView()
        case .importWallet:
            ImportWalletView()
        case .transactionDetail(let id):
            if let transaction = coordinator.selectedTransaction, transaction.id == id {
                TransactionDetailView(transaction: transaction.asTransactionItem())
            } else {
                TransactionDetailFallbackView(transactionId: id)
            }
        case .walletSettings(let id):
            if let wallet = coordinator.selectedWallet, wallet.id.uuidString == id {
                WalletDetailView(walletId: wallet.id.uuidString)
            } else {
                WalletDetailView(walletId: id)
            }
        case .share(let path):
            SharePresenterView(path: path)
        }
    }

    @ViewBuilder
    private func fullScreenContent(for cover: AppCoordinator.FullScreenCover) -> some View {
        switch cover {
        case .onboarding:
            OnboardingView()
        case .backup:
            BackupFlowView()
        case .authentication:
            UnlockView(
                isLocked: Binding(
                    get: { !coordinator.isAuthenticated },
                    set: { isLocked in
                        coordinator.isAuthenticated = !isLocked
                        if !isLocked {
                            coordinator.dismissFullScreenCover()
                        }
                    }
                )
            )
        }
    }

    private func alertContent(for alert: AppCoordinator.AlertItem) -> Alert {
        if let secondary = alert.secondaryButton {
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text(alert.primaryButton), action: alert.primaryAction),
                secondaryButton: .cancel(Text(secondary), action: alert.secondaryAction)
            )
        } else {
            return Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(alert.primaryButton), action: alert.primaryAction)
            )
        }
    }
}

private extension TransactionModel {
    func asTransactionItem() -> TransactionItem {
        TransactionItem(
            id: id,
            type: type == .sent ? .sent : .received,
            amount: amount,
            fiatAmount: amount, // Placeholder until fiat conversion is wired
            address: address,
            date: date,
            status: status,
            confirmations: confirmations,
            fee: fee
        )
    }
}

private struct TransactionDetailFallbackView: View {
    let transactionId: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading transaction \(transactionId)…")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

private struct SharePresenterView: View {
    let path: String

    var body: some View {
        let items = shareItems(from: path)
        return SendReceiveShareSheet(activityItems: items)
    }

    private func shareItems(from path: String) -> [Any] {
        if let url = URL(string: path), url.scheme != nil {
            return [url]
        }
        let fileURL = URL(fileURLWithPath: path)
        return [fileURL]
    }
}

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                Text("WALL-ET")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Secure Bitcoin wallet for iOS, featuring Electrum integration and modern UX.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
        }
        .navigationTitle("About")
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppCoordinator())
}