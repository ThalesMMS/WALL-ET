import SwiftUI

struct BalanceCard: View {
    let btcAmount: Double
    let fiatAmount: Double
    let currencyCode: String
    var showBalance: Bool = true
    
    var body: some View {
        VStack(spacing: 8) {
            if showBalance {
                Text("\(btcAmount.toBitcoin()) BTC")
                    .bitcoinAmount()
                    .foregroundColor(Color.Wallet.primaryText)
                
                Text(fiatAmount.toCurrency(code: currencyCode))
                    .fiatAmount()
                    .foregroundColor(Color.Wallet.secondaryText)
            } else {
                Text("••••••••")
                    .bitcoinAmount()
                    .foregroundColor(Color.Wallet.primaryText)
                
                Text("••••••")
                    .fiatAmount()
                    .foregroundColor(Color.Wallet.secondaryText)
            }
        }
    }
}

struct CompactBalanceView: View {
    let btcAmount: Double
    let fiatAmount: Double
    let currencyCode: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(btcAmount.toBitcoin()) BTC")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.Wallet.primaryText)
                
                Text(fiatAmount.toCurrency(code: currencyCode))
                    .font(.system(size: 14))
                    .foregroundColor(Color.Wallet.secondaryText)
            }
            Spacer()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        BalanceCard(btcAmount: 1.23456789, fiatAmount: 45678.90, currencyCode: "USD")
        BalanceCard(btcAmount: 0.5, fiatAmount: 18500.00, currencyCode: "USD", showBalance: false)
        CompactBalanceView(btcAmount: 0.25, fiatAmount: 9250.00, currencyCode: "USD")
    }
    .padding()
}