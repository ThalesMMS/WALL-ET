import Foundation
import Combine

@MainActor
final class CreateWalletViewModel: ObservableObject {
    @Published var walletName = ""
    @Published var walletType: WalletType = .bitcoin
    @Published var isCreating = false
    @Published var errorMessage: String?
    @Published var createdWallet: Wallet?
    @Published var mnemonic: String?
    
    private let createWalletUseCase: CreateWalletUseCaseProtocol
    private let walletRepository: WalletRepositoryProtocol
    
    init(createWalletUseCase: CreateWalletUseCaseProtocol, walletRepository: WalletRepositoryProtocol) {
        self.createWalletUseCase = createWalletUseCase
        self.walletRepository = walletRepository
    }
    
    var isValidName: Bool {
        !walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func createWallet() async {
        guard isValidName else {
            errorMessage = "Please enter a wallet name"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        do {
            let wallet = try await createWalletUseCase.execute(name: walletName, type: walletType)
            createdWallet = wallet
            
            // Generate mnemonic for display
            mnemonic = generateMockMnemonic()
            
            logInfo("Wallet created successfully: \(wallet.name)")
        } catch {
            errorMessage = error.localizedDescription
            logError("Failed to create wallet: \(error)")
        }
        
        isCreating = false
    }
    
    func importWallet(mnemonic: String) async {
        guard isValidName else {
            errorMessage = "Please enter a wallet name"
            return
        }
        
        guard !mnemonic.isEmpty else {
            errorMessage = "Please enter a recovery phrase"
            return
        }
        // Log what we will interpret from the seed phrase (normalized form)
        let trimmed = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .decomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let words = normalized.split(separator: " ")
        logInfo("Import seed: rawWordCount=\(trimmed.split(whereSeparator: { $0.isWhitespace }).count), normalizedWordCount=\(words.count)")
        logInfo("Interpreted mnemonic (redacted): \(redactMnemonic(normalized))")
        // Validate mnemonic using BIP39 word list and checksum
        do {
            let valid = try MnemonicService.shared.validateMnemonic(normalized)
            if !valid {
                errorMessage = "Invalid recovery phrase"
                return
            }
        } catch {
            // Provide a friendlier error for common cases
            if let err = error as? MnemonicService.MnemonicError {
                switch err {
                case .invalidWordCount:
                    errorMessage = "Phrase must be 12, 15, 18, 21, or 24 words"
                case .invalidWord(let w):
                    errorMessage = "Unknown word: \(w)"
                case .invalidChecksum:
                    errorMessage = "Checksum is invalid. Please check the words order."
                default:
                    errorMessage = err.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        do {
            let wallet = try await walletRepository.importWallet(
                mnemonic: normalized,
                name: walletName,
                type: walletType
            )
            createdWallet = wallet
            if let addr = wallet.accounts.first?.address {
                logInfo("Imported wallet first address: \(addr)")
            } else {
                logWarning("Imported wallet has no first address")
            }
            logInfo("Wallet imported successfully: \(wallet.name)")
        } catch {
            errorMessage = error.localizedDescription
            logError("Failed to import wallet: \(error)")
        }
        
        isCreating = false
    }
    
    func importWatchOnlyWallet(address: String) async {
        guard isValidName else {
            errorMessage = "Please enter a wallet name"
            return
        }
        
        guard address.isValidBitcoinAddress else {
            errorMessage = "Invalid Bitcoin address"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        do {
            let wallet = try await walletRepository.importWatchOnlyWallet(
                address: address,
                name: walletName,
                type: walletType
            )
            createdWallet = wallet
            logInfo("Watch-only wallet imported successfully: \(wallet.name)")
        } catch {
            errorMessage = error.localizedDescription
            logError("Failed to import watch-only wallet: \(error)")
        }
        
        isCreating = false
    }
    
    private func generateMockMnemonic() -> String {
        // In a real app, use proper BIP39 library
        let words = [
            "abandon", "ability", "able", "about", "above", "absent",
            "absorb", "abstract", "absurd", "abuse", "access", "accident"
        ]
        return words.joined(separator: " ")
    }
}

// MARK: - Redaction helper for mnemonic logging
private func redactMnemonic(_ phrase: String) -> String {
    let ws = phrase.split(separator: " ")
    if ws.count <= 6 { return phrase }
    let head = ws.prefix(3).joined(separator: " ")
    let tail = ws.suffix(3).joined(separator: " ")
    return "\(head) … \(tail)"
}
