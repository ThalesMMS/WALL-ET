import Foundation
import LocalAuthentication
import Combine
import UIKit

class AuthenticationManager: ObservableObject {
    
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var biometricType: BiometricAuthService.BiometricType = .none
    
    private let biometricService = BiometricAuthService()
    private let secureStorage = SecureStorageService.shared
    private let settingsRepository = SettingsRepository()
    
    private var authenticationTimer: Timer?
    private let sessionTimeout: TimeInterval = 300
    
    init() {
        checkBiometricAvailability()
        setupSessionManagement()
    }
    
    private func checkBiometricAvailability() {
        biometricType = biometricService.biometricType
    }
    
    private func setupSessionManagement() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        if !isAuthenticated && shouldRequireAuthentication() {
            authenticate()
        }
        startSessionTimer()
    }
    
    @objc private func appWillResignActive() {
        stopSessionTimer()
    }
    
    private func startSessionTimer() {
        stopSessionTimer()
        authenticationTimer = Timer.scheduledTimer(withTimeInterval: sessionTimeout, repeats: false) { [weak self] _ in
            self?.sessionExpired()
        }
    }
    
    private func stopSessionTimer() {
        authenticationTimer?.invalidate()
        authenticationTimer = nil
    }
    
    private func sessionExpired() {
        isAuthenticated = false
        authenticate()
    }
    
    private func shouldRequireAuthentication() -> Bool {
        let biometricEnabled = settingsRepository.getBoolSetting(
            key: SettingsRepository.SettingsKey.biometricEnabled,
            defaultValue: true
        )
        
        let pinEnabled = settingsRepository.getBoolSetting(
            key: SettingsRepository.SettingsKey.pinEnabled,
            defaultValue: false
        )
        
        return biometricEnabled || pinEnabled
    }
    
    func authenticate(completion: ((Bool) -> Void)? = nil) {
        let biometricEnabled = settingsRepository.getBoolSetting(
            key: SettingsRepository.SettingsKey.biometricEnabled,
            defaultValue: true
        )
        
        if biometricEnabled && biometricService.isBiometricAvailable() {
            authenticateWithBiometric(completion: completion)
        } else if settingsRepository.getBoolSetting(key: SettingsRepository.SettingsKey.pinEnabled) {
            authenticateWithPIN(completion: completion)
        } else {
            isAuthenticated = true
            completion?(true)
        }
    }
    
    func authenticateWithBiometric(completion: ((Bool) -> Void)? = nil) {
        let reason = "Authenticate to access your wallet"
        
        biometricService.authenticate(reason: reason) { [weak self] result in
            switch result {
            case .success:
                self?.isAuthenticated = true
                self?.startSessionTimer()
                completion?(true)
            case .failure(let error):
                print("Biometric authentication failed: \(error)")
                self?.isAuthenticated = false
                
                if self?.settingsRepository.getBoolSetting(key: SettingsRepository.SettingsKey.pinEnabled) ?? false {
                    self?.authenticateWithPIN(completion: completion)
                } else {
                    completion?(false)
                }
            }
        }
    }
    
    func authenticateWithPIN(pin: String? = nil, completion: ((Bool) -> Void)? = nil) {
        if let pin = pin {
            let isValid = secureStorage.verifyPIN(pin)
            isAuthenticated = isValid

            if isValid {
                startSessionTimer()
            }

            completion?(isValid)
        } else {
            completion?(false)
        }
    }

    var isPINConfigured: Bool {
        settingsRepository.getBoolSetting(
            key: SettingsRepository.SettingsKey.pinEnabled,
            defaultValue: false
        )
    }
    
    func setPIN(_ pin: String, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            try secureStorage.setPIN(pin)
            settingsRepository.saveSetting(
                key: SettingsRepository.SettingsKey.pinEnabled,
                value: "true"
            )
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
    func removePIN() {
        settingsRepository.saveSetting(
            key: SettingsRepository.SettingsKey.pinEnabled,
            value: "false"
        )
    }
    
    func enableBiometric(_ enable: Bool) {
        settingsRepository.saveSetting(
            key: SettingsRepository.SettingsKey.biometricEnabled,
            value: enable ? "true" : "false"
        )
    }
    
    func logout() {
        isAuthenticated = false
        stopSessionTimer()
    }
}