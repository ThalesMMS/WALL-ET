import XCTest
@testable import WALL_ET

class RealCryptoTests: XCTestCase {
    
    var cryptoService: CryptoService!
    var bitcoinService: BitcoinService!
    var mnemonicService: MnemonicService!
    
    override func setUp() {
        super.setUp()
        cryptoService = CryptoService.shared
        bitcoinService = BitcoinService(network: .testnet)
        mnemonicService = MnemonicService.shared
    }
    
    // MARK: - Key Generation Tests
    
    func testGeneratePrivateKey() {
        let privateKey = cryptoService.generatePrivateKey()
        
        XCTAssertEqual(privateKey.count, 32)
        XCTAssertTrue(cryptoService.isValidPrivateKey(privateKey))
        
        // Generate multiple keys and ensure they're different
        let privateKey2 = cryptoService.generatePrivateKey()
        XCTAssertNotEqual(privateKey, privateKey2)
    }
    
    func testDerivePublicKey() {
        let privateKey = cryptoService.generatePrivateKey()
        
        // Test compressed public key
        let compressedPubKey = cryptoService.derivePublicKey(from: privateKey, compressed: true)
        XCTAssertNotNil(compressedPubKey)
        XCTAssertEqual(compressedPubKey?.count, 33)
        XCTAssertTrue(compressedPubKey![0] == 0x02 || compressedPubKey![0] == 0x03)
        
        // Test uncompressed public key
        let uncompressedPubKey = cryptoService.derivePublicKey(from: privateKey, compressed: false)
        XCTAssertNotNil(uncompressedPubKey)
        XCTAssertEqual(uncompressedPubKey?.count, 65)
        XCTAssertEqual(uncompressedPubKey![0], 0x04)
    }
    
    // MARK: - BIP39 Tests
    
    func testGenerateMnemonic24Words() throws {
        let mnemonic = try mnemonicService.generateMnemonic(strength: .words24)
        let words = mnemonic.split(separator: " ")
        
        XCTAssertEqual(words.count, 24)
        
        // Verify all words are in the word list
        let wordList = mnemonicService.wordList
        for word in words {
            XCTAssertTrue(wordList.contains(String(word)))
        }
        
        // Verify mnemonic is valid
        XCTAssertTrue(try mnemonicService.validateMnemonic(mnemonic))
    }
    
    func testMnemonicToSeed() {
        // Test vector from BIP39 spec
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let seed = mnemonicService.mnemonicToSeed(mnemonic)
        
        XCTAssertEqual(seed.count, 64)
        
        // Expected seed from BIP39 test vectors
        let expectedSeed = Data(hex: "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4")
        XCTAssertEqual(seed.hexString, expectedSeed.hexString)
    }
    
    // MARK: - Transaction Signing Tests
    
    func testSignTransactionHash() {
        let privateKey = cryptoService.generatePrivateKey()
        let hash = cryptoService.sha256("test transaction".data(using: .utf8)!)
        
        let signature = cryptoService.signTransactionHash(hash, with: privateKey)
        XCTAssertNotNil(signature)
        
        // DER signature should be between 70-72 bytes typically
        XCTAssertGreaterThanOrEqual(signature!.count, 68)
        XCTAssertLessThanOrEqual(signature!.count, 72)
        
        // Verify signature starts with 0x30 (DER sequence tag)
        XCTAssertEqual(signature![0], 0x30)
    }
    
    func testSignAndVerify() {
        let privateKey = cryptoService.generatePrivateKey()
        let publicKey = cryptoService.derivePublicKey(from: privateKey, compressed: true)!
        let message = "Hello, Bitcoin!".data(using: .utf8)!
        let hash = cryptoService.sha256(message)
        
        // Sign the hash
        let signature = cryptoService.signTransactionHash(hash, with: privateKey)!
        
        // Verify the signature
        let isValid = cryptoService.verifySignature(signature, publicKey: publicKey, hash: hash)
        XCTAssertTrue(isValid)
        
        // Verify with wrong message should fail
        let wrongHash = cryptoService.sha256("Wrong message".data(using: .utf8)!)
        let isInvalid = cryptoService.verifySignature(signature, publicKey: publicKey, hash: wrongHash)
        XCTAssertFalse(isInvalid)
    }
    
