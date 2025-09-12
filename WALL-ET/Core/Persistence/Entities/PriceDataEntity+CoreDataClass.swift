import Foundation
import CoreData

@objc(PriceDataEntity)
public class PriceDataEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: PriceDataEntity.entity(), insertInto: context)
        self.timestamp = Date()
    }
}