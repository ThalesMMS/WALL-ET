import XCTest
@testable import WALL_ET

class MnemonicServiceTests: XCTestCase {
    
    var sut: MnemonicService!
    
    override func setUp() {
        super.setUp()
        sut = MnemonicService.shared
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testGenerateMnemonic12Words() throws {
        let mnemonic = try sut.generateMnemonic(strength: .words12)
        let words = mnemonic.split(separator: " ")
        
        XCTAssertEqual(words.count, 12)
        XCTAssertTrue(try sut.validateMnemonic(mnemonic))
    }
    
    func testGenerateMnemonic24Words() throws {
        let mnemonic = try sut.generateMnemonic(strength: .words24)
        let words = mnemonic.split(separator: " ")
        
        XCTAssertEqual(words.count, 24)
        XCTAssertTrue(try sut.validateMnemonic(mnemonic))
    }
    
    func testValidateMnemonic() {
        let validMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let invalidMnemonic = "invalid word sequence that is not valid"
        
        XCTAssertTrue(try! sut.validateMnemonic(validMnemonic))
        XCTAssertThrowsError(try sut.validateMnemonic(invalidMnemonic))
    }
    
    func testMnemonicToSeed() {
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let seed = sut.mnemonicToSeed(mnemonic)
        
        XCTAssertEqual(seed.count, 64)
        
        let expectedSeed = Data(hex: "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4")
        XCTAssertEqual(seed, expectedSeed)
    }
    
    func testMnemonicToSeedWithPassphrase() {
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let passphrase = "TREZOR"
        let seed = sut.mnemonicToSeed(mnemonic, passphrase: passphrase)
        
        XCTAssertEqual(seed.count, 64)
        
        let expectedSeed = Data(hex: "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04")
        XCTAssertEqual(seed, expectedSeed)
    }
    
    func testGenerateMasterKey() {
        let seed = Data(hex: "000102030405060708090a0b0c0d0e0f")
        let masterKey = sut.generateMasterKey(from: seed)
        
        XCTAssertEqual(masterKey.privateKey.count, 32)
        XCTAssertEqual(masterKey.chainCode.count, 32)
        XCTAssertEqual(masterKey.depth, 0)
        XCTAssertEqual(masterKey.index, 0)
    }
    
    func testDeriveKey() {
        let seed = Data(hex: "000102030405060708090a0b0c0d0e0f")
        let masterKey = sut.generateMasterKey(from: seed)
        
        let childKey = sut.deriveKey(from: masterKey, at: 0, hardened: true)
        
        XCTAssertEqual(childKey.depth, 1)
        XCTAssertEqual(childKey.index, 0x80000000)
        XCTAssertNotEqual(childKey.privateKey, masterKey.privateKey)
    }
    
    func testDeriveAddress() {
        let seed = Data(hex: "000102030405060708090a0b0c0d0e0f")
        
        let (privateKey, address) = sut.deriveAddress(
            from: seed,
            path: "m/84'/0'/0'/0/0",
            network: .testnet
        )
        
        XCTAssertEqual(privateKey.count, 32)
        XCTAssertTrue(address.starts(with: "tb1"))
    }
    
    func testEntropyToMnemonic() throws {
        let entropy = Data(hex: "00000000000000000000000000000000")
        let mnemonic = try sut.mnemonicFromEntropy(entropy)
        
        let expectedMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        XCTAssertEqual(mnemonic, expectedMnemonic)
    }

    func testKnownMnemonicFirstAddress() {
        // Provided vector (mainnet): first m/84'/0'/0'/0/0 address
        let mnemonic = "twist outside favorite taxi bracket admit unveil around demand number mixture civil diesel enhance hammer meat then replace master carpet farm viable toast muscle"
        let seed = sut.mnemonicToSeed(mnemonic)
        let (_, address) = sut.deriveAddress(from: seed, path: "m/84'/0'/0'/0/0", network: .mainnet)
        NSLog("Derived address: %@", address)
        let expected = "bc1q249u4yzmkas7jk7cne0kqwr8ky8097ttxlmlrz"
        if address != expected {
            XCTFail("Derived address: \(address)")
        }
    }
}
