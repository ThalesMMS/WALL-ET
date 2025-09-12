import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Bitcoin Service
class BitcoinService {
    
    // MARK: - Properties
    static let shared = BitcoinService()
    private let network: Network
    
    // MARK: - Enums
    enum Network {
        case mainnet
        case testnet
        case regtest
        
        var bech32HRP: String {
            switch self {
            case .mainnet: return "bc"
            case .testnet, .regtest: return "tb"
            }
        }
        
        var p2pkhVersion: UInt8 {
            switch self {
            case .mainnet: return 0x00
            case .testnet, .regtest: return 0x6f
            }
        }
        
        var p2shVersion: UInt8 {
            switch self {
            case .mainnet: return 0x05
            case .testnet, .regtest: return 0xc4
            }
        }
        
        var wifVersion: UInt8 {
            switch self {
            case .mainnet: return 0x80
            case .testnet, .regtest: return 0xef
            }
        }
        
        var xpubVersion: UInt32 {
            switch self {
            case .mainnet: return 0x0488b21e
            case .testnet, .regtest: return 0x043587cf
            }
        }
        
        var xprvVersion: UInt32 {
            switch self {
            case .mainnet: return 0x0488ade4
            case .testnet, .regtest: return 0x04358394
            }
        }
    }
    
    enum AddressType {
        case p2pkh  // Legacy (1...)
        case p2sh   // Nested SegWit (3...)
        case p2wpkh // Native SegWit (bc1...)
        case p2wsh  // Native SegWit Script (bc1...)
        case p2tr   // Taproot (bc1p...)
    }
    
    // MARK: - Initialization
    init(network: Network = .mainnet) {
        self.network = network
    }
    
    // MARK: - Key Generation
    func generatePrivateKey() -> Data {
        return CryptoService.shared.generatePrivateKey()
    }
    
    func derivePublicKey(from privateKey: Data, compressed: Bool = true) -> Data {
        return CryptoService.shared.derivePublicKey(from: privateKey, compressed: compressed) ?? Data()
    }
    
    // MARK: - Address Generation
    func generateAddress(from publicKey: Data, type: AddressType) -> String {
        switch type {
        case .p2pkh:
            return generateP2PKH(from: publicKey)
        case .p2sh:
            return generateP2SH(from: publicKey)
        case .p2wpkh:
            return generateP2WPKH(from: publicKey)
        case .p2wsh:
            return generateP2WSH(from: publicKey)
        case .p2tr:
            return generateP2TR(from: publicKey)
        }
    }
    
    private func generateP2PKH(from publicKey: Data) -> String {
        let hash160 = hash160(publicKey)
        var data = Data([network.p2pkhVersion])
        data.append(hash160)
        return Base58.encode(data)
    }
    
    private func generateP2SH(from publicKey: Data) -> String {
        // Create P2WPKH script
        let pubKeyHash = hash160(publicKey)
        var redeemScript = Data([0x00, 0x14]) // OP_0 + push 20 bytes
        redeemScript.append(pubKeyHash)
        
        // Hash the redeem script
        let scriptHash = hash160(redeemScript)
        var data = Data([network.p2shVersion])
        data.append(scriptHash)
        return Base58.encode(data)
    }
    
    private func generateP2WPKH(from publicKey: Data) -> String {
        let pubKeyHash = hash160(publicKey)
        return Bech32.encode(hrp: network.bech32HRP, version: 0, program: pubKeyHash)
    }
    
    private func generateP2WSH(from script: Data) -> String {
        let scriptHash = sha256(script)
        return Bech32.encode(hrp: network.bech32HRP, version: 0, program: scriptHash)
    }
    
    private func generateP2TR(from publicKey: Data) -> String {
        // Taproot uses x-only public key (32 bytes)
        let xOnlyPubkey = publicKey.dropFirst() // Remove prefix byte
        return Bech32.encode(hrp: network.bech32HRP, version: 1, program: xOnlyPubkey)
    }
    
    // MARK: - Address Validation
    func validateAddress(_ address: String) -> Bool {
        // Check Bech32 addresses
        if address.lowercased().hasPrefix(network.bech32HRP) {
            return Bech32.decode(address) != nil
        }
        
        // Check Base58 addresses
        if let decoded = Base58.decode(address) {
            if decoded.count < 25 { return false }
            
            let version = decoded[0]
            let checksum = decoded.suffix(4)
            let payload = decoded.prefix(decoded.count - 4)
            
            // Verify checksum
            let hash = sha256(sha256(payload))
            let calculatedChecksum = hash.prefix(4)
            
            guard checksum == calculatedChecksum else { return false }
            
            // Verify version
            return version == network.p2pkhVersion || version == network.p2shVersion
        }
        
        return false
    }
    
