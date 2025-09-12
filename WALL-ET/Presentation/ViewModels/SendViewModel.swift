import Foundation
import Combine
import AVFoundation

@MainActor
class SendViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var recipientAddress = ""
    @Published var btcAmount = ""
    @Published var fiatAmount = ""
    @Published var note = ""
    @Published var selectedFeeOption: FeeOption = .normal
    @Published var customFeeRate: String = ""
    @Published var useCustomFee = false
    @Published var useMaxAmount = false
    
    // MARK: - State
    @Published var isAddressValid = false
    @Published var isAmountValid = false
    @Published var estimatedFee: Double = 0
    @Published var totalAmount: Double = 0
    @Published var availableBalance: Double = 1.23456789
    @Published var currentBTCPrice: Double = 62000
    
    // MARK: - UI State
    @Published var showScanner = false
    @Published var showConfirmation = false
    @Published var showAddressBook = false
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    // MARK: - Services
    private let walletService: WalletServiceProtocol
    private let transactionService: TransactionServiceProtocol
    private let feeService: FeeServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    enum FeeOption: String, CaseIterable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
        case custom = "Custom"
        
        var description: String {
            switch self {
            case .slow: return "~60 min"
            case .normal: return "~30 min"
            case .fast: return "~10 min"
            case .custom: return "Custom"
            }
        }
    }
    
    struct FeeEstimate {
        let satPerByte: Int
        let totalFee: Double
        let estimatedTime: Int // in minutes
    }
    
    // MARK: - Initialization
    init(walletService: WalletServiceProtocol = WalletService(),
         transactionService: TransactionServiceProtocol = TransactionService(),
         feeService: FeeServiceProtocol = FeeService()) {
        self.walletService = walletService
        self.transactionService = transactionService
        self.feeService = feeService
        
        setupBindings()
        loadInitialData()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Validate address
        $recipientAddress
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] address in
                self?.validateAddress(address)
            }
            .store(in: &cancellables)
        
        // BTC to Fiat conversion
        $btcAmount
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] btcAmount in
                self?.updateFiatAmount(from: btcAmount)
            }
            .store(in: &cancellables)
        
        // Fiat to BTC conversion
        $fiatAmount
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] fiatAmount in
                self?.updateBTCAmount(from: fiatAmount)
            }
            .store(in: &cancellables)
        
        // Fee estimation
        Publishers.CombineLatest3($btcAmount, $selectedFeeOption, $customFeeRate)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] amount, feeOption, customRate in
                Task {
                    await self?.estimateFee()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    private func loadInitialData() {
        Task {
            do {
                availableBalance = try await walletService.getAvailableBalance()
                currentBTCPrice = try await PriceService().fetchBTCPrice().price
            } catch {
                handleError(error)
            }
        }
    }
    
    // MARK: - Validation
    private func validateAddress(_ address: String) {
        guard !address.isEmpty else {
            isAddressValid = false
            return
        }
        
        // Basic Bitcoin address validation
        let isValidBech32 = address.hasPrefix("bc1") && address.count >= 42
        let isValidP2SH = address.hasPrefix("3") && address.count >= 26
        let isValidLegacy = address.hasPrefix("1") && address.count >= 26
        let isValidTestnet = address.hasPrefix("tb1") || address.hasPrefix("2")
        
        isAddressValid = isValidBech32 || isValidP2SH || isValidLegacy || isValidTestnet
    }
    
    private func validateAmount() {
        guard let amount = Double(btcAmount), amount > 0 else {
            isAmountValid = false
            return
        }
        
        let totalWithFee = amount + estimatedFee
        isAmountValid = totalWithFee <= availableBalance
        
        if !isAmountValid {
            errorMessage = "Insufficient balance"
        }
    }
    
    // MARK: - Amount Conversion
    private func updateFiatAmount(from btcAmount: String) {
        guard !btcAmount.isEmpty,
              let btc = Double(btcAmount) else {
            fiatAmount = ""
            return
        }
        
        let fiat = btc * currentBTCPrice
        fiatAmount = String(format: "%.2f", fiat)
        validateAmount()
    }
    
    private func updateBTCAmount(from fiatAmount: String) {
        guard !fiatAmount.isEmpty,
              let fiat = Double(fiatAmount) else {
            btcAmount = ""
            return
        }
        
        let btc = fiat / currentBTCPrice
        btcAmount = String(format: "%.8f", btc)
        validateAmount()
    }
    
    // MARK: - Fee Estimation
    private func estimateFee() async {
        guard let amount = Double(btcAmount), amount > 0 else {
            estimatedFee = 0
            return
        }
        
        do {
            let feeRate = getFeeRate()
            estimatedFee = try await feeService.estimateFee(
                amount: amount,
                feeRate: feeRate
            )
            
            totalAmount = amount + estimatedFee
        } catch {
            handleError(error)
        }
    }
    
    private func getFeeRate() -> Int {
        if useCustomFee, let customRate = Int(customFeeRate) {
            return customRate
        }
        
        switch selectedFeeOption {
        case .slow:
            return 5
        case .normal:
            return 20
        case .fast:
            return 50
        case .custom:
            return Int(customFeeRate) ?? 20
        }
    }
    
    // MARK: - Actions
    func setMaxAmount() {
        useMaxAmount = true
        let maxAmount = availableBalance - estimatedFee
        btcAmount = String(format: "%.8f", max(0, maxAmount))
        updateFiatAmount(from: btcAmount)
    }
    
    func scanQRCode() {
        checkCameraPermission { [weak self] granted in
            if granted {
                self?.showScanner = true
            } else {
                self?.errorMessage = "Camera permission required to scan QR codes"
                self?.showError = true
            }
        }
    }
    
    func pasteFromClipboard() {
        if let pasteString = UIPasteboard.general.string {
            // Parse Bitcoin URI if present
            if pasteString.hasPrefix("bitcoin:") {
                parseBitcoinURI(pasteString)
            } else {
                recipientAddress = pasteString
            }
        }
    }
    
    func selectFromAddressBook() {
        showAddressBook = true
    }
    
    func reviewTransaction() {
        guard isAddressValid && isAmountValid else {
            errorMessage = "Please enter a valid address and amount"
            showError = true
            return
        }
        
        showConfirmation = true
    }
    
    func confirmAndSend() {
        guard let amount = Double(btcAmount) else { return }
        
        isProcessing = true
        
        Task {
            do {
                let transaction = try await transactionService.sendBitcoin(
                    to: recipientAddress,
                    amount: amount,
                    fee: estimatedFee,
                    note: note
                )
                
                // Post success notification
                NotificationCenter.default.post(
                    name: .transactionSent,
                    object: nil,
                    userInfo: ["transaction": transaction]
                )
                
                // Reset form
                resetForm()
                
            } catch {
                handleError(error)
            }
            
            isProcessing = false
        }
    }
    
    // MARK: - Helper Methods
    private func parseBitcoinURI(_ uri: String) {
        guard let url = URL(string: uri),
              url.scheme == "bitcoin" else { return }
        
        recipientAddress = url.host ?? ""
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                switch item.name {
                case "amount":
                    btcAmount = item.value ?? ""
                case "message", "label":
                    note = item.value ?? ""
                default:
                    break
                }
            }
        }
    }
    
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    private func resetForm() {
        recipientAddress = ""
        btcAmount = ""
        fiatAmount = ""
        note = ""
        selectedFeeOption = .normal
        useMaxAmount = false
        showConfirmation = false
    }
    
    private func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let transactionSent = Notification.Name("transactionSent")
}