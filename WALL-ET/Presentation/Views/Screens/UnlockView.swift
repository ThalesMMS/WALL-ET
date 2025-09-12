import SwiftUI
import LocalAuthentication

struct UnlockView: View {
    @Binding var isLocked: Bool
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)
            
            Text("WALL-ET")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Bitcoin Wallet")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 20) {
                SecureField("Enter Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        unlock()
                    }
                
                HStack(spacing: 15) {
                    Button(action: authenticateWithBiometrics) {
                        Label("Face ID", systemImage: "faceid")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    
                    Button(action: unlock) {
                        Text("Unlock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
        .padding()
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            authenticateWithBiometrics()
        }
    }
    
    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Unlock your wallet"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        isLocked = false
                    } else if let error = authenticationError {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    private func unlock() {
        // TODO: Implement actual password verification
        // For now, any non-empty password unlocks
        if !password.isEmpty {
            isLocked = false
        } else {
            errorMessage = "Please enter a password"
            showError = true
        }
    }
}