import XCTest
@testable import WALL_ET

class SecureStorageServiceTests: XCTestCase {
    
    var sut: SecureStorageService!
    
    override func setUp() {
        super.setUp()
        sut = SecureStorageService.shared
    }
    
    override func tearDown() {
        try? sut.wipeAllData()
        sut = nil
        super.tearDown()
    }
    
    func testSaveAndRetrieveSeed() throws {
        let seed = Data(repeating: 0xAB, count: 64)
        
        try sut.saveSeed(seed, requiresBiometric: false)
        let retrievedSeed = try sut.retrieveSeed()
        
        XCTAssertEqual(seed, retrievedSeed)
    }
    
    func testSaveAndRetrieveWalletData() throws {
        struct TestWallet: Codable, Equatable {
            let id: String
            let name: String
            let balance: Int64
        }
        
        let wallet = TestWallet(id: "test-id", name: "Test Wallet", balance: 100000)
        
        try sut.saveWalletData(wallet, key: "test-wallet")
        let retrieved = try sut.retrieveWalletData(TestWallet.self, key: "test-wallet")
        
        XCTAssertEqual(wallet, retrieved)
    }
    
    func testPINManagement() throws {
        let pin = "123456"
        
        try sut.setPIN(pin)
        
        XCTAssertTrue(sut.verifyPIN(pin))
        XCTAssertFalse(sut.verifyPIN("wrong-pin"))
        XCTAssertFalse(sut.verifyPIN("000000"))
    }
    
    func testExportAndImportBackup() throws {
        let seed = Data(repeating: 0xCD, count: 64)
        let password = "backup-password-123"
        
        try sut.saveSeed(seed, requiresBiometric: false)
        
        let backupData = try sut.exportEncryptedBackup(password: password)
        
        try sut.wipeAllData()
        
        XCTAssertThrowsError(try sut.retrieveSeed())
        
        try sut.importEncryptedBackup(backupData, password: password)
        
        let retrievedSeed = try sut.retrieveSeed()
        XCTAssertEqual(seed, retrievedSeed)
    }
    
    func testImportBackupWithWrongPassword() throws {
        let seed = Data(repeating: 0xEF, count: 64)
        let correctPassword = "correct-password"
        let wrongPassword = "wrong-password"
        
        try sut.saveSeed(seed, requiresBiometric: false)
        
        let backupData = try sut.exportEncryptedBackup(password: correctPassword)
        
        try sut.wipeAllData()
        
        XCTAssertThrowsError(try sut.importEncryptedBackup(backupData, password: wrongPassword))
    }
    
    func testDeleteSeed() throws {
        let seed = Data(repeating: 0x12, count: 64)
        
        try sut.saveSeed(seed, requiresBiometric: false)
        
        XCTAssertNoThrow(try sut.retrieveSeed())
        
        try sut.deleteSeed()
        
        XCTAssertThrowsError(try sut.retrieveSeed())
    }
    
    func testEncryptionService() throws {
        let encryptionService = EncryptionService()
        let plaintext = "This is a secret message".data(using: .utf8)!
        
        let encrypted = try encryptionService.encrypt(plaintext)
        let decrypted = try encryptionService.decrypt(encrypted)
        
        XCTAssertNotEqual(plaintext, encrypted)
        XCTAssertEqual(plaintext, decrypted)
    }
}