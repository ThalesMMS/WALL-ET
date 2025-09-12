import Foundation
import CoreData

extension PriceDataEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PriceDataEntity> {
        return NSFetchRequest<PriceDataEntity>(entityName: "PriceDataEntity")
    }
    
    @NSManaged public var currency: String?
    @NSManaged public var price: Double
    @NSManaged public var change24h: Double
    @NSManaged public var changePercentage24h: Double
    @NSManaged public var volume24h: Double
    @NSManaged public var marketCap: Double
    @NSManaged public var timestamp: Date?
    @NSManaged public var provider: String?
}