import Foundation
import CoreData

class SettingsRepository {
    
    private let coreDataStack: CoreDataStack
    private let context: NSManagedObjectContext
    
    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.context = coreDataStack.viewContext
    }
    
    func saveSetting(key: String, value: String, type: String = "string") {
        // Check if setting exists
        if let existing = getSetting(key: key) {
            existing.value = value
            existing.updatedAt = Date()
        } else {
            let setting = SettingsEntity(context: context)
            setting.key = key
            setting.value = value
            setting.type = type
            setting.updatedAt = Date()
        }
        
        save()
    }
    
    func getSetting(key: String) -> SettingsEntity? {
        let request = SettingsEntity.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch setting: \(error)")
            return nil
        }
    }
    
    func getSettingValue(key: String, defaultValue: String? = nil) -> String? {
        return getSetting(key: key)?.value ?? defaultValue
    }
    
    func getBoolSetting(key: String, defaultValue: Bool = false) -> Bool {
        guard let value = getSettingValue(key: key) else { return defaultValue }
        return value == "true" || value == "1"
    }
    
    func getIntSetting(key: String, defaultValue: Int = 0) -> Int {
        guard let value = getSettingValue(key: key),
              let intValue = Int(value) else { return defaultValue }
        return intValue
    }
    
    func getDoubleSetting(key: String, defaultValue: Double = 0.0) -> Double {
        guard let value = getSettingValue(key: key),
              let doubleValue = Double(value) else { return defaultValue }
        return doubleValue
    }
    
    func deleteSetting(key: String) {
        if let setting = getSetting(key: key) {
            context.delete(setting)
            save()
        }
    }
    
    func getAllSettings() -> [SettingsEntity] {
        let request = SettingsEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "key", ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch all settings: \(error)")
            return []
        }
    }
    
    private func save() {
        coreDataStack.save(context: context)
    }
}

// MARK: - Settings Keys
extension SettingsRepository {
    enum SettingsKey {
        static let defaultCurrency = "default_currency"
        static let biometricEnabled = "biometric_enabled"
        static let pinEnabled = "pin_enabled"
        static let networkType = "network_type"
        static let electrumServer = "electrum_server"
        static let priceProvider = "price_provider"
        static let feeLevel = "fee_level"
        static let showTestnetWarning = "show_testnet_warning"
        static let lastBackupDate = "last_backup_date"
        static let addressType = "default_address_type"
        static let hideBalance = "hide_balance"
        static let notificationsEnabled = "notifications_enabled"
        static let priceAlertHigh = "price_alert_high"
        static let priceAlertLow = "price_alert_low"
    }
}