import Foundation
import Combine

protocol PriceDataServiceType {
    func fetchCurrentPrice(for currency: String) async -> PriceData?
    var priceUpdatePublisher: PassthroughSubject<PriceData, Never> { get }
}

// MARK: - Price Service
class PriceDataService {
    
    // MARK: - Properties
    static let shared = PriceDataService()
    private let networkManager = NetworkManager()
    private var cancellables = Set<AnyCancellable>()
    private var priceUpdateTimer: Timer?
    
    // Publishers
    let priceUpdatePublisher = PassthroughSubject<PriceData, Never>()
    let marketDataPublisher = PassthroughSubject<MarketData, Never>()
    let chartDataPublisher = PassthroughSubject<[ChartPoint], Never>()
    
    // Cache
    private var priceCache: [String: PriceData] = [:]
    private let cacheLock = NSLock()
    private let cacheExpiration: TimeInterval = 30 // 30 seconds
    
    // API Configuration
    private let apiProviders: [PriceProvider] = [
        CoinGeckoProvider(),
        BinanceProvider(),
        CoinbaseProvider(),
        KrakenProvider()
    ]
    
    private var currentProvider: PriceProvider
    
    // MARK: - Initialization
    private init() {
        self.currentProvider = apiProviders.first!
        startPriceUpdates()
    }
    