    // MARK: - Script Creation
    func createP2PKHScript(for address: String) -> Data? {
        guard let decoded = Base58.decode(address) else { return nil }
        let hash160 = decoded.dropFirst().prefix(20)
        
        var script = Data()
        script.append(0x76) // OP_DUP
        script.append(0xa9) // OP_HASH160
        script.append(0x14) // Push 20 bytes
        script.append(hash160)
        script.append(0x88) // OP_EQUALVERIFY
        script.append(0xac) // OP_CHECKSIG
        
        return script
    }
    
    func createP2WPKHScript(for address: String) -> Data? {
        guard let decoded = Bech32.decode(address) else { return nil }
        let (version, program) = decoded
        
        guard version == 0, program.count == 20 else { return nil }
        
        var script = Data()
        script.append(0x00) // OP_0
        script.append(0x14) // Push 20 bytes
        script.append(program)
        
        return script
    }
    
    // MARK: - WIF (Wallet Import Format)
    func exportPrivateKeyWIF(_ privateKey: Data, compressed: Bool = true) -> String {
        var data = Data([network.wifVersion])
        data.append(privateKey)
        if compressed {
            data.append(0x01)
        }
        return Base58.encode(data)
    }
    
    func importPrivateKeyWIF(_ wif: String) -> (privateKey: Data, compressed: Bool)? {
        guard let decoded = Base58.decode(wif) else { return nil }
        
        let version = decoded[0]
        guard version == network.wifVersion else { return nil }
        
        let compressed = decoded.count == 34
        let privateKey = compressed ? decoded[1..<33] : decoded[1..<33]
        
        return (Data(privateKey), compressed)
    }
    
    // MARK: - Helper Functions
    private func hash160(_ data: Data) -> Data {
        return CryptoService.shared.hash160(data)
    }
    
    private func sha256(_ data: Data) -> Data {
        return CryptoService.shared.sha256(data)
    }
    
    private func ripemd160(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
}

// MARK: - Base58 Encoding/Decoding
struct Base58 {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    
    static func encode(_ data: Data) -> String {
        // Add checksum per Base58Check
        var payload = Data(data)
        let checksum = Data(SHA256.hash(data: Data(SHA256.hash(data: payload)))).prefix(4)
        payload.append(checksum)

        // Count leading zero bytes
        let zeroCount = payload.prefix(while: { $0 == 0 }).count

        // Convert to Base58
        var bytes = [UInt8](payload)
        var encoded = ""
        while !bytes.isEmpty && bytes.contains(where: { $0 != 0 }) {
            var remainder = 0
            var newBytes: [UInt8] = []
            newBytes.reserveCapacity(bytes.count)
            for b in bytes {
                let acc = Int(b) + remainder * 256
                let q = acc / 58
                let r = acc % 58
                if !(newBytes.isEmpty && q == 0) {
                    newBytes.append(UInt8(q))
                }
                remainder = r
            }
            let char = alphabet[alphabet.index(alphabet.startIndex, offsetBy: remainder)]
            encoded.insert(char, at: encoded.startIndex)
            bytes = newBytes
        }

        // Add '1' for each leading zero byte
        for _ in 0..<zeroCount { encoded.insert("1", at: encoded.startIndex) }
        return encoded
    }
    
    static func decode(_ string: String) -> Data? {
        // Build index map
        var indexMap: [Character: Int] = [:]
        indexMap.reserveCapacity(alphabet.count)
        for (i, c) in alphabet.enumerated() { indexMap[c] = i }

        // Count leading '1's (zero bytes)
        let zeroCount = string.prefix(while: { $0 == "1" }).count

        // Convert Base58 to base256
        var b256 = [UInt8](repeating: 0, count: max(1, string.count * 733 / 1000 + 1))
        var length = 0
        for char in string where char != " " {
            guard let carry = indexMap[char] else { return nil }
            var carryVal = carry
            var i = 0
            for j in stride(from: b256.count - 1, through: 0, by: -1) {
                if i >= length && carryVal == 0 { break }
                let val = Int(b256[j]) * 58 + carryVal
                b256[j] = UInt8(val & 0xff)
                carryVal = val >> 8
                i += 1
            }
            length = i
        }

        // Skip leading zeros in b256
        var it = b256.drop(while: { $0 == 0 })
        var data = Data(repeating: 0, count: zeroCount)
        data.append(contentsOf: it)

        // Verify checksum
        guard data.count >= 4 else { return nil }
        let payload = data.dropLast(4)
        let checksum = data.suffix(4)
        let calculated = Data(SHA256.hash(data: Data(SHA256.hash(data: payload)))).prefix(4)
        guard checksum == calculated else { return nil }
        return Data(payload)
    }
}

// MARK: - Bech32 Encoding/Decoding
struct Bech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    
    static func encode(hrp: String, version: Int, program: Data) -> String {
        var data = [UInt8]([UInt8(version)])
        data.append(contentsOf: convertBits(from: program, fromBits: 8, toBits: 5, pad: true) ?? Data())
        
        let checksum = createChecksum(hrp: hrp, data: data)
        data.append(contentsOf: checksum)
        
        let encoded = data.map { charset[charset.index(charset.startIndex, offsetBy: Int($0))] }
        return hrp + "1" + String(encoded)
    }
    
