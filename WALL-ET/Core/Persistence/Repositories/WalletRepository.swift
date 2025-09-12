import Foundation
import CoreData
import Combine

class WalletRepository {
    
    private let coreDataStack: CoreDataStack
    private let context: NSManagedObjectContext
    
    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
        self.context = coreDataStack.viewContext
    }
    
    // MARK: - Wallet Operations
    
    func createWallet(name: String, type: String, derivationPath: String?, network: String) -> WalletEntity {
        let wallet = WalletEntity(context: context)
        wallet.name = name
        wallet.type = type
        wallet.derivationPath = derivationPath
        wallet.network = network
        wallet.isActive = false
        
        save()
        return wallet
    }
    
    func getActiveWallet() -> WalletEntity? {
        let request = WalletEntity.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == true")
        request.fetchLimit = 1
        
        do {
            return try context.fetch(request).first
        } catch {
            print("Failed to fetch active wallet: \(error)")
            return nil
        }
    }
    
    func getAllWallets() -> [WalletEntity] {
        let request = WalletEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch wallets: \(error)")
            return []
        }
    }
    
    func setActiveWallet(_ wallet: WalletEntity) {
        // Deactivate all wallets
        getAllWallets().forEach { $0.isActive = false }
        
        // Activate selected wallet
        wallet.isActive = true
        wallet.update()
        
        save()
    }
    
    func deleteWallet(_ wallet: WalletEntity) {
        context.delete(wallet)
        save()
    }
    
    // MARK: - Address Operations
    
    func addAddress(to wallet: WalletEntity, address: String, type: String, index: Int32, isChange: Bool) -> AddressEntity {
        let addressEntity = AddressEntity(context: context)
        addressEntity.address = address
        addressEntity.type = type
        addressEntity.derivationIndex = index
        addressEntity.isChange = isChange
        addressEntity.createdAt = Date()
        addressEntity.wallet = wallet
        
        wallet.addToAddresses(addressEntity)
        wallet.update()
        
        save()
        return addressEntity
    }
    
    func getAddresses(for wallet: WalletEntity, isChange: Bool? = nil) -> [AddressEntity] {
        let request = AddressEntity.fetchRequest()
        
        var predicates = [NSPredicate(format: "wallet == %@", wallet)]
        if let isChange = isChange {
            predicates.append(NSPredicate(format: "isChange == %@", NSNumber(value: isChange)))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "derivationIndex", ascending: true)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch addresses: \(error)")
            return []
        }
    }
    
    func updateAddressBalance(_ address: AddressEntity, balance: Int64, unconfirmedBalance: Int64) {
        address.balance = balance
        address.unconfirmedBalance = unconfirmedBalance
        
        if balance > 0 || unconfirmedBalance > 0 {
            address.isUsed = true
        }
        
        save()
    }
    
    // MARK: - Transaction Operations
    
    func saveTransaction(
        wallet: WalletEntity,
        txid: String,
        amount: Int64,
        fee: Int64,
        type: String,
        status: String,
        fromAddress: String? = nil,
        toAddress: String? = nil,
        memo: String? = nil
    ) -> TransactionEntity {
        let transaction = TransactionEntity(context: context)
        transaction.txid = txid
        transaction.amount = amount
        transaction.fee = fee
        transaction.type = type
        transaction.status = status
        transaction.fromAddress = fromAddress
        transaction.toAddress = toAddress
        transaction.memo = memo
        transaction.timestamp = Date()
        transaction.wallet = wallet
        
        wallet.addToTransactions(transaction)
        wallet.update()
        
        save()
        return transaction
    }
    
    func getTransactions(for wallet: WalletEntity, limit: Int? = nil) -> [TransactionEntity] {
        let request = TransactionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "wallet == %@", wallet)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        if let limit = limit {
            request.fetchLimit = limit
        }
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch transactions: \(error)")
            return []
        }
    }
    
    func updateTransactionConfirmations(_ transaction: TransactionEntity, confirmations: Int32, blockHeight: Int32?) {
        transaction.confirmations = confirmations
        transaction.blockHeight = blockHeight ?? 0
        
        if confirmations >= 6 {
            transaction.status = "confirmed"
        } else if confirmations > 0 {
            transaction.status = "confirming"
        }
        
        save()
    }
    
    // MARK: - UTXO Operations
    
    func saveUTXO(
        address: AddressEntity,
        txid: String,
        vout: Int32,
        amount: Int64,
        scriptPubKey: Data
    ) -> UTXOEntity {
        let utxo = UTXOEntity(context: context)
        utxo.txid = txid
        utxo.vout = vout
        utxo.amount = amount
        utxo.scriptPubKey = scriptPubKey
        utxo.address = address
        
        address.addToUtxos(utxo)
        
        save()
        return utxo
    }
    
    func getUTXOs(for address: AddressEntity, unspentOnly: Bool = true) -> [UTXOEntity] {
        let request = UTXOEntity.fetchRequest()
        
        var predicates = [NSPredicate(format: "address == %@", address)]
        if unspentOnly {
            predicates.append(NSPredicate(format: "isSpent == false"))
        }
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        
        do {
            return try context.fetch(request)
        } catch {
            print("Failed to fetch UTXOs: \(error)")
            return []
        }
    }
    
    func markUTXOAsSpent(_ utxo: UTXOEntity, spentBy: String) {
        utxo.isSpent = true
        utxo.spentTxid = spentBy
        save()
    }
    
    // MARK: - Helper Methods
    
    private func save() {
        coreDataStack.save(context: context)
    }
    
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        coreDataStack.performBackgroundTask(block)
    }
}