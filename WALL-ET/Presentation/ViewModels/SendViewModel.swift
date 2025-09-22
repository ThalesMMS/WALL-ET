import Foundation
import Combine
import UIKit

@MainActor
final class SendViewModel: ObservableObject {
    enum FeeOption: String, CaseIterable, Identifiable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
        case custom = "Custom"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .slow: return "~60 min"
            case .normal: return "~30 min"
            case .fast: return "~10 min"
            case .custom: return "Custom"
            }
        }

        var defaultSatPerByte: Int {
            switch self {
            case .slow: return 5
            case .normal: return 20
            case .fast: return 50
            case .custom: return 15
            }
        }
    }

    // MARK: - Published State
    @Published var recipientAddress = "" {
        didSet { validateAddress() }
    }
    @Published var btcAmount = "" {
        didSet { handleBTCAmountChange(oldValue: oldValue) }
    }
    @Published var fiatAmount = "" {
        didSet { handleFiatAmountChange(oldValue: oldValue) }
    }
    @Published var selectedFeeOption: FeeOption = .normal {
        didSet { Task { await recalculateEstimate() } }
    }
    @Published var customSatPerByte: Double = 15 {
        didSet { Task { await recalculateEstimate() } }
    }
    @Published var showScanner = false
    @Published var showConfirmation = false
    @Published var errorMessage: String?
    @Published var useMaxAmount = false
    @Published var memo = ""
    @Published private(set) var btcPrice: Double = 0
    @Published private(set) var availableBalance: Double = 0
    @Published private(set) var estVBytes: Int = 140
    @Published private(set) var isAddressValid = false
    @Published private(set) var isAmountValid = false
    @Published private(set) var isSending = false

    // MARK: - Services
    private let walletRepository: WalletRepositoryProtocol
    private let priceService: PriceServiceProtocol
    private let transactionService: TransactionService
    private let sendBitcoinUseCase: SendBitcoinUseCaseProtocol
    private var activeWallet: Wallet?
    private var didLoad = false
    private var isUpdatingAmounts = false
    private var isApplyingMaxAmount = false

    // MARK: - Initialization
    init(
        walletRepository: WalletRepositoryProtocol? = nil,
        priceService: PriceServiceProtocol? = nil,
        transactionService: TransactionService? = nil,
        sendBitcoinUseCase: SendBitcoinUseCaseProtocol? = nil,
        initialBalance: Double? = nil,
        initialPrice: Double? = nil,
        skipInitialLoad: Bool = false
    ) {
        if let walletRepository {
            self.walletRepository = walletRepository
        } else if let resolved: WalletRepositoryProtocol = DIContainer.shared.resolve(WalletRepositoryProtocol.self) {
            self.walletRepository = resolved
        } else {
            fatalError("WalletRepositoryProtocol dependency missing")
        }

        if let priceService {
            self.priceService = priceService
        } else if let resolved: PriceServiceProtocol = DIContainer.shared.resolve(PriceServiceProtocol.self) {
            self.priceService = resolved
        } else {
            self.priceService = PriceService()
        }

        if let transactionService {
            self.transactionService = transactionService
        } else if let resolved: TransactionServiceProtocol = DIContainer.shared.resolve(TransactionServiceProtocol.self) as? TransactionService {
            self.transactionService = resolved
        } else {
            self.transactionService = TransactionService()
        }

        if let sendBitcoinUseCase {
            self.sendBitcoinUseCase = sendBitcoinUseCase
        } else if let resolved: SendBitcoinUseCaseProtocol = DIContainer.shared.resolve(SendBitcoinUseCaseProtocol.self) {
            self.sendBitcoinUseCase = resolved
        } else {
            fatalError("SendBitcoinUseCaseProtocol dependency missing")
        }

        if let initialBalance {
            availableBalance = initialBalance
        }

        if let initialPrice {
            btcPrice = initialPrice
        }

        if skipInitialLoad {
            didLoad = true
        }
    }

    // MARK: - Public API
    func handleAppear() async {
        guard !didLoad else { return }
        didLoad = true
        await loadInitialData()
    }

    func pasteAddressFromClipboard() {
        if let pasteString = UIPasteboard.general.string {
            recipientAddress = pasteString
        }
    }

    func handleScannedCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { showScanner = false }

        guard !trimmed.isEmpty else {
            errorMessage = NSLocalizedString("Scanned code is empty.", comment: "")
            return
        }

        errorMessage = nil

        if let uri = parseBitcoinURI(from: trimmed) {
            applyScannedBitcoinURI(uri)
            return
        }

        if isLikelyBitcoinAddress(trimmed) {
            recipientAddress = trimmed
            useMaxAmount = false
            return
        }

        errorMessage = NSLocalizedString("Unsupported QR code content.", comment: "")
    }

    func toggleMaxAmount() {
        if useMaxAmount {
            useMaxAmount = false
            return
        }

        isApplyingMaxAmount = true
        useMaxAmount = true
        let feeBTC = estimatedFeeBTC
        let maxAmount = max(0, availableBalance - feeBTC)
        btcAmount = String(format: "%.8f", maxAmount)
        fiatAmount = String(format: "%.2f", maxAmount * btcPrice)
        isApplyingMaxAmount = false
    }

    func selectFeeOption(_ option: FeeOption) {
        selectedFeeOption = option
    }

    func updateCustomFeeRate(_ value: Double) {
        customSatPerByte = value
    }

    func prepareReview() async {
        await recalculateEstimate()
        showConfirmation = true
    }

    func confirmationDetails() -> TransactionConfirmationDetails {
        TransactionConfirmationDetails(
            recipientAddress: recipientAddress,
            btcAmount: btcAmountDouble,
            fiatAmount: fiatAmountDouble,
            feeRateSatPerVb: effectiveSatPerByte,
            estimatedVBytes: estVBytes
        )
    }

    func confirmTransaction() async {
        guard !isSending else { return }

        isSending = true
        errorMessage = nil

        defer { isSending = false }

        do {
            let wallet = try await resolveActiveWallet()
            let amountBTC = btcAmountDouble

            guard amountBTC > 0 else {
                errorMessage = NSLocalizedString("Enter a valid amount before sending.", comment: "")
                return
            }

            let memoText = memo.trimmingCharacters(in: .whitespacesAndNewlines)
            let request = SendTransactionRequest(
                fromWallet: wallet,
                toAddress: recipientAddress,
                amount: amountBTC.bitcoinToSatoshis(),
                feeRate: effectiveSatPerByte,
                memo: memoText.isEmpty ? nil : memoText
            )

            _ = try await sendBitcoinUseCase.execute(request: request)
            NotificationCenter.default.post(name: .transactionSent, object: nil)
            showConfirmation = false
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                errorMessage = description
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissConfirmation() {
        showConfirmation = false
    }

    var isReviewEnabled: Bool {
        isAddressValid && isAmountValid
    }

    var btcAmountDouble: Double {
        Double(btcAmount) ?? 0
    }

    var fiatAmountDouble: Double {
        Double(fiatAmount) ?? 0
    }

    var estimatedFeeBTC: Double {
        Double(estVBytes * effectiveSatPerByte) / 100_000_000.0
    }

    var estimatedFeeFiat: Double {
        estimatedFeeBTC * btcPrice
    }

    var effectiveSatPerByte: Int {
        selectedFeeOption == .custom ? Int(customSatPerByte) : selectedFeeOption.defaultSatPerByte
    }

    // MARK: - Private Helpers
    private func parseBitcoinURI(from string: String) -> QRCodeService.BitcoinURI? {
        if let uri = QRCodeService.shared.parseBitcoinURI(string) {
            return uri
        }

        let prefix = "bitcoin:"
        guard string.lowercased().hasPrefix(prefix), string.count > prefix.count else {
            return nil
        }

        let remainderIndex = string.index(string.startIndex, offsetBy: prefix.count)
        let remainder = string[remainderIndex...]
        let normalized = prefix + remainder
        return QRCodeService.shared.parseBitcoinURI(normalized)
    }

    private func applyScannedBitcoinURI(_ uri: QRCodeService.BitcoinURI) {
        guard !uri.address.isEmpty else {
            errorMessage = NSLocalizedString("Unsupported QR code content.", comment: "")
            return
        }

        recipientAddress = uri.address
        useMaxAmount = false

        if let amount = uri.amount {
            applyScannedAmount(amount)
        }
    }

    private func applyScannedAmount(_ amount: Double) {
        guard amount > 0 else {
            useMaxAmount = false
            btcAmount = ""
            fiatAmount = ""
            validateAmount()
            return
        }

        let formattedBTC = String(format: "%.8f", amount)
        let formattedFiat = String(format: "%.2f", amount * btcPrice)

        isUpdatingAmounts = true
        btcAmount = formattedBTC
        fiatAmount = formattedFiat
        isUpdatingAmounts = false
        useMaxAmount = false
        validateAmount()
        Task { await recalculateEstimate() }
    }

    private func isLikelyBitcoinAddress(_ string: String) -> Bool {
        let address = string.lowercased()
        let isBech32 = address.hasPrefix("bc1") || address.hasPrefix("tb1")
        let isP2SH = address.hasPrefix("3") || address.hasPrefix("2")
        let isLegacy = address.hasPrefix("1") || address.hasPrefix("m") || address.hasPrefix("n")
        return isBech32 || isP2SH || isLegacy
    }

    private func loadInitialData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadBalance() }
            group.addTask { await self.loadPrice() }
        }
        validateAmount()
        await recalculateEstimate()
    }

    private func loadBalance() async {
        do {
            if let wallet = try await walletRepository.getAllWallets().first,
               let address = wallet.accounts.first?.address {
                activeWallet = wallet
                let balance = try await walletRepository.getBalance(for: address)
                availableBalance = balance.btcValue
            } else {
                availableBalance = 0
            }
        } catch {
            availableBalance = 0
        }
    }

    private func loadPrice() async {
        do {
            btcPrice = try await priceService.fetchBTCPrice().price
        } catch {
            btcPrice = 0
        }
    }

    private func handleBTCAmountChange(oldValue: String) {
        if useMaxAmount && !isUpdatingAmounts && !isApplyingMaxAmount {
            useMaxAmount = false
        }

        guard !isUpdatingAmounts else { return }
        defer { isUpdatingAmounts = false }
        isUpdatingAmounts = true

        guard let btc = Double(btcAmount) else {
            fiatAmount = ""
            isAmountValid = false
            return
        }

        fiatAmount = String(format: "%.2f", btc * btcPrice)
        validateAmount()
        Task { await recalculateEstimate() }
    }

    private func handleFiatAmountChange(oldValue: String) {
        if useMaxAmount && !isUpdatingAmounts && !isApplyingMaxAmount {
            useMaxAmount = false
        }

        guard !isUpdatingAmounts else { return }
        defer { isUpdatingAmounts = false }
        isUpdatingAmounts = true

        guard let fiat = Double(fiatAmount), btcPrice > 0 else {
            btcAmount = ""
            isAmountValid = false
            return
        }

        let btc = fiat / btcPrice
        btcAmount = String(format: "%.8f", btc)
        validateAmount()
        Task { await recalculateEstimate() }
    }

    private func validateAddress() {
        guard !recipientAddress.isEmpty else {
            isAddressValid = false
            return
        }

        let address = recipientAddress.lowercased()
        let isBech32 = address.hasPrefix("bc1") || address.hasPrefix("tb1")
        let isP2SH = address.hasPrefix("3") || address.hasPrefix("2")
        let isLegacy = address.hasPrefix("1")
        let isLegacyTestnet = address.hasPrefix("m") || address.hasPrefix("n")
        isAddressValid = isBech32 || isP2SH || isLegacy || isLegacyTestnet
    }

    private func validateAmount() {
        guard let amount = Double(btcAmount), amount > 0 else {
            isAmountValid = false
            return
        }

        isAmountValid = amount + estimatedFeeBTC <= availableBalance || availableBalance == 0
    }

    private func recalculateEstimate() async {
        guard isAddressValid, let amount = Double(btcAmount), amount > 0 else {
            estVBytes = 140
            validateAmount()
            return
        }

        do {
            let estimate = try await transactionService.estimateFee(
                to: recipientAddress,
                amount: amount,
                feeRateSatPerVb: effectiveSatPerByte
            )
            estVBytes = estimate.vbytes
        } catch {
            estVBytes = 140
        }

        validateAmount()
    }

    private func resolveActiveWallet() async throws -> Wallet {
        if let activeWallet {
            return activeWallet
        }

        let wallets = try await walletRepository.getAllWallets()
        guard let wallet = wallets.first else {
            throw SendViewModelError.missingWallet
        }

        activeWallet = wallet
        return wallet
    }
}

private enum SendViewModelError: LocalizedError {
    case missingWallet

    var errorDescription: String? {
        switch self {
        case .missingWallet:
            return NSLocalizedString("Unable to find a wallet to send from.", comment: "")
        }
    }
}

struct TransactionConfirmationDetails {
    let recipientAddress: String
    let btcAmount: Double
    let fiatAmount: Double
    let feeRateSatPerVb: Int
    let estimatedVBytes: Int

    var estimatedFeeBTC: Double {
        Double(estimatedVBytes * feeRateSatPerVb) / 100_000_000.0
    }

    var totalBTC: Double {
        btcAmount + estimatedFeeBTC
    }
}
