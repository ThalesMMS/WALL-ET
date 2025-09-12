import Foundation
import CoreData

extension TransactionEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionEntity> {
        return NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
    }
    
    @NSManaged public var txid: String?
    @NSManaged public var rawTx: Data?
    @NSManaged public var amount: Int64
    @NSManaged public var fee: Int64
    @NSManaged public var confirmations: Int32
    @NSManaged public var blockHeight: Int32
    @NSManaged public var timestamp: Date?
    @NSManaged public var type: String?
    @NSManaged public var status: String?
    @NSManaged public var memo: String?
    @NSManaged public var fromAddress: String?
    @NSManaged public var toAddress: String?
    @NSManaged public var wallet: WalletEntity?
    @NSManaged public var inputs: NSSet?
    @NSManaged public var outputs: NSSet?
}

// MARK: Generated accessors for inputs
extension TransactionEntity {
    
    @objc(addInputsObject:)
    @NSManaged public func addToInputs(_ value: TransactionInputEntity)
    
    @objc(removeInputsObject:)
    @NSManaged public func removeFromInputs(_ value: TransactionInputEntity)
    
    @objc(addInputs:)
    @NSManaged public func addToInputs(_ values: NSSet)
    
    @objc(removeInputs:)
    @NSManaged public func removeFromInputs(_ values: NSSet)
}

// MARK: Generated accessors for outputs
extension TransactionEntity {
    
    @objc(addOutputsObject:)
    @NSManaged public func addToOutputs(_ value: TransactionOutputEntity)
    
    @objc(removeOutputsObject:)
    @NSManaged public func removeFromOutputs(_ value: TransactionOutputEntity)
    
    @objc(addOutputs:)
    @NSManaged public func addToOutputs(_ values: NSSet)
    
    @objc(removeOutputs:)
    @NSManaged public func removeFromOutputs(_ values: NSSet)
}