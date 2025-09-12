import SwiftUI
import LocalAuthentication

struct BiometricButton: View {
    let action: () -> Void
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var isAnimating = false
    
    var body: some View {
        Button(action: {
            isAnimating = true
            authManager.authenticateWithBiometric { success in
                isAnimating = false
                if success {
                    action()
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Image(systemName: biometricIcon)
                    .font(.system(size: 35, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(isAnimating ? 0.85 : 1.0)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
    }
    
    private var biometricIcon: String {
        switch authManager.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "lock.shield"
        }
    }
}

struct BiometricLockView: View {
    @Binding var isUnlocked: Bool
    let onSuccess: () -> Void
    
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var showPINEntry = false
    @State private var pinEntry = ""
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 12) {
                Text("Welcome Back")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Authenticate to access your wallet")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            if !showPINEntry {
                BiometricButton {
                    withAnimation(.spring()) {
                        isUnlocked = true
                        onSuccess()
                    }
                }
                
                Button(action: {
                    withAnimation {
                        showPINEntry = true
                    }
                }) {
                    Text("Use PIN Instead")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            } else {
                PINEntryView(
                    pin: $pinEntry,
                    isSecure: true,
                    onComplete: { pin in
                        authManager.authenticateWithPIN(pin: pin) { success in
                            if success {
                                withAnimation(.spring()) {
                                    isUnlocked = true
                                    onSuccess()
                                }
                            } else {
                                errorMessage = "Incorrect PIN"
                                showError = true
                                pinEntry = ""
                            }
                        }
                    }
                )
                
                Button(action: {
                    withAnimation {
                        showPINEntry = false
                        pinEntry = ""
                    }
                }) {
                    Text("Use Biometric Instead")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .alert("Authentication Error", isPresented: $showError) {
            Button("OK") {
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if authManager.biometricType != .none {
                authManager.authenticate { success in
                    if success {
                        withAnimation(.spring()) {
                            isUnlocked = true
                            onSuccess()
                        }
                    }
                }
            }
        }
    }
}

struct PINEntryView: View {
    @Binding var pin: String
    let isSecure: Bool
    let onComplete: (String) -> Void
    
    private let maxDigits = 6
    
    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 15) {
                ForEach(0..<maxDigits, id: \.self) { index in
                    Circle()
                        .stroke(lineWidth: 2)
                        .fill(index < pin.count ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .fill(index < pin.count ? Color.blue : Color.clear)
                                .frame(width: 12, height: 12)
                        )
                }
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                ForEach(1...9, id: \.self) { number in
                    PINButton(number: String(number)) {
                        addDigit(String(number))
                    }
                }
                
                PINButton(number: "", isSpecial: true) {
                    // Empty button
                }
                .hidden()
                
                PINButton(number: "0") {
                    addDigit("0")
                }
                
                PINButton(number: "⌫", isSpecial: true) {
                    deleteDigit()
                }
            }
            .padding(.horizontal, 40)
        }
    }
    
    private func addDigit(_ digit: String) {
        guard pin.count < maxDigits else { return }
        pin.append(digit)
        
        if pin.count == maxDigits {
            onComplete(pin)
        }
    }
    
    private func deleteDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }
}

struct PINButton: View {
    let number: String
    let isSpecial: Bool
    let action: () -> Void
    
    init(number: String, isSpecial: Bool = false, action: @escaping () -> Void) {
        self.number = number
        self.isSpecial = isSpecial
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSpecial ? Color.gray.opacity(0.2) : Color.blue.opacity(0.1))
                    .frame(width: 75, height: 75)
                
                Text(number)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }
}