import Foundation
import CoreData

extension AddressEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AddressEntity> {
        return NSFetchRequest<AddressEntity>(entityName: "AddressEntity")
    }
    
    @NSManaged public var address: String?
    @NSManaged public var derivationIndex: Int32
    @NSManaged public var type: String?
    @NSManaged public var label: String?
    @NSManaged public var balance: Int64
    @NSManaged public var unconfirmedBalance: Int64
    @NSManaged public var isUsed: Bool
    @NSManaged public var isChange: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var wallet: WalletEntity?
    @NSManaged public var utxos: NSSet?
}

// MARK: Generated accessors for utxos
extension AddressEntity {
    
    @objc(addUtxosObject:)
    @NSManaged public func addToUtxos(_ value: UTXOEntity)
    
    @objc(removeUtxosObject:)
    @NSManaged public func removeFromUtxos(_ value: UTXOEntity)
    
    @objc(addUtxos:)
    @NSManaged public func addToUtxos(_ values: NSSet)
    
    @objc(removeUtxos:)
    @NSManaged public func removeFromUtxos(_ values: NSSet)
}