import Foundation
import Combine

class WatchOnlyWalletService {
    
    static let shared = WatchOnlyWalletService()
    private let bitcoinService = BitcoinService.shared
    private let electrumService = ElectrumService.shared
    private let walletRepository = WalletRepository()
    private let settingsRepository = SettingsRepository()
    
    private var watchedAddresses: Set<String> = []
    private var addressLabels: [String: String] = [:]
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var watchOnlyWallets: [WatchOnlyWallet] = []
    @Published var totalBalance: Int64 = 0
    @Published var portfolioValue: Double = 0
    
    // MARK: - Watch-Only Wallet Model
    
    struct WatchOnlyWallet {
        let id: UUID
        let name: String
        let type: WalletType
        let addresses: [WatchedAddress]
        let totalBalance: Int64
        let lastUpdated: Date
        let metadata: WalletMetadata?
        
        enum WalletType {
            case singleAddress
            case multiAddress
            case xpub
            case descriptor
        }
        
        struct WalletMetadata {
            let label: String?
            let color: String?
            let icon: String?
            let notes: String?
            let tags: [String]
        }
    }
    
    struct WatchedAddress {
        let address: String
        let label: String?
        let balance: Int64
        let unconfirmedBalance: Int64
        let transactionCount: Int
        let lastActivity: Date?
        let type: AddressType
        
        enum AddressType {
            case p2pkh   // Legacy
            case p2sh    // Wrapped SegWit
            case p2wpkh  // Native SegWit
            case p2wsh   // Native SegWit Script
            case p2tr    // Taproot
            case unknown
            
            init(from address: String) {
                if address.starts(with: "1") {
                    self = .p2pkh
                } else if address.starts(with: "3") || address.starts(with: "2") {
                    self = .p2sh
                } else if address.starts(with: "bc1q") || address.starts(with: "tb1q") {
                    self = .p2wpkh
                } else if address.starts(with: "bc1p") || address.starts(with: "tb1p") {
                    self = .p2tr
                } else {
                    self = .unknown
                }
            }
        }
    }
    
    // MARK: - Add Watch-Only Wallet
    
    func addWatchOnlyAddress(
        _ address: String,
        label: String? = nil
    ) throws -> WatchOnlyWallet {
        // Validate address
        guard bitcoinService.validateAddress(address) else {
            throw WatchOnlyError.invalidAddress
        }
        
        // Check if already watching
        guard !watchedAddresses.contains(address) else {
            throw WatchOnlyError.alreadyWatching
        }
        
        // Add to watched set
        watchedAddresses.insert(address)
        if let label = label {
            addressLabels[address] = label
        }
        
        // Subscribe to address updates
        electrumService.subscribeToAddress(address)
        
        // Create wallet
        let watchedAddress = WatchedAddress(
            address: address,
            label: label,
            balance: 0,
            unconfirmedBalance: 0,
            transactionCount: 0,
            lastActivity: nil,
            type: WatchedAddress.AddressType(from: address)
        )
        
        let wallet = WatchOnlyWallet(
            id: UUID(),
            name: label ?? "Watch-Only",
            type: .singleAddress,
            addresses: [watchedAddress],
            totalBalance: 0,
            lastUpdated: Date(),
            metadata: nil
        )
        
        // Save to repository
        saveWatchOnlyWallet(wallet)
        
        // Update balance
        Task {
            await updateWalletBalance(wallet)
        }
        
        return wallet
    }
    
