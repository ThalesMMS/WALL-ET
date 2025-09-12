import Foundation
import UserNotifications
import Combine
import UIKit

class NotificationService: NSObject {
    
    static let shared = NotificationService()
    private let notificationCenter = UNUserNotificationCenter.current()
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
        notificationCenter.delegate = self
        setupNotificationObservers()
    }
    
    // MARK: - Setup
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                completion(granted)
            }
            
            if granted {
                self.registerForRemoteNotifications()
            }
        }
    }
    
    private func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    private func setupNotificationObservers() {
        // Listen for transaction updates
        ElectrumService.shared.transactionUpdatePublisher
            .sink { [weak self] update in
                self?.handleTransactionUpdate(update)
            }
            .store(in: &cancellables)
        
        // Listen for price alerts
        PriceDataService.shared.priceUpdatePublisher
            .sink { [weak self] priceData in
                self?.checkPriceAlerts(priceData)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Transaction Notifications
    
    private func handleTransactionUpdate(_ update: ElectrumService.TransactionUpdate) {
        if update.confirmations == 0 {
            // New unconfirmed transaction
            sendTransactionNotification(
                title: "New Transaction",
                body: "Incoming transaction detected (unconfirmed)",
                txid: update.txid,
                type: .pending
            )
        } else if update.confirmations == 1 {
            // First confirmation
            sendTransactionNotification(
                title: "Transaction Confirmed",
                body: "Your transaction has received its first confirmation",
                txid: update.txid,
                type: .confirmed
            )
        } else if update.confirmations == 6 {
            // Fully confirmed
            sendTransactionNotification(
                title: "Transaction Complete",
                body: "Your transaction is now fully confirmed",
                txid: update.txid,
                type: .complete
            )
        }
    }
    
    func sendTransactionNotification(
        title: String,
        body: String,
        txid: String,
        type: TransactionNotificationType
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "TRANSACTION"
        content.userInfo = [
            "txid": txid,
            "type": type.rawValue
        ]
        
        // Add action buttons
        switch type {
        case .pending:
            content.badge = NSNumber(value: 1)
        case .confirmed:
            content.badge = NSNumber(value: 0)
        case .complete:
            content.badge = NSNumber(value: 0)
            content.sound = UNNotificationSound(named: UNNotificationSoundName("success.mp3"))
        }
        
        let request = UNNotificationRequest(
            identifier: "tx-\(txid)-\(type.rawValue)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
    
    // MARK: - Price Alerts
    
    private func checkPriceAlerts(_ priceData: PriceData) {
        let settingsRepo = SettingsRepository()
        
        let highAlert = settingsRepo.getDoubleSetting(
            key: SettingsRepository.SettingsKey.priceAlertHigh,
            defaultValue: 0
        )
        
        let lowAlert = settingsRepo.getDoubleSetting(
            key: SettingsRepository.SettingsKey.priceAlertLow,
            defaultValue: 0
        )
        
        if highAlert > 0 && priceData.price >= highAlert {
            sendPriceAlert(
                title: "Price Alert 📈",
                body: "Bitcoin has reached $\(Int(priceData.price))",
                price: priceData.price,
                type: .high
            )
        }
        
        if lowAlert > 0 && priceData.price <= lowAlert {
            sendPriceAlert(
                title: "Price Alert 📉",
                body: "Bitcoin has dropped to $\(Int(priceData.price))",
                price: priceData.price,
                type: .low
            )
        }
    }
    
    func sendPriceAlert(
        title: String,
        body: String,
        price: Double,
        type: PriceAlertType
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "PRICE_ALERT"
        content.userInfo = [
            "price": price,
            "type": type.rawValue
        ]
        
        let request = UNNotificationRequest(
            identifier: "price-\(type.rawValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Scheduled Notifications
    
    func scheduleBackupReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Backup Reminder"
        content.body = "It's been 30 days since your last backup. Keep your wallet safe!"
        content.sound = .default
        content.categoryIdentifier = "BACKUP_REMINDER"
        
        // Schedule for 30 days from now
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 30 * 24 * 60 * 60,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "backup-reminder",
            content: content,
            trigger: trigger
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Notification Categories
    
    func setupNotificationCategories() {
        // Transaction category
        let viewAction = UNNotificationAction(
            identifier: "VIEW_TRANSACTION",
            title: "View Details",
            options: .foreground
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )
        
        let transactionCategory = UNNotificationCategory(
            identifier: "TRANSACTION",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Price alert category
        let adjustAction = UNNotificationAction(
            identifier: "ADJUST_ALERTS",
            title: "Adjust Alerts",
            options: .foreground
        )
        
        let priceCategory = UNNotificationCategory(
            identifier: "PRICE_ALERT",
            actions: [adjustAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        // Backup reminder category
        let backupNowAction = UNNotificationAction(
            identifier: "BACKUP_NOW",
            title: "Backup Now",
            options: .foreground
        )
        
        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Remind in 7 Days",
            options: []
        )
        
        let backupCategory = UNNotificationCategory(
            identifier: "BACKUP_REMINDER",
            actions: [backupNowAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            transactionCategory,
            priceCategory,
            backupCategory
        ])
    }
    
    // MARK: - Types
    
    enum TransactionNotificationType: String {
        case pending = "pending"
        case confirmed = "confirmed"
        case complete = "complete"
    }
    
    enum PriceAlertType: String {
        case high = "high"
        case low = "low"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "VIEW_TRANSACTION":
            if let txid = userInfo["txid"] as? String {
                // Navigate to transaction details
                NotificationCenter.default.post(
                    name: .navigateToTransaction,
                    object: nil,
                    userInfo: ["txid": txid]
                )
            }
            
        case "ADJUST_ALERTS":
            // Navigate to settings
            NotificationCenter.default.post(
                name: .navigateToSettings,
                object: nil
            )
            
        case "BACKUP_NOW":
            // Navigate to backup
            NotificationCenter.default.post(
                name: .navigateToBackup,
                object: nil
            )
            
        case "REMIND_LATER":
            // Schedule reminder for 7 days
            scheduleBackupReminder()
            
        default:
            break
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToTransaction = Notification.Name("navigateToTransaction")
    static let navigateToSettings = Notification.Name("navigateToSettings")
    static let navigateToBackup = Notification.Name("navigateToBackup")
}