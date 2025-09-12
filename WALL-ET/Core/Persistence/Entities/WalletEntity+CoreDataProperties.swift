import Foundation
import CoreData

extension WalletEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<WalletEntity> {
        return NSFetchRequest<WalletEntity>(entityName: "WalletEntity")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var type: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var isActive: Bool
    @NSManaged public var derivationPath: String?
    @NSManaged public var network: String?
    @NSManaged public var addresses: NSSet?
    @NSManaged public var transactions: NSSet?
}

// MARK: Generated accessors for addresses
extension WalletEntity {
    
    @objc(addAddressesObject:)
    @NSManaged public func addToAddresses(_ value: AddressEntity)
    
    @objc(removeAddressesObject:)
    @NSManaged public func removeFromAddresses(_ value: AddressEntity)
    
    @objc(addAddresses:)
    @NSManaged public func addToAddresses(_ values: NSSet)
    
    @objc(removeAddresses:)
    @NSManaged public func removeFromAddresses(_ values: NSSet)
}

// MARK: Generated accessors for transactions
extension WalletEntity {
    
    @objc(addTransactionsObject:)
    @NSManaged public func addToTransactions(_ value: TransactionEntity)
    
    @objc(removeTransactionsObject:)
    @NSManaged public func removeFromTransactions(_ value: TransactionEntity)
    
    @objc(addTransactions:)
    @NSManaged public func addToTransactions(_ values: NSSet)
    
    @objc(removeTransactions:)
    @NSManaged public func removeFromTransactions(_ values: NSSet)
}