    func addWatchOnlyXPub(
        _ xpub: String,
        name: String,
        gapLimit: Int = 20
    ) throws -> WatchOnlyWallet {
        // Validate xpub
        guard xpub.starts(with: "xpub") || xpub.starts(with: "tpub") else {
            throw WatchOnlyError.invalidXPub
        }
        
        // Derive addresses from xpub
        var addresses: [WatchedAddress] = []
        
        for i in 0..<gapLimit {
            // External addresses (m/0/i)
            if let address = deriveAddress(from: xpub, path: "0/\(i)") {
                let watchedAddress = WatchedAddress(
                    address: address,
                    label: "Address \(i)",
                    balance: 0,
                    unconfirmedBalance: 0,
                    transactionCount: 0,
                    lastActivity: nil,
                    type: WatchedAddress.AddressType(from: address)
                )
                addresses.append(watchedAddress)
                watchedAddresses.insert(address)
                electrumService.subscribeToAddress(address)
            }
            
            // Change addresses (m/1/i)
            if let changeAddress = deriveAddress(from: xpub, path: "1/\(i)") {
                let watchedAddress = WatchedAddress(
                    address: changeAddress,
                    label: "Change \(i)",
                    balance: 0,
                    unconfirmedBalance: 0,
                    transactionCount: 0,
                    lastActivity: nil,
                    type: WatchedAddress.AddressType(from: changeAddress)
                )
                addresses.append(watchedAddress)
                watchedAddresses.insert(changeAddress)
                electrumService.subscribeToAddress(changeAddress)
            }
        }
        
        let wallet = WatchOnlyWallet(
            id: UUID(),
            name: name,
            type: .xpub,
            addresses: addresses,
            totalBalance: 0,
            lastUpdated: Date(),
            metadata: WatchOnlyWallet.WalletMetadata(
                label: name,
                color: "blue",
                icon: "eye",
                notes: "Extended public key wallet",
                tags: ["xpub", "watch-only"]
            )
        )
        
        saveWatchOnlyWallet(wallet)
        
        // Update all balances
        Task {
            await updateWalletBalance(wallet)
        }
        
        return wallet
    }
    
    // MARK: - Balance Updates
    
    func updateAllWalletBalances() async {
        for wallet in watchOnlyWallets {
            await updateWalletBalance(wallet)
        }
        
        // Calculate total portfolio
        totalBalance = watchOnlyWallets.reduce(0) { $0 + $1.totalBalance }
        
        // Convert to fiat
        if let priceData = await PriceDataService.shared.fetchCurrentPrice() {
            portfolioValue = Double(totalBalance) / 100_000_000 * priceData.price
        }
    }
    
    private func updateWalletBalance(_ wallet: WatchOnlyWallet) async {
        var updatedAddresses: [WatchedAddress] = []
        var totalBalance: Int64 = 0
        
        for address in wallet.addresses {
            let balance = await fetchAddressBalance(address.address)
            let history = await fetchAddressHistory(address.address)
            
            let updatedAddress = WatchedAddress(
                address: address.address,
                label: address.label,
                balance: balance.confirmed,
                unconfirmedBalance: balance.unconfirmed,
                transactionCount: history.count,
                lastActivity: history.first?.date,
                type: address.type
            )
            
            updatedAddresses.append(updatedAddress)
            totalBalance += balance.confirmed + balance.unconfirmed
        }
        
        // Update wallet
        if let index = watchOnlyWallets.firstIndex(where: { $0.id == wallet.id }) {
            watchOnlyWallets[index] = WatchOnlyWallet(
                id: wallet.id,
                name: wallet.name,
                type: wallet.type,
                addresses: updatedAddresses,
                totalBalance: totalBalance,
                lastUpdated: Date(),
                metadata: wallet.metadata
            )
        }
    }
    
    private func fetchAddressBalance(_ address: String) async -> (confirmed: Int64, unconfirmed: Int64) {
        return await withCheckedContinuation { continuation in
            electrumService.getBalance(for: address) { result in
                switch result {
                case .success(let balance):
                    continuation.resume(returning: (balance.confirmed, balance.unconfirmed))
                case .failure:
                    continuation.resume(returning: (0, 0))
                }
            }
        }
    }
    
