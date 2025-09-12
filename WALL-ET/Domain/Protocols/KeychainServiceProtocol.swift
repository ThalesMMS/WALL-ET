import Foundation

protocol KeychainServiceProtocol {
    func save(_ data: Data, for key: String) throws
    func load(for key: String) throws -> Data?
    func delete(for key: String) throws
    func saveString(_ string: String, for key: String) throws
    func loadString(for key: String) throws -> String?
}