    // MARK: - Address Generation Tests
    
    func testGenerateBitcoinAddresses() {
        let privateKey = cryptoService.generatePrivateKey()
        let publicKey = cryptoService.derivePublicKey(from: privateKey, compressed: true)!
        
        // Test P2PKH (Legacy)
        let legacyAddress = bitcoinService.generateAddress(from: publicKey, type: .p2pkh)
        XCTAssertTrue(legacyAddress.starts(with: "m") || legacyAddress.starts(with: "n")) // testnet
        
        // Test P2WPKH (Native SegWit)
        let segwitAddress = bitcoinService.generateAddress(from: publicKey, type: .p2wpkh)
        XCTAssertTrue(segwitAddress.starts(with: "tb1q")) // testnet bech32
        
        // Test P2TR (Taproot)
        let taprootAddress = bitcoinService.generateAddress(from: publicKey, type: .p2tr)
        XCTAssertTrue(taprootAddress.starts(with: "tb1p")) // testnet taproot
    }
    
    // MARK: - Taproot Tests
    
    func testSchnorrSignature() {
        let privateKey = cryptoService.generatePrivateKey()
        let message = "Taproot transaction".data(using: .utf8)!
        let hash = cryptoService.sha256(message)
        
        // Create Schnorr signature
        let schnorrSig = cryptoService.signSchnorr(hash, with: privateKey)
        XCTAssertNotNil(schnorrSig)
        XCTAssertEqual(schnorrSig?.count, 64) // Schnorr signatures are always 64 bytes
    }
    
    func testXOnlyPublicKey() {
        let privateKey = cryptoService.generatePrivateKey()
        
        let xOnlyPubKey = cryptoService.getXOnlyPublicKey(from: privateKey)
        XCTAssertNotNil(xOnlyPubKey)
        XCTAssertEqual(xOnlyPubKey?.count, 32) // X-only public keys are 32 bytes
    }
    
    // MARK: - Hash Function Tests
    
    func testHashFunctions() {
        let data = "bitcoin".data(using: .utf8)!
        
        // Test SHA256
        let sha256Hash = cryptoService.sha256(data)
        XCTAssertEqual(sha256Hash.count, 32)
        
        // Test double SHA256 (hash256)
        let hash256Result = cryptoService.hash256(data)
        XCTAssertEqual(hash256Result.count, 32)
        XCTAssertNotEqual(sha256Hash, hash256Result)
        
        // Test RIPEMD160
        let ripemd160Hash = cryptoService.ripemd160(data)
        XCTAssertEqual(ripemd160Hash.count, 20)
        
        // Test hash160 (SHA256 + RIPEMD160)
        let hash160Result = cryptoService.hash160(data)
        XCTAssertEqual(hash160Result.count, 20)
    }
    
    // MARK: - Performance Tests
    
    func testKeyGenerationPerformance() {
        measure {
            for _ in 0..<100 {
                let privateKey = cryptoService.generatePrivateKey()
                _ = cryptoService.derivePublicKey(from: privateKey, compressed: true)
            }
        }
    }
    
    func testSigningPerformance() {
        let privateKey = cryptoService.generatePrivateKey()
        let hash = cryptoService.sha256("test".data(using: .utf8)!)
        
        measure {
            for _ in 0..<100 {
                _ = cryptoService.signTransactionHash(hash, with: privateKey)
            }
        }
    }
}

// Helper extension for tests
extension Data {
    init(hex: String) {
        var hexString = hex
        if hexString.hasPrefix("0x") {
            hexString = String(hexString.dropFirst(2))
        }
        
        var data = Data()
        for i in stride(from: 0, to: hexString.count, by: 2) {
            let startIndex = hexString.index(hexString.startIndex, offsetBy: i)
            let endIndex = hexString.index(startIndex, offsetBy: 2)
            let byteString = hexString[startIndex..<endIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
        }
        self = data
    }
    
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}