    private func fetchAddressHistory(_ address: String) async -> [(txid: String, date: Date)] {
        return await withCheckedContinuation { continuation in
            electrumService.getAddressHistory(for: address) { result in
                switch result {
                case .success(let history):
                    let transactions = history.compactMap { item -> (String, Date)? in
                        guard let txid = item["tx_hash"] as? String else { return nil }
                        return (txid, Date())
                    }
                    continuation.resume(returning: transactions)
                case .failure:
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // MARK: - Cold Storage Monitoring
    
    func monitorColdStorage(
        addresses: [String],
        name: String,
        alertThreshold: Int64? = nil
    ) throws -> WatchOnlyWallet {
        let watchedAddresses = addresses.compactMap { address -> WatchedAddress? in
            guard bitcoinService.validateAddress(address) else { return nil }
            
            return WatchedAddress(
                address: address,
                label: "Cold Storage",
                balance: 0,
                unconfirmedBalance: 0,
                transactionCount: 0,
                lastActivity: nil,
                type: WatchedAddress.AddressType(from: address)
            )
        }
        
        guard !watchedAddresses.isEmpty else {
            throw WatchOnlyError.invalidAddress
        }
        
        let wallet = WatchOnlyWallet(
            id: UUID(),
            name: name,
            type: .multiAddress,
            addresses: watchedAddresses,
            totalBalance: 0,
            lastUpdated: Date(),
            metadata: WatchOnlyWallet.WalletMetadata(
                label: name,
                color: "purple",
                icon: "snow",
                notes: "Cold storage monitoring",
                tags: ["cold-storage", "watch-only"]
            )
        )
        
        // Set up alerts if threshold provided
        if let threshold = alertThreshold {
            setupColdStorageAlert(walletId: wallet.id, threshold: threshold)
        }
        
        saveWatchOnlyWallet(wallet)
        
        // Subscribe to all addresses
        for address in addresses {
            self.watchedAddresses.insert(address)
            electrumService.subscribeToAddress(address)
        }
        
        return wallet
    }
    
    private func setupColdStorageAlert(walletId: UUID, threshold: Int64) {
        // Monitor for unexpected transactions
        ElectrumService.shared.transactionUpdatePublisher
            .sink { [weak self] update in
                self?.checkColdStorageAlert(walletId: walletId, threshold: threshold)
            }
            .store(in: &cancellables)
    }
    
    private func checkColdStorageAlert(walletId: UUID, threshold: Int64) {
        guard let wallet = watchOnlyWallets.first(where: { $0.id == walletId }) else { return }
        
        if wallet.totalBalance < threshold {
            // Send alert notification
            NotificationService.shared.sendTransactionNotification(
                title: "Cold Storage Alert",
                body: "Balance has dropped below threshold",
                txid: "",
                type: .pending
            )
        }
    }
    
    // MARK: - Portfolio Tracking
    
    func getPortfolioSummary() -> PortfolioSummary {
        let totalBTC = Double(totalBalance) / 100_000_000
        
        let walletBreakdown = watchOnlyWallets.map { wallet in
            PortfolioWallet(
                name: wallet.name,
                balance: wallet.totalBalance,
                percentage: Double(wallet.totalBalance) / Double(max(totalBalance, 1)) * 100,
                addressCount: wallet.addresses.count,
                lastActivity: wallet.addresses.compactMap { $0.lastActivity }.max()
            )
        }
        
        return PortfolioSummary(
            totalBalance: totalBalance,
            totalBTC: totalBTC,
            totalValue: portfolioValue,
            walletCount: watchOnlyWallets.count,
            addressCount: watchedAddresses.count,
            wallets: walletBreakdown
        )
    }
    
    struct PortfolioSummary {
        let totalBalance: Int64
        let totalBTC: Double
        let totalValue: Double
        let walletCount: Int
        let addressCount: Int
        let wallets: [PortfolioWallet]
    }
    
    struct PortfolioWallet {
        let name: String
        let balance: Int64
        let percentage: Double
        let addressCount: Int
        let lastActivity: Date?
    }
    
    // MARK: - Persistence
    
    private func saveWatchOnlyWallet(_ wallet: WatchOnlyWallet) {
        watchOnlyWallets.append(wallet)
        
        // Save to Core Data
        let walletEntity = walletRepository.createWallet(
            name: wallet.name,
            type: "watch-only",
            derivationPath: nil,
            network: "mainnet"
        )
        
        // Save addresses
        for (index, address) in wallet.addresses.enumerated() {
            _ = walletRepository.addAddress(
                to: walletEntity,
                address: address.address,
                type: "watch-only",
                index: Int32(index),
                isChange: false
            )
        }
    }
    
    private func deriveAddress(from xpub: String, path: String) -> String? {
        // Simplified - would use actual derivation
        return "bc1q" + UUID().uuidString.prefix(39)
    }
    
    // MARK: - Error Types
    
    enum WatchOnlyError: LocalizedError {
        case invalidAddress
        case invalidXPub
        case alreadyWatching
        case derivationFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidAddress:
                return "Invalid Bitcoin address"
            case .invalidXPub:
                return "Invalid extended public key"
            case .alreadyWatching:
                return "Already watching this address"
            case .derivationFailed:
                return "Failed to derive addresses"
            }
        }
    }
}