import Foundation

protocol WalletDerivationServicing {
    func mnemonic(for walletName: String) throws -> String?
    func saveMnemonic(_ mnemonic: String, walletName: String) throws
    func deriveFirstAccount(for walletName: String, type: WalletType) throws -> AccountDerivation
    func deriveAddress(for walletName: String, path: String, network: BitcoinService.Network) throws -> AddressDerivation
}

enum WalletDerivationError: Error, Equatable {
    case mnemonicNotFound(name: String)
}

struct AccountDerivation {
    let mnemonic: String
    let privateKey: Data
    let address: String
    let network: BitcoinService.Network
    let coinType: Int

    var accountBasePath: String { "m/84'/\(coinType)'/0'" }
}

struct AddressDerivation {
    let privateKey: Data
    let address: String
}

struct WalletDerivationService: WalletDerivationServicing {
    private let keychain: KeychainServiceProtocol
    private let mnemonicService: MnemonicService

    init(keychain: KeychainServiceProtocol, mnemonicService: MnemonicService = .shared) {
        self.keychain = keychain
        self.mnemonicService = mnemonicService
    }

    func mnemonic(for walletName: String) throws -> String? {
        try keychain.loadString(for: mnemonicKey(walletName))
    }

    func saveMnemonic(_ mnemonic: String, walletName: String) throws {
        try keychain.saveString(mnemonic, for: mnemonicKey(walletName))
    }

    func deriveFirstAccount(for walletName: String, type: WalletType) throws -> AccountDerivation {
        guard let mnemonic = try mnemonic(for: walletName) else {
            throw WalletDerivationError.mnemonicNotFound(name: walletName)
        }

        let network = type == .testnet ? BitcoinService.Network.testnet : .mainnet
        let coin = type == .testnet ? 1 : 0
        let path = "m/84'/\(coin)'/0'/0/0"
        let seed = mnemonicService.mnemonicToSeed(mnemonic)
        let (privateKey, address) = mnemonicService.deriveAddress(from: seed, path: path, network: network)

        return AccountDerivation(
            mnemonic: mnemonic,
            privateKey: privateKey,
            address: address,
            network: network,
            coinType: coin
        )
    }

    func deriveAddress(for walletName: String, path: String, network: BitcoinService.Network) throws -> AddressDerivation {
        guard let mnemonic = try mnemonic(for: walletName) else {
            throw WalletDerivationError.mnemonicNotFound(name: walletName)
        }

        let seed = mnemonicService.mnemonicToSeed(mnemonic)
        let (privateKey, address) = mnemonicService.deriveAddress(from: seed, path: path, network: network)
        return AddressDerivation(privateKey: privateKey, address: address)
    }

    private func mnemonicKey(_ walletName: String) -> String {
        "\(Constants.Keychain.walletSeed)_\(walletName)"
    }
}
