import Foundation
import CoreData

@objc(AddressEntity)
public class AddressEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: AddressEntity.entity(), insertInto: context)
        self.createdAt = Date()
        self.balance = 0
        self.unconfirmedBalance = 0
        self.isUsed = false
        self.isChange = false
    }
}