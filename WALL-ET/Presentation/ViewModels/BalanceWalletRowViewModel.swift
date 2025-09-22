import Foundation
import Combine

@MainActor
final class BalanceWalletRowViewModel: ObservableObject {
    @Published private(set) var fiatBalance: Double?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let wallet: Wallet
    let currencyCode: String

    private let priceService: PriceDataServiceType
    private var cancellables = Set<AnyCancellable>()

    var totalBalance: Double {
        wallet.accounts.reduce(0) { $0 + $1.balance.btcValue }
    }

    init(
        wallet: Wallet,
        currencyCode: String = "USD",
        priceService: PriceDataServiceType = PriceDataService.shared
    ) {
        self.wallet = wallet
        self.currencyCode = currencyCode
        self.priceService = priceService

        subscribeToPriceUpdates()
        Task { await loadCurrentPrice() }
    }

    func refreshPrice() {
        Task { await loadCurrentPrice() }
    }

    private func loadCurrentPrice() async {
        isLoading = true
        errorMessage = nil

        guard let priceData = await priceService.fetchCurrentPrice(for: currencyCode) else {
            fiatBalance = nil
            errorMessage = NSLocalizedString(
                "Unable to load price",
                comment: "Balance wallet row price load failure"
            )
            isLoading = false
            return
        }

        apply(priceData: priceData)
    }

    private func subscribeToPriceUpdates() {
        priceService.priceUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] priceData in
                guard let self else { return }
                self.apply(priceData: priceData)
            }
            .store(in: &cancellables)
    }

    private func apply(priceData: PriceData) {
        guard priceData.currency.caseInsensitiveCompare(currencyCode) == .orderedSame else {
            return
        }

        fiatBalance = totalBalance * priceData.price
        errorMessage = nil
        isLoading = false
    }
}
