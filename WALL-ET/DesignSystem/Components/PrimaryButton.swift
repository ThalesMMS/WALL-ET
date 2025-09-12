import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(Constants.UI.cornerRadius)
        }
        .disabled(isDisabled || isLoading)
    }
    
    private var backgroundColor: Color {
        if isDisabled || isLoading {
            return Color.gray.opacity(0.3)
        }
        return Color.Wallet.bitcoinOrange
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.clear)
                .foregroundColor(foregroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                        .stroke(borderColor, lineWidth: 2)
                )
        }
        .disabled(isDisabled)
    }
    
    private var foregroundColor: Color {
        isDisabled ? Color.gray : Color.Wallet.bitcoinOrange
    }
    
    private var borderColor: Color {
        isDisabled ? Color.gray.opacity(0.3) : Color.Wallet.bitcoinOrange
    }
}

#Preview {
    VStack(spacing: 20) {
        PrimaryButton(title: "Send Bitcoin", action: {})
        PrimaryButton(title: "Loading...", action: {}, isLoading: true)
        PrimaryButton(title: "Disabled", action: {}, isDisabled: true)
        SecondaryButton(title: "Receive", action: {})
    }
    .padding()
}