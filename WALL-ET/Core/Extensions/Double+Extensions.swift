import Foundation

extension Double {
    func toBitcoin() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 8
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        
        return formatter.string(from: NSNumber(value: self)) ?? "0.00"
    }
    
    func toCurrency(code: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }
    
    func satoshisToBitcoin() -> Double {
        return self / Double(Constants.Bitcoin.satoshisPerBitcoin)
    }
    
    func bitcoinToSatoshis() -> Int64 {
        return Int64(self * Double(Constants.Bitcoin.satoshisPerBitcoin))
    }
}