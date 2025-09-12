import Foundation
import CryptoKit

extension String {
    var isValidBitcoinAddress: Bool {
        // Basic Bitcoin address validation (P2PKH, P2SH, Bech32)
        let p2pkhRegex = "^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$"
        let p2shRegex = "^3[a-km-zA-HJ-NP-Z1-9]{25,34}$"
        let bech32Regex = "^bc1[a-z0-9]{39,59}$"
        
        let p2pkhPredicate = NSPredicate(format: "SELF MATCHES %@", p2pkhRegex)
        let p2shPredicate = NSPredicate(format: "SELF MATCHES %@", p2shRegex)
        let bech32Predicate = NSPredicate(format: "SELF MATCHES %@", bech32Regex)
        
        return p2pkhPredicate.evaluate(with: self) ||
               p2shPredicate.evaluate(with: self) ||
               bech32Predicate.evaluate(with: self)
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