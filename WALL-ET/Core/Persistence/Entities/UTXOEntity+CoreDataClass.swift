import Foundation
import CoreData

@objc(UTXOEntity)
public class UTXOEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: UTXOEntity.entity(), insertInto: context)
        self.isSpent = false
        self.confirmations = 0
    }
}