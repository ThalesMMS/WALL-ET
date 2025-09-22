import Foundation

protocol UnlockAuthenticating {
    var isPINConfigured: Bool { get }
    func authenticateWithPIN(pin: String?, completion: ((Bool) -> Void)?)
}

final class UnlockViewModel: ObservableObject {

    @Published var password: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private let authenticator: UnlockAuthenticating

    init(authenticator: UnlockAuthenticating = AuthenticationManager.shared) {
        self.authenticator = authenticator
    }

    func unlock(completion: @escaping (Bool) -> Void) {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPassword.isEmpty else {
            presentError(message: "Please enter your PIN.")
            password = ""
            completion(false)
            return
        }

        guard authenticator.isPINConfigured else {
            presentError(message: "No PIN configured. Please set one up in Settings.")
            password = ""
            completion(false)
            return
        }

        authenticator.authenticateWithPIN(pin: trimmedPassword) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                self.password = ""

                if success {
                    self.showError = false
                    completion(true)
                } else {
                    self.presentError(message: "Incorrect PIN. Please try again.")
                    completion(false)
                }
            }
        }
    }

    func presentError(message: String) {
        errorMessage = message
        showError = true
    }
}

