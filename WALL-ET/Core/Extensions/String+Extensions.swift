import Foundation
import CryptoKit

extension String {
    var isValidBitcoinAddress: Bool {
        // Accept mainnet/testnet/regtest (Base58 + Bech32)
        // Base58 P2PKH/P2SH (mainnet)
        let p2_main = "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$"
        // Base58 P2PKH (testnet 'm' or 'n') and P2SH (testnet '2')
        let p2_test = "^[mn2][a-km-zA-HJ-NP-Z1-9]{25,34}$"
        // Bech32: bc1 (main), tb1 (testnet), bcrt1 (regtest)
        let bech32 = "^(bc|tb|bcrt)1[0-9a-z]{6,87}$"
        let predicate = NSPredicate(format: "SELF MATCHES[c] %@ OR SELF MATCHES[c] %@ OR SELF MATCHES[c] %@", p2_main, p2_test, bech32)
        return predicate.evaluate(with: self)
    }
    
    func sha256() -> String {
        let data = Data(utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}
