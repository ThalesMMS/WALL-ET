import SwiftUI
import Combine

@MainActor
class AppCoordinator: ObservableObject {
    // MARK: - Navigation State
    @Published var selectedTab: Tab = .home
    @Published var navigationPath = NavigationPath()
    @Published var sheet: Sheet?
    @Published var fullScreenCover: FullScreenCover?
    @Published var alert: AlertItem?
    
    // MARK: - Data State
    @Published var selectedWallet: WalletModel?
    @Published var selectedTransaction: TransactionModel?
    @Published var isAuthenticated = true // Set to true by default (no auth screen)
    
    // MARK: - Services
    private let container = DIContainer.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Tab Definition
    enum Tab: Int, CaseIterable {
        case home = 0
        case transactions = 1
        case sendReceive = 2
        case settings = 3
        
        var title: String {
            switch self {
            case .home: return "Home"
            case .transactions: return "Transactions"
            case .sendReceive: return "Send/Receive"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .transactions: return "arrow.left.arrow.right"
            case .sendReceive: return "qrcode"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    // MARK: - Navigation Destinations
    enum Destination: Hashable {
        case walletDetail(String) // Using String ID for Hashable
        case transactionDetail(String) // Using String ID for Hashable
        case addressBook
        case importWallet
        case createWallet
        case backup
        case security
        case about
    }
    
    // MARK: - Sheet Types
    enum Sheet: Identifiable {
        case send
        case receive
        case scanQR
        case createWallet
        case importWallet
        case transactionDetail(String) // Using String ID
        case walletSettings(String) // Using String ID
        case share(String) // Using String for URL path
        
        var id: String {
            switch self {
            case .send: return "send"
            case .receive: return "receive"
            case .scanQR: return "scanQR"
            case .createWallet: return "createWallet"
            case .importWallet: return "importWallet"
            case .transactionDetail(let id): return "transactionDetail-\(id)"
            case .walletSettings(let id): return "walletSettings-\(id)"
            case .share(let path): return "share-\(path)"
            }
        }
    }
    
    // MARK: - Full Screen Cover Types
    enum FullScreenCover: Identifiable {
        case onboarding
        case backup(String) // Using String ID
        case authentication
        
        var id: String {
            switch self {
            case .onboarding: return "onboarding"
            case .backup(let id): return "backup-\(id)"
            case .authentication: return "authentication"
            }
        }
    }
    
    // MARK: - Alert Types
    struct AlertItem: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let primaryButton: String
        let primaryAction: () -> Void
        let secondaryButton: String?
        let secondaryAction: (() -> Void)?
    }
    
    // MARK: - Initialization
    init() {
        // Defaults
        UserDefaults.standard.register(defaults: [
            "useNewTxPipeline": true
        ])
        setupDependencies()
        setupNotificationObservers()
        checkForOnboarding()
        // Apply saved Electrum settings and reconnect early (respects SSL off/on and network)
        ElectrumService.shared.applySavedSettingsAndReconnect()
    }
    
    // MARK: - Dependency Injection Setup
    private func setupDependencies() {
        // Register services
        container.register(KeychainServiceProtocol.self) {
            KeychainService()
        }
        
        container.register(WalletServiceProtocol.self) { WalletService() }
        container.register(TransactionServiceProtocol.self) { TransactionService() }
        container.register(PriceServiceProtocol.self) { PriceService() }
        container.register(FeeServiceProtocol.self) { FeeService() }
        // Register repositories (real implementation)
        container.register(WalletRepositoryProtocol.self) {
            DefaultWalletRepository(keychainService: self.container.resolve(KeychainServiceProtocol.self)!)
        }
        
        // Register use cases
        container.register(CreateWalletUseCaseProtocol.self) {
            CreateWalletUseCase(
                walletRepository: self.container.resolve(WalletRepositoryProtocol.self)!,
                keychainService: self.container.resolve(KeychainServiceProtocol.self)!
            )
        }
        
        container.register(SendBitcoinUseCaseProtocol.self) {
            SendBitcoinUseCase(
                walletRepository: self.container.resolve(WalletRepositoryProtocol.self)!,
                transactionService: self.container.resolve(TransactionServiceProtocol.self)!,
                feeService: self.container.resolve(FeeServiceProtocol.self)!
            )
        }
    }
    
    // MARK: - Setup
    private func setupNotificationObservers() {
        // Navigation notifications
        NotificationCenter.default.publisher(for: .navigateToWallet)
            .compactMap { $0.userInfo?["wallet"] as? WalletModel }
            .sink { [weak self] wallet in
                self?.navigateToWallet(wallet)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .navigateToSend)
            .sink { [weak self] _ in
                self?.showSend()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .navigateToReceive)
            .sink { [weak self] _ in
                self?.showReceive()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .transactionSent)
            .sink { [weak self] notification in
                self?.handleTransactionSent(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .shareFile)
            .compactMap { $0.userInfo?["url"] as? URL }
            .sink { [weak self] url in
                self?.shareFile(url)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Onboarding
    private func checkForOnboarding() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !hasCompletedOnboarding {
            showOnboarding()
        }
    }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        dismissFullScreenCover()
    }
    
    // MARK: - Tab Navigation
    func selectTab(_ tab: Tab) {
        selectedTab = tab
    }
    
    // MARK: - Push Navigation
    func navigate(to destination: Destination) {
        navigationPath.append(destination)
    }
    
    func navigateToWallet(_ wallet: WalletModel) {
        selectedWallet = wallet
        navigate(to: .walletDetail(wallet.id.uuidString))
    }
    
    func navigateToTransaction(_ transaction: TransactionModel) {
        selectedTransaction = transaction
        navigate(to: .transactionDetail(transaction.id))
    }
    
    func popToRoot() {
        navigationPath = NavigationPath()
    }
    
    func pop() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    // MARK: - Sheet Presentation
    func showSend() {
        sheet = .send
    }
    
    func showReceive() {
        sheet = .receive
    }
    
    func showScanQR() {
        sheet = .scanQR
    }
    
    func showCreateWallet() {
        sheet = .createWallet
    }
    
    func showImportWallet() {
        sheet = .importWallet
    }
    
    func showTransactionDetail(_ transaction: TransactionModel) {
        sheet = .transactionDetail(transaction.id)
    }
    
    func showWalletSettings(_ wallet: WalletModel) {
        sheet = .walletSettings(wallet.id.uuidString)
    }
    
    func shareFile(_ url: URL) {
        sheet = .share(url.absoluteString)
    }
    
    func dismissSheet() {
        sheet = nil
    }
    
    // MARK: - Full Screen Cover Presentation
    func showOnboarding() {
        fullScreenCover = .onboarding
    }
    
    func showBackup(for wallet: WalletModel) {
        fullScreenCover = .backup(wallet.id.uuidString)
    }
    
    func dismissFullScreenCover() {
        fullScreenCover = nil
    }
    
    // MARK: - Alerts
    func showAlert(
        title: String,
        message: String,
        primaryButton: String = "OK",
        primaryAction: @escaping () -> Void = {},
        secondaryButton: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        alert = AlertItem(
            title: title,
            message: message,
            primaryButton: primaryButton,
            primaryAction: primaryAction,
            secondaryButton: secondaryButton,
            secondaryAction: secondaryAction
        )
    }
    
    func showError(_ error: Error) {
        showAlert(
            title: "Error",
            message: error.localizedDescription
        )
    }
    
    func showSuccess(_ message: String) {
        showAlert(
            title: "Success",
            message: message
        )
    }
    
    func dismissAlert() {
        alert = nil
    }
    
    // MARK: - Deep Linking
    func handleDeepLink(_ url: URL) {
        guard url.scheme == "wallet" || url.scheme == "bitcoin" else { return }
        
        if url.scheme == "bitcoin" {
            // Handle bitcoin: URI
            handleBitcoinURI(url)
            return
        }
        
        switch url.host {
        case "send":
            showSend()
        case "receive":
            showReceive()
        case "transaction":
            if let id = url.pathComponents.last {
                // Load and show transaction
                Task {
                    if let transaction = try? await TransactionService().fetchTransaction(by: id) {
                        showTransactionDetail(transaction)
                    }
                }
            }
        case "wallet":
            if let id = url.pathComponents.last,
               let uuid = UUID(uuidString: id) {
                Task {
                    if let wallet = try? await WalletService().getWalletDetails(uuid) {
                        navigateToWallet(wallet)
                    }
                }
            }
        default:
            break
        }
    }
    
    private func handleBitcoinURI(_ url: URL) {
        // Parse bitcoin: URI and open send view with pre-filled data
        showSend()
        
        // Post notification with URI data
        NotificationCenter.default.post(
            name: .bitcoinURIReceived,
            object: nil,
            userInfo: ["uri": url.absoluteString]
        )
    }
    
    // MARK: - Event Handlers
    private func handleTransactionSent(_ notification: Notification) {
        dismissSheet()
        showSuccess("Transaction sent successfully")
        
        // Navigate to transactions tab
        selectedTab = .transactions
    }
    
    // MARK: - State Restoration
    func saveState() {
        UserDefaults.standard.set(selectedTab.rawValue, forKey: "selectedTab")
    }
    
    func restoreState() {
        if let tabRawValue = UserDefaults.standard.object(forKey: "selectedTab") as? Int,
           let tab = Tab(rawValue: tabRawValue) {
            selectedTab = tab
        }
    }
    
    // MARK: - Service Resolution
    func resolve<T>(_ type: T.Type) -> T? {
        return container.resolve(type)
    }
}

// MARK: - Additional Notification Names
extension Notification.Name {
    static let bitcoinURIReceived = Notification.Name("bitcoinURIReceived")
}

// MARK: - Protocols are now defined in their respective files