    // MARK: - Price Updates
    func startPriceUpdates(interval: TimeInterval = 30) {
        stopPriceUpdates()
        
        // Fetch immediately
        Task {
            await fetchCurrentPrice()
        }
        
        // Setup timer for periodic updates
        priceUpdateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchCurrentPrice()
            }
        }
    }
    
    func stopPriceUpdates() {
        priceUpdateTimer?.invalidate()
        priceUpdateTimer = nil
    }
    
    // MARK: - Price Fetching
    func fetchCurrentPrice(for currency: String = "USD") async -> PriceData? {
        // Check cache first
        let cacheKey = "BTC-\(currency)"
        cacheLock.lock()
        let cached = priceCache[cacheKey]
        cacheLock.unlock()
        if let cached,
           Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            return cached
        }
        
        // Try each provider until one succeeds
        for provider in apiProviders {
            do {
                let priceData = try await provider.fetchPrice(currency: currency)
                
                // Update cache
                cacheLock.lock(); priceCache[cacheKey] = priceData; cacheLock.unlock()
                
                // Publish update
                priceUpdatePublisher.send(priceData)
                
                return priceData
            } catch {
                print("Failed to fetch from \(provider.name): \(error)")
                continue
            }
        }
        
        return nil
    }
    
    // MARK: - Market Data
    func fetchMarketData() async -> MarketData? {
        do {
            let marketData = try await currentProvider.fetchMarketData()
            marketDataPublisher.send(marketData)
            return marketData
        } catch {
            print("Failed to fetch market data: \(error)")
            
            // Try fallback provider
            for provider in apiProviders where provider.name != currentProvider.name {
                do {
                    let marketData = try await provider.fetchMarketData()
                    currentProvider = provider // Switch to working provider
                    marketDataPublisher.send(marketData)
                    return marketData
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Historical Data
    func fetchPriceHistory(days: Int, currency: String = "USD") async -> [ChartPoint] {
        do {
            let chartData = try await currentProvider.fetchPriceHistory(days: days, currency: currency)
            chartDataPublisher.send(chartData)
            return chartData
        } catch {
            print("Failed to fetch price history: \(error)")
            return []
        }
    }
    
    // MARK: - Currency Conversion
    func convertBTCToFiat(btc: Double, currency: String = "USD") async -> Double {
        guard let priceData = await fetchCurrentPrice(for: currency) else {
            return 0
        }
        return btc * priceData.price
    }
    
    func convertFiatToBTC(fiat: Double, currency: String = "USD") async -> Double {
        guard let priceData = await fetchCurrentPrice(for: currency) else {
            return 0
        }
        return fiat / priceData.price
    }
    
    // MARK: - Exchange Rates
    func fetchExchangeRates(base: String = "USD") async -> [String: Double]? {
        do {
            return try await currentProvider.fetchExchangeRates(base: base)
        } catch {
            print("Failed to fetch exchange rates: \(error)")
            return nil
        }
    }
}

extension PriceDataService: PriceDataServiceType {}

// MARK: - Data Models
struct PriceData {
    let price: Double
    let change24h: Double
    let changePercentage24h: Double
    let volume24h: Double
    let marketCap: Double
    let currency: String
    let timestamp: Date
}

struct MarketData {
    let rank: Int
    let circulatingSupply: Double
    let totalSupply: Double
    let ath: Double
    let athDate: Date?
    let atl: Double
    let atlDate: Date?
}

struct ChartPoint {
    let timestamp: Date
    let price: Double
}

// MARK: - Price Provider Protocol
protocol PriceProvider {
    var name: String { get }
    func fetchPrice(currency: String) async throws -> PriceData
    func fetchMarketData() async throws -> MarketData
    func fetchPriceHistory(days: Int, currency: String) async throws -> [ChartPoint]
    func fetchExchangeRates(base: String) async throws -> [String: Double]
}

// MARK: - CoinGecko Provider
class CoinGeckoProvider: PriceProvider {
    let name = "CoinGecko"
    private let baseURL = "https://api.coingecko.com/api/v3"
    private let networkManager = NetworkManager()
    
    func fetchPrice(currency: String) async throws -> PriceData {
        let endpoint = "\(baseURL)/simple/price?ids=bitcoin&vs_currencies=\(currency.lowercased())&include_24hr_change=true&include_24hr_vol=true&include_market_cap=true"
        
        let response: CoinGeckoResponse = try await networkManager.fetch(from: endpoint)
        
        guard let bitcoin = response.bitcoin else {
            throw PriceError.invalidResponse
        }
        
        return PriceData(
            price: bitcoin.price(for: currency) ?? 0,
            change24h: bitcoin.change24h(for: currency) ?? 0,
            changePercentage24h: bitcoin.changePercentage24h(for: currency) ?? 0,
            volume24h: bitcoin.volume24h(for: currency) ?? 0,
            marketCap: bitcoin.marketCap(for: currency) ?? 0,
            currency: currency,
            timestamp: Date()
        )
    }
    
    func fetchMarketData() async throws -> MarketData {
        let endpoint = "\(baseURL)/coins/bitcoin?localization=false&tickers=false&community_data=false&developer_data=false"
        
        let response: CoinGeckoMarketResponse = try await networkManager.fetch(from: endpoint)
        
        return MarketData(
            rank: response.market_cap_rank ?? 1,
            circulatingSupply: response.market_data?.circulating_supply ?? 0,
            totalSupply: response.market_data?.total_supply ?? 21_000_000,
            ath: response.market_data?.ath?["usd"] ?? 0,
            athDate: nil,
            atl: response.market_data?.atl?["usd"] ?? 0,
            atlDate: nil
        )
    }
    
    func fetchPriceHistory(days: Int, currency: String) async throws -> [ChartPoint] {
        let endpoint = "\(baseURL)/coins/bitcoin/market_chart?vs_currency=\(currency.lowercased())&days=\(days)"
        
        let response: CoinGeckoChartResponse = try await networkManager.fetch(from: endpoint)
        
        return response.prices.map { pricePoint in
            ChartPoint(
                timestamp: Date(timeIntervalSince1970: pricePoint[0] / 1000),
                price: pricePoint[1]
            )
        }
    }
    
    func fetchExchangeRates(base: String) async throws -> [String: Double] {
        let endpoint = "\(baseURL)/exchange_rates"
        
        let response: CoinGeckoExchangeResponse = try await networkManager.fetch(from: endpoint)
        
        var rates: [String: Double] = [:]
        for (key, value) in response.rates {
            if let rate = value.value {
                rates[key.uppercased()] = rate
            }
        }
        
        return rates
    }
}

// MARK: - Binance Provider
class BinanceProvider: PriceProvider {
    let name = "Binance"
    private let baseURL = "https://api.binance.com/api/v3"
    private let networkManager = NetworkManager()
    
    func fetchPrice(currency: String) async throws -> PriceData {
        let symbol = currency == "USD" ? "BTCUSDT" : "BTC\(currency)"
        let endpoint = "\(baseURL)/ticker/24hr?symbol=\(symbol)"
        
        let response: BinanceTickerResponse = try await networkManager.fetch(from: endpoint)
        
        return PriceData(
            price: Double(response.lastPrice) ?? 0,
            change24h: Double(response.priceChange) ?? 0,
            changePercentage24h: Double(response.priceChangePercent) ?? 0,
            volume24h: Double(response.volume) ?? 0,
            marketCap: 0, // Binance doesn't provide market cap
            currency: currency,
            timestamp: Date()
        )
    }
    
    func fetchMarketData() async throws -> MarketData {
        // Binance doesn't provide comprehensive market data
        throw PriceError.notSupported
    }
    
    func fetchPriceHistory(days: Int, currency: String) async throws -> [ChartPoint] {
        let symbol = currency == "USD" ? "BTCUSDT" : "BTC\(currency)"
        let interval = days <= 1 ? "1h" : days <= 7 ? "4h" : "1d"
        let limit = min(500, days <= 1 ? 24 : days <= 7 ? days * 6 : days)
        
        let endpoint = "\(baseURL)/klines?symbol=\(symbol)&interval=\(interval)&limit=\(limit)"
        
        // Binance returns an array of arrays, need custom handling
        guard let url = URL(string: endpoint) else {
            throw PriceError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONSerialization.jsonObject(with: data) as? [[Any]] ?? []
        
        return response.compactMap { kline in
            guard kline.count >= 5,
                  let timestamp = kline[0] as? Double,
                  let closePrice = Double(kline[4] as? String ?? "") else {
                return nil
            }
            
            return ChartPoint(
                timestamp: Date(timeIntervalSince1970: timestamp / 1000),
                price: closePrice
            )
        }
    }
    
    func fetchExchangeRates(base: String) async throws -> [String: Double] {
        throw PriceError.notSupported
    }
}

// MARK: - Coinbase Provider
class CoinbaseProvider: PriceProvider {
    let name = "Coinbase"
    private let baseURL = "https://api.coinbase.com/v2"
    private let networkManager = NetworkManager()
    
    func fetchPrice(currency: String) async throws -> PriceData {
        let endpoint = "\(baseURL)/exchange-rates?currency=BTC"
        
        let response: CoinbaseExchangeResponse = try await networkManager.fetch(from: endpoint)
        
        guard let rate = response.data.rates[currency],
              let price = Double(rate) else {
            throw PriceError.invalidResponse
        }
        
        return PriceData(
            price: price,
            change24h: 0,
            changePercentage24h: 0,
            volume24h: 0,
            marketCap: 0,
            currency: currency,
            timestamp: Date()
        )
    }
    
    func fetchMarketData() async throws -> MarketData {
        throw PriceError.notSupported
    }
    
    func fetchPriceHistory(days: Int, currency: String) async throws -> [ChartPoint] {
        throw PriceError.notSupported
    }
    
    func fetchExchangeRates(base: String) async throws -> [String: Double] {
        let endpoint = "\(baseURL)/exchange-rates?currency=\(base)"
        
        let response: CoinbaseExchangeResponse = try await networkManager.fetch(from: endpoint)
        
        var rates: [String: Double] = [:]
        for (key, value) in response.data.rates {
            if let rate = Double(value) {
                rates[key] = rate
            }
        }
        
        return rates
    }
}

// MARK: - Kraken Provider
class KrakenProvider: PriceProvider {
    let name = "Kraken"
    private let baseURL = "https://api.kraken.com/0/public"
    private let networkManager = NetworkManager()
    
    func fetchPrice(currency: String) async throws -> PriceData {
        let pair = currency == "USD" ? "XBTUSD" : "XBT\(currency)"
        let endpoint = "\(baseURL)/Ticker?pair=\(pair)"
        
        let response: KrakenTickerResponse = try await networkManager.fetch(from: endpoint)
        
        guard let ticker = response.result?.first?.value else {
            throw PriceError.invalidResponse
        }
        
        let price = Double(ticker.c?.first ?? "0") ?? 0
        let change24h = price - (Double(ticker.o ?? "0") ?? 0)
        let changePercentage24h = (change24h / (Double(ticker.o ?? "0") ?? 1)) * 100
        
        return PriceData(
            price: price,
            change24h: change24h,
            changePercentage24h: changePercentage24h,
            volume24h: Double(ticker.v?.last ?? "0") ?? 0,
            marketCap: 0,
            currency: currency,
            timestamp: Date()
        )
    }
    
    func fetchMarketData() async throws -> MarketData {
        throw PriceError.notSupported
    }
    
    func fetchPriceHistory(days: Int, currency: String) async throws -> [ChartPoint] {
        throw PriceError.notSupported
    }
    
    func fetchExchangeRates(base: String) async throws -> [String: Double] {
        throw PriceError.notSupported
    }
}

// MARK: - Network Manager
class NetworkManager {
    private let session = URLSession.shared
    
    func fetch<T: Decodable>(from urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw PriceError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw PriceError.networkError
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            throw PriceError.decodingError
        }
    }
}

// MARK: - Response Models
struct CoinGeckoResponse: Codable {
    let bitcoin: BitcoinData?
    
    struct BitcoinData: Codable {
        let usd: Double?
        let usd_24h_change: Double?
        let usd_24h_vol: Double?
        let usd_market_cap: Double?
        
        func price(for currency: String) -> Double? {
            switch currency.uppercased() {
            case "USD": return usd
            default: return nil
            }
        }
        
        func change24h(for currency: String) -> Double? {
            switch currency.uppercased() {
            case "USD": return usd_24h_change
            default: return nil
            }
        }
        
        func changePercentage24h(for currency: String) -> Double? {
            return change24h(for: currency)
        }
        
        func volume24h(for currency: String) -> Double? {
            switch currency.uppercased() {
            case "USD": return usd_24h_vol
            default: return nil
            }
        }
        
        func marketCap(for currency: String) -> Double? {
            switch currency.uppercased() {
            case "USD": return usd_market_cap
            default: return nil
            }
        }
    }
}

struct CoinGeckoMarketResponse: Codable {
    let market_cap_rank: Int?
    let market_data: MarketDataResponse?
    
    struct MarketDataResponse: Codable {
        let circulating_supply: Double?
        let total_supply: Double?
        let ath: [String: Double]?
        let ath_date: [String: String]?
        let atl: [String: Double]?
        let atl_date: [String: String]?
    }
}

struct CoinGeckoChartResponse: Codable {
    let prices: [[Double]]
}

struct CoinGeckoExchangeResponse: Codable {
    let rates: [String: ExchangeRate]
    
    struct ExchangeRate: Codable {
        let value: Double?
    }
}

struct BinanceTickerResponse: Codable {
    let symbol: String
    let lastPrice: String
    let priceChange: String
    let priceChangePercent: String
    let volume: String
}

struct CoinbaseExchangeResponse: Codable {
    let data: ExchangeData
    
    struct ExchangeData: Codable {
        let rates: [String: String]
    }
}

struct KrakenTickerResponse: Codable {
    let result: [String: TickerData]?
    
    struct TickerData: Codable {
        let c: [String]? // Close price
        let o: String? // Open price
        let v: [String]? // Volume
    }
}


// MARK: - Errors
enum PriceError: LocalizedError {
    case invalidURL
    case networkError
    case invalidResponse
    case decodingError
    case notSupported
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network request failed"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Failed to decode response"
        case .notSupported:
            return "Operation not supported by this provider"
        }
    }
}
