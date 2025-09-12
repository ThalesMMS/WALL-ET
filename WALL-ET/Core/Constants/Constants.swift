import Foundation

enum Constants {
    enum UserDefaults {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let selectedTheme = "selectedTheme"
        static let baseCurrency = "baseCurrency"
        static let biometricEnabled = "biometricEnabled"
        static let autoLockTimeout = "autoLockTimeout"
    }
    
    enum Keychain {
        static let walletSeed = "walletSeed"
        static let walletPassword = "walletPassword"
        static let duressPassword = "duressPassword"
    }
    
    enum API {
        static let bitcoinNodeURL = "https://blockchain.info"
        static let priceAPIURL = "https://api.coingecko.com/api/v3"
    }
    
    enum UI {
        static let standardPadding: Double = 16
        static let smallPadding: Double = 8
        static let largePadding: Double = 24
        static let cornerRadius: Double = 12
        static let smallCornerRadius: Double = 8
    }
    
    enum Bitcoin {
        static let satoshisPerBitcoin: Int64 = 100_000_000
        static let minimumDustAmount: Int64 = 546 // satoshis
        static let defaultFeeRate: Int = 20 // sat/vByte
    }
}