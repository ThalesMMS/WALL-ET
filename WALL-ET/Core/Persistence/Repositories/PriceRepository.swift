import Foundation
import CoreData

class PriceRepository {
    
    private let coreDataStack: CoreDataStack
    private let context: NSManagedObjectContext
    
    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.context = coreDataStack.viewContext
    }
    
    func savePriceData(
        currency: String,
        price: Double,
        change24h: Double,
        changePercentage24h: Double,
        volume24h: Double,
        marketCap: Double,
        provider: String
    ) -> PriceDataEntity {
        // Delete old price data for this currency
        deleteOldPriceData(for: currency)
        
        let priceData = PriceDataEntity(context: context)
        priceData.currency = currency
        priceData.price = price
        priceData.change24h = change24h
        priceData.changePercentage24h = changePercentage24h
        priceData.volume24h = volume24h
        priceData.marketCap = marketCap
        priceData.provider = provider
        priceData.timestamp = Date()
        
        save()
        return priceData
    }
    
    func getLatestPrice(for currency: String) -> PriceDataEntity? {
        let request = PriceDataEntity.fetchRequest()
        request.predicate = NSPredicate(format: "currency == %@", currency)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch price data: \(error)")
            return nil
        }
    }
    
    func getPriceHistory(for currency: String, days: Int) -> [PriceDataEntity] {
        let request = PriceDataEntity.fetchRequest()
        
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "currency == %@", currency),
            NSPredicate(format: "timestamp >= %@", startDate as NSDate)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch price history: \(error)")
            return []
        }
    }
    
    private func deleteOldPriceData(for currency: String) {
        let request = PriceDataEntity.fetchRequest()
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "currency == %@", currency),
            NSPredicate(format: "timestamp < %@", cutoffDate as NSDate)
        ])
        
        do {
            let oldPrices = try context.fetch(request)
            oldPrices.forEach { context.delete($0) }
        } catch {
            print("Failed to delete old price data: \(error)")
        }
    }
    
    private func save() {
        coreDataStack.save(context: context)
    }
}