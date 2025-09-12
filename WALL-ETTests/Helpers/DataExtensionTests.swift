import XCTest
@testable import WALL_ET

extension Data {
    init(hex: String) {
        var hexString = hex
        if hexString.hasPrefix("0x") {
            hexString = String(hexString.dropFirst(2))
        }
        
        if hexString.count % 2 != 0 {
            hexString = "0" + hexString
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

class DataExtensionTests: XCTestCase {
    
    func testHexInitialization() {
        let hexString = "deadbeef"
        let data = Data(hex: hexString)
        
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data[0], 0xde)
        XCTAssertEqual(data[1], 0xad)
        XCTAssertEqual(data[2], 0xbe)
        XCTAssertEqual(data[3], 0xef)
    }
    
    func testHexString() {
        let data = Data([0xde, 0xad, 0xbe, 0xef])
        let hexString = data.hexString
        
        XCTAssertEqual(hexString, "deadbeef")
    }
    
    func testRoundTrip() {
        let original = "0123456789abcdef"
        let data = Data(hex: original)
        let result = data.hexString
        
        XCTAssertEqual(original, result)
    }
}