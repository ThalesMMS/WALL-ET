import Foundation
import CoreData

@objc(WalletEntity)
public class WalletEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: WalletEntity.entity(), insertInto: context)
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isActive = false
    }
    
    func update() {
        self.updatedAt = Date()
    }
}