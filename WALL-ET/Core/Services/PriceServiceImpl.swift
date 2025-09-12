import Foundation

final class PriceService: PriceServiceProtocol {
    func fetchBTCPrice() async throws -> PriceData {
        if let pd = await PriceDataService.shared.fetchCurrentPrice(for: "USD") {
            return pd
        }
        throw NSError(domain: "PriceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Price unavailable"])
    }
    func fetchPriceHistory(days: Int) async throws -> [PricePoint] {
        let points = await PriceDataService.shared.fetchPriceHistory(days: days)
        return points.map { PricePoint(date: $0.timestamp, price: $0.price) }
    }
    func subscribeToPriceUpdates(completion: @escaping (PriceData) -> Void) {
        _ = PriceDataService.shared.priceUpdatePublisher.sink { completion($0) }
    }
}

