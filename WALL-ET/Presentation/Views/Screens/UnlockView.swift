import SwiftUI
import LocalAuthentication

struct UnlockView: View {
    @Binding var isLocked: Bool
    @StateObject private var viewModel: UnlockViewModel

    init(isLocked: Binding<Bool>, viewModel: UnlockViewModel = UnlockViewModel()) {
        self._isLocked = isLocked
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
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
                SecureField("Enter PIN", text: $viewModel.password)
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
                    .disabled(viewModel.password.isEmpty)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
        .padding()
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
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
                        viewModel.presentError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func unlock() {
        viewModel.unlock { success in
            if success {
                isLocked = false
            }
        }
    }
}