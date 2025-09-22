import Foundation
import Combine
import UIKit

@MainActor
final class ReceiveViewModel: ObservableObject {
    @Published private(set) var walletAddress = ""
    @Published var requestAmount = ""
    @Published var copied = false
    @Published var showShareSheet = false

    private let walletService: WalletService
    private let electrumService: ElectrumService
    private let qrGenerator: QRCodeGenerating
    private var cancellables = Set<AnyCancellable>()
    private var addressResetTask: Task<Void, Never>?
    private var didLoad = false
    private var gapLimit: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: "gap_limit") as? Int
            return stored ?? 20
        }
        set { UserDefaults.standard.set(newValue, forKey: "gap_limit") }
    }
    private var autoRotate: Bool {
        get {
            if UserDefaults.standard.object(forKey: "auto_rotate_receive") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "auto_rotate_receive")
        }
        set { UserDefaults.standard.set(newValue, forKey: "auto_rotate_receive") }
    }

    weak var coordinator: AppCoordinator?

    init(
        walletService: WalletService? = nil,
        electrumService: ElectrumService? = nil,
        qrGenerator: QRCodeGenerating = QRCodeGenerator(),
        initialAddress: String? = nil,
        skipInitialLoad: Bool = false
    ) {
        self.walletService = walletService ?? WalletService()
        self.electrumService = electrumService ?? ElectrumService.shared
        self.qrGenerator = qrGenerator
        if let initialAddress {
            walletAddress = initialAddress
        }
        if skipInitialLoad {
            didLoad = true
        }
        subscribeToElectrumUpdates()
    }

    func handleAppear() async {
        guard !didLoad else { return }
        didLoad = true
        await refreshReceiveAddress(force: true)
    }

    func updateCoordinator(_ coordinator: AppCoordinator) {
        guard self.coordinator !== coordinator else { return }
        self.coordinator = coordinator
        Task { await refreshReceiveAddress(force: true) }
    }

    func qrCodeImage() -> UIImage {
        qrGenerator.generate(from: bitcoinURI())
    }

    func bitcoinURI() -> String {
        var uri = "bitcoin:\(walletAddress)"
        if !requestAmount.isEmpty, let amount = Double(requestAmount) {
            uri += "?amount=\(amount)"
        }
        return uri
    }

    func copyAddressToClipboard() {
        guard !walletAddress.isEmpty else { return }
        UIPasteboard.general.string = walletAddress
        copied = true
        addressResetTask?.cancel()
        addressResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.resetCopiedState()
        }
    }

    func presentShareSheet() {
        showShareSheet = true
    }

    func dismissShareSheet() {
        showShareSheet = false
    }

    func rotateAddressIfNeeded() async {
        await refreshReceiveAddress(force: true)
    }

    // MARK: - Private Helpers
    private func subscribeToElectrumUpdates() {
        electrumService.transactionUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshReceiveAddress(force: false) }
            }
            .store(in: &cancellables)

        electrumService.addressStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self else { return }
                if self.autoRotate, update.address == self.walletAddress, update.hasHistory {
                    Task { await self.refreshReceiveAddress(force: true) }
                }
            }
            .store(in: &cancellables)
    }

    private func resetCopiedState() {
        copied = false
    }

    private func refreshReceiveAddress(force: Bool) async {
        if !force, !walletAddress.isEmpty { return }

        if let coordinator, let selected = coordinator.selectedWallet {
            await updateAddress(from: selected.id, fallback: selected.address)
            return
        }

        if let active = await walletService.getActiveWallet() {
            await updateAddress(from: active.id, fallback: active.address)
            return
        }

        if let first = try? await walletService.fetchWallets().first {
            await updateAddress(from: first.id, fallback: first.address)
        }
    }

    private func updateAddress(from walletId: UUID, fallback: String) async {
        if let next = await walletService.getNextReceiveAddress(for: walletId, gap: gapLimit) {
            walletAddress = next
            logInfo("[Receive] Next address: \(next)")
            electrumService.subscribeToAddress(next)
        } else {
            walletAddress = fallback
            if !fallback.isEmpty {
                logInfo("[Receive] Using fallback address: \(fallback)")
                electrumService.subscribeToAddress(fallback)
            }
        }
    }
}
