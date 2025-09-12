import Foundation
import CoreData

extension SettingsEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SettingsEntity> {
        return NSFetchRequest<SettingsEntity>(entityName: "SettingsEntity")
    }
    
    @NSManaged public var key: String?
    @NSManaged public var value: String?
    @NSManaged public var type: String?
    @NSManaged public var updatedAt: Date?
}