    static func decode(_ address: String) -> (version: Int, program: Data)? {
        guard let separatorIndex = address.firstIndex(of: "1") else { return nil }
        
        let hrp = String(address[..<separatorIndex])
        let data = String(address[address.index(after: separatorIndex)...])
        
        var values = [UInt8]()
        for char in data {
            guard let index = charset.firstIndex(of: char) else { return nil }
            values.append(UInt8(charset.distance(from: charset.startIndex, to: index)))
        }
        
        // Verify checksum
        guard verifyChecksum(hrp: hrp, data: values) else { return nil }
        
        // Remove checksum
        values.removeLast(6)
        
        guard !values.isEmpty else { return nil }
        let version = Int(values.removeFirst())
        
        // Convert from 5-bit to 8-bit
        guard let program = convertBits(from: Data(values), fromBits: 5, toBits: 8, pad: false) else {
            return nil
        }
        
        return (version, program)
    }
    
    private static func createChecksum(hrp: String, data: [UInt8]) -> [UInt8] {
        let values = hrpExpand(hrp) + data
        let polymod = polymod(values + [0, 0, 0, 0, 0, 0]) ^ 1
        
        var checksum = [UInt8]()
        for i in 0..<6 {
            checksum.append(UInt8((polymod >> (5 * (5 - i))) & 31))
        }
        return checksum
    }
    
    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        return polymod(hrpExpand(hrp) + data) == 1
    }
    
    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var result = [UInt8]()
        for char in hrp {
            result.append(UInt8(char.asciiValue! >> 5))
        }
        result.append(0)
        for char in hrp {
            result.append(UInt8(char.asciiValue! & 31))
        }
        return result
    }
    
    private static func polymod(_ values: [UInt8]) -> Int {
        let generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
        var chk = 1
        
        for value in values {
            let top = chk >> 25
            chk = (chk & 0x1ffffff) << 5 ^ Int(value)
            for i in 0..<5 {
                chk ^= ((top >> i) & 1) != 0 ? generator[i] : 0
            }
        }
        
        return chk
    }
    
    private static func convertBits(from data: Data, fromBits: Int, toBits: Int, pad: Bool) -> Data? {
        var acc = 0
        var bits = 0
        var result = Data()
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1
        
        for byte in data {
            acc = ((acc << fromBits) | Int(byte)) & maxAcc
            bits += fromBits
            
            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((acc >> bits) & maxv))
            }
        }
        
        if pad {
            if bits > 0 {
                result.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }
        
        return result
    }
}

// Real secp256k1 cryptography is now implemented in CryptoService

// MARK: - BigInt (Simplified implementation)
struct BigInt {
    private var value: String
    
    init(_ data: Data) {
        self.value = data.map { String(format: "%02x", $0) }.joined()
    }
    
    init(_ int: Int) {
        self.value = String(int)
    }
    
    func quotientAndRemainder(dividingBy divisor: BigInt) -> (quotient: BigInt, remainder: BigInt) {
        // Simplified - use actual BigInt library in production
        return (BigInt(0), BigInt(0))
    }
    
    static func +(lhs: BigInt, rhs: BigInt) -> BigInt {
        return BigInt(0)
    }
    
    static func *(lhs: BigInt, rhs: BigInt) -> BigInt {
        return BigInt(0)
    }
    
    static func >(lhs: BigInt, rhs: Int) -> Bool {
        return Int(lhs.value) ?? 0 > rhs
    }
}

// MARK: - Extensions
extension Digest {
    var data: Data {
        return Data(self)
    }
}
