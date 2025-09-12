import Foundation
import CoreData

@objc(SettingsEntity)
public class SettingsEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: SettingsEntity.entity(), insertInto: context)
        self.updatedAt = Date()
    }
}