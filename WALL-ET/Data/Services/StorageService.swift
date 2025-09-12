import Foundation

protocol StorageServiceProtocol {
    func save<T: Codable>(_ object: T, for key: String) throws
    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T?
    func delete(for key: String) throws
}

final class StorageService: StorageServiceProtocol {
    private let documentsDirectory: URL
    
    init() {
        self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    func save<T: Codable>(_ object: T, for key: String) throws {
        let url = documentsDirectory.appendingPathComponent("\(key).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(object)
        try data.write(to: url)
    }
    
    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        let url = documentsDirectory.appendingPathComponent("\(key).json")
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    
    func delete(for key: String) throws {
        let url = documentsDirectory.appendingPathComponent("\(key).json")
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}