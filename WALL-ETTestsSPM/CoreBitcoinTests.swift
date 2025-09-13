import XCTest
@testable import CoreBitcoin

final class CoreBitcoinTests: XCTestCase {
    func testRIPEMD160Vector() {
        let message = "The quick brown fox jumps over the lazy dog".data(using: .utf8)!
        let digest = RIPEMD160.hash(message)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        print("ripemd160:", hex)
        XCTAssertEqual(hex, "37f332f68db77bd9d7edd4969571ad671cf9dd3b")
    }
    func testKnownMnemonicAddress() {
        let mnemonic = "twist outside favorite taxi bracket admit unveil around demand number mixture civil diesel enhance hammer meat then replace master carpet farm viable toast muscle"
        let seed = MnemonicService.shared.mnemonicToSeed(mnemonic)
        let (priv, address) = MnemonicService.shared.deriveAddress(from: seed, path: "m/84'/0'/0'/0/0", network: .mainnet)
        func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
        if let pub = CryptoService.shared.derivePublicKey(from: priv, compressed: true) {
            print("priv:", hex(priv))
            print("pub:", hex(pub))
            let h160 = CryptoService.shared.hash160(pub)
            print("hash160:", hex(h160))
        }
        let expected = "bc1q249u4yzmkas7jk7cne0kqwr8ky8097ttxlmlrz"
        if let (_, prog) = Bech32.decode(expected) {
            print("expected program:", hex(prog))
        }
        print("Derived address:", address)
        XCTAssertEqual(address, expected)
    }
}
