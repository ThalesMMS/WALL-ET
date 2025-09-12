import Foundation
import CryptoKit
import libsecp256k1

/// Real Bitcoin cryptography implementation using secp256k1
class CryptoService {
    
    static let shared = CryptoService()
    private let context: OpaquePointer
    
    init() {
        // Initialize secp256k1 context for signing and verification
        context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY))!
    }
    
    deinit {
        secp256k1_context_destroy(context)
    }
    
    // MARK: - Key Generation
    
    /// Generate a cryptographically secure private key
    func generatePrivateKey() -> Data {
        var privateKey = Data(count: 32)
        var attempts = 0
        
        repeat {
            privateKey.withUnsafeMutableBytes { bytes in
                _ = SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
            }
            attempts += 1
        } while !isValidPrivateKey(privateKey) && attempts < 100
        
        return privateKey
    }
    
    /// Validate a private key is within the valid range for secp256k1
    func isValidPrivateKey(_ privateKey: Data) -> Bool {
        guard privateKey.count == 32 else { return false }
        
        return privateKey.withUnsafeBytes { bytes in
            secp256k1_ec_seckey_verify(context, bytes.bindMemory(to: UInt8.self).baseAddress!) == 1
        }
    }
    
    /// Derive public key from private key
    func derivePublicKey(from privateKey: Data, compressed: Bool = true) -> Data? {
        guard isValidPrivateKey(privateKey) else { return nil }
        
        var pubkey = secp256k1_pubkey()
        
        let result = privateKey.withUnsafeBytes { privateKeyBytes in
            secp256k1_ec_pubkey_create(context, &pubkey, privateKeyBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard result == 1 else { return nil }
        
        var outputLength = compressed ? 33 : 65
        var output = Data(count: outputLength)
        
        let serializeResult = output.withUnsafeMutableBytes { outputBytes in
            secp256k1_ec_pubkey_serialize(
                context,
                outputBytes.bindMemory(to: UInt8.self).baseAddress!,
                &outputLength,
                &pubkey,
                compressed ? UInt32(SECP256K1_EC_COMPRESSED) : UInt32(SECP256K1_EC_UNCOMPRESSED)
            )
        }
        
        guard serializeResult == 1 else { return nil }
        
        return output
    }
    
    // MARK: - Transaction Signing
    
    /// Sign a transaction hash with a private key
    func signTransactionHash(_ hash: Data, with privateKey: Data) -> Data? {
        guard hash.count == 32, isValidPrivateKey(privateKey) else { return nil }
        
        var signature = secp256k1_ecdsa_signature()
        
        let result = hash.withUnsafeBytes { hashBytes in
            privateKey.withUnsafeBytes { privateKeyBytes in
                secp256k1_ecdsa_sign(
                    context,
                    &signature,
                    hashBytes.bindMemory(to: UInt8.self).baseAddress!,
                    privateKeyBytes.bindMemory(to: UInt8.self).baseAddress!,
                    nil,
                    nil
                )
            }
        }
        
        guard result == 1 else { return nil }
        
        // Serialize signature to DER format
        var derSignature = Data(count: 72)
        var derLength = 72
        
        let serializeResult = derSignature.withUnsafeMutableBytes { derBytes in
            secp256k1_ecdsa_signature_serialize_der(
                context,
                derBytes.bindMemory(to: UInt8.self).baseAddress!,
                &derLength,
                &signature
            )
        }
        
        guard serializeResult == 1 else { return nil }
        
        return derSignature.prefix(derLength)
    }
    
    /// Sign for SegWit transactions (returns 64-byte signature)
    func signSegwitHash(_ hash: Data, with privateKey: Data) -> Data? {
        guard hash.count == 32, isValidPrivateKey(privateKey) else { return nil }
        
        var signature = secp256k1_ecdsa_signature()
        
        let result = hash.withUnsafeBytes { hashBytes in
            privateKey.withUnsafeBytes { privateKeyBytes in
                secp256k1_ecdsa_sign(
                    context,
                    &signature,
                    hashBytes.bindMemory(to: UInt8.self).baseAddress!,
                    privateKeyBytes.bindMemory(to: UInt8.self).baseAddress!,
                    nil,
                    nil
                )
            }
        }
        
        guard result == 1 else { return nil }
        
        // Return compact 64-byte signature for witness
        var compactSig = Data(count: 64)
        compactSig.withUnsafeMutableBytes { bytes in
            memcpy(bytes.baseAddress!, &signature.data, 64)
        }
        
        return compactSig
    }
    
    // MARK: - Signature Verification
    
    /// Verify a signature against a public key and message hash
    func verifySignature(_ signature: Data, publicKey: Data, hash: Data) -> Bool {
        guard hash.count == 32 else { return false }
        
        // Parse public key
        var pubkey = secp256k1_pubkey()
        let pubkeyResult = publicKey.withUnsafeBytes { pubkeyBytes in
            secp256k1_ec_pubkey_parse(
                context,
                &pubkey,
                pubkeyBytes.bindMemory(to: UInt8.self).baseAddress!,
                publicKey.count
            )
        }
        
        guard pubkeyResult == 1 else { return false }
        
        // Parse signature from DER
        var sig = secp256k1_ecdsa_signature()
        let sigResult = signature.withUnsafeBytes { sigBytes in
            secp256k1_ecdsa_signature_parse_der(
                context,
                &sig,
                sigBytes.bindMemory(to: UInt8.self).baseAddress!,
                signature.count
            )
        }
        
        guard sigResult == 1 else { return false }
        
        // Verify
        let verifyResult = hash.withUnsafeBytes { hashBytes in
            secp256k1_ecdsa_verify(
                context,
                &sig,
                hashBytes.bindMemory(to: UInt8.self).baseAddress!,
                &pubkey
            )
        }
        
        return verifyResult == 1
    }
    
    // MARK: - Schnorr Signatures (for Taproot)
    
    /// Create Schnorr signature for Taproot
    func signSchnorr(_ hash: Data, with privateKey: Data) -> Data? {
        guard hash.count == 32, isValidPrivateKey(privateKey) else { return nil }
        
        var keypair = secp256k1_keypair()
        
        let keypairResult = privateKey.withUnsafeBytes { privateKeyBytes in
            secp256k1_keypair_create(context, &keypair, privateKeyBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard keypairResult == 1 else { return nil }
        
        var signature = Data(count: 64)
        
        let signResult = signature.withUnsafeMutableBytes { signatureBytes in
            hash.withUnsafeBytes { hashBytes in
                secp256k1_schnorrsig_sign32(
                    context,
                    signatureBytes.bindMemory(to: UInt8.self).baseAddress!,
                    hashBytes.bindMemory(to: UInt8.self).baseAddress!,
                    &keypair,
                    nil
                )
            }
        }
        
        guard signResult == 1 else { return nil }
        
        return signature
    }
    
    /// Get x-only public key for Taproot
    func getXOnlyPublicKey(from privateKey: Data) -> Data? {
        guard isValidPrivateKey(privateKey) else { return nil }
        
        var keypair = secp256k1_keypair()
        
        let keypairResult = privateKey.withUnsafeBytes { privateKeyBytes in
            secp256k1_keypair_create(context, &keypair, privateKeyBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard keypairResult == 1 else { return nil }
        
        var xonly_pubkey = secp256k1_xonly_pubkey()
        var pk_parity: Int32 = 0
        
        let xonlyResult = secp256k1_keypair_xonly_pub(context, &xonly_pubkey, &pk_parity, &keypair)
        
        guard xonlyResult == 1 else { return nil }
        
        var output = Data(count: 32)
        
        let serializeResult = output.withUnsafeMutableBytes { outputBytes in
            secp256k1_xonly_pubkey_serialize(
                context,
                outputBytes.bindMemory(to: UInt8.self).baseAddress!,
                &xonly_pubkey
            )
        }
        
        guard serializeResult == 1 else { return nil }
        
        return output
    }
    
    // MARK: - Key Tweaking (for Taproot)
    
    /// Tweak private key for Taproot
    func tweakPrivateKey(_ privateKey: Data, with tweak: Data) -> Data? {
        guard privateKey.count == 32, tweak.count == 32 else { return nil }
        
        var keypair = secp256k1_keypair()
        
        let keypairResult = privateKey.withUnsafeBytes { privateKeyBytes in
            secp256k1_keypair_create(context, &keypair, privateKeyBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard keypairResult == 1 else { return nil }
        
        let tweakResult = tweak.withUnsafeBytes { tweakBytes in
            secp256k1_keypair_xonly_tweak_add(context, &keypair, tweakBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        guard tweakResult == 1 else { return nil }
        
        var tweakedKey = Data(count: 32)
        
        let secretResult = tweakedKey.withUnsafeMutableBytes { keyBytes in
            secp256k1_keypair_sec(context, keyBytes.bindMemory(to: UInt8.self).baseAddress!, &keypair)
        }
        
        guard secretResult == 1 else { return nil }
        
        return tweakedKey
    }
    
    // MARK: - Hash Functions
    
    /// SHA256 hash
    func sha256(_ data: Data) -> Data {
        return Data(SHA256.hash(data: data))
    }
    
    /// Double SHA256 (used in Bitcoin)
    func hash256(_ data: Data) -> Data {
        return sha256(sha256(data))
    }
    
    /// RIPEMD160 hash
    func ripemd160(_ data: Data) -> Data {
        return RIPEMD160.hash(data)
    }
    
    /// Hash160 (SHA256 then RIPEMD160)
    func hash160(_ data: Data) -> Data {
        return ripemd160(sha256(data))
    }

    // MARK: - Scalar tweak (BIP32)
    /// Add a 32-byte tweak to a private key modulo secp256k1 order.
    func tweakAddPrivateKey(_ privateKey: Data, tweak: Data) -> Data? {
        guard privateKey.count == 32, tweak.count == 32 else { return nil }
        var seckey = privateKey
        let ok = seckey.withUnsafeMutableBytes { keyBytes in
            tweak.withUnsafeBytes { tweakBytes in
                secp256k1_ec_seckey_tweak_add(
                    context,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress!,
                    tweakBytes.bindMemory(to: UInt8.self).baseAddress!
                )
            }
        }
        return ok == 1 ? seckey : nil
    }
}
