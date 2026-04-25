import Foundation

struct FiatCurrency: Identifiable, Hashable {
    let code: String
    let symbol: String
    let name: String
    var id: String { code }
}

actor ExchangeRateService {
    static let shared = ExchangeRateService()

    static let supported: [FiatCurrency] = [
        FiatCurrency(code: "USD", symbol: "$", name: "US Dollar"),
        FiatCurrency(code: "EUR", symbol: "€", name: "Euro"),
        FiatCurrency(code: "GBP", symbol: "£", name: "British Pound"),
        FiatCurrency(code: "JPY", symbol: "¥", name: "Japanese Yen"),
        FiatCurrency(code: "CAD", symbol: "$", name: "Canadian Dollar"),
        FiatCurrency(code: "AUD", symbol: "$", name: "Australian Dollar"),
        FiatCurrency(code: "CHF", symbol: "Fr", name: "Swiss Franc"),
        FiatCurrency(code: "CNY", symbol: "¥", name: "Chinese Yuan"),
        FiatCurrency(code: "INR", symbol: "₹", name: "Indian Rupee"),
        FiatCurrency(code: "BRL", symbol: "R$", name: "Brazilian Real"),
        FiatCurrency(code: "MXN", symbol: "$", name: "Mexican Peso"),
        FiatCurrency(code: "KRW", symbol: "₩", name: "South Korean Won"),
        FiatCurrency(code: "SGD", symbol: "$", name: "Singapore Dollar"),
        FiatCurrency(code: "ZAR", symbol: "R", name: "South African Rand"),
        FiatCurrency(code: "HKD", symbol: "$", name: "Hong Kong Dollar"),
        FiatCurrency(code: "NZD", symbol: "$", name: "New Zealand Dollar"),
        FiatCurrency(code: "SEK", symbol: "kr", name: "Swedish Krona"),
        FiatCurrency(code: "NOK", symbol: "kr", name: "Norwegian Krone"),
        FiatCurrency(code: "DKK", symbol: "kr", name: "Danish Krone"),
        FiatCurrency(code: "PLN", symbol: "zł", name: "Polish Złoty"),
        FiatCurrency(code: "TRY", symbol: "₺", name: "Turkish Lira"),
        FiatCurrency(code: "THB", symbol: "฿", name: "Thai Baht"),
        FiatCurrency(code: "IDR", symbol: "Rp", name: "Indonesian Rupiah"),
        FiatCurrency(code: "PHP", symbol: "₱", name: "Philippine Peso"),
        FiatCurrency(code: "AED", symbol: "د.إ", name: "UAE Dirham"),
        FiatCurrency(code: "SAR", symbol: "﷼", name: "Saudi Riyal")
    ]

    static func currency(for code: String) -> FiatCurrency {
        supported.first(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) ?? supported[0]
    }

    private static let ratesKey = "wisp_settings_rates_json"
    private static let updatedAtKey = "wisp_settings_rates_ts"

    /// Map of UPPERCASE currency code → BTC price in that currency.
    private(set) var rates: [String: Double] = [:]
    private(set) var updatedAt: Date? = nil

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.ratesKey) {
            let parsed = Self.parseRates(data: data)
            if !parsed.isEmpty {
                self.rates = parsed
                let ts = UserDefaults.standard.double(forKey: Self.updatedAtKey)
                if ts > 0 {
                    self.updatedAt = Date(timeIntervalSince1970: ts)
                }
            }
        }
    }

    func satsToFiat(_ sats: Int64, currency code: String) -> Double? {
        guard let btcPrice = rates[code.uppercased()] else { return nil }
        return Double(sats) / 100_000_000.0 * btcPrice
    }

    func snapshot() -> (rates: [String: Double], updatedAt: Date?) {
        (rates, updatedAt)
    }

    func refresh() async {
        let codes = Self.supported.map { $0.code.lowercased() }.joined(separator: ",")
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=\(codes)") else {
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return
            }
            let parsed = parseRates(data: data)
            guard !parsed.isEmpty else { return }
            self.rates = parsed
            let now = Date()
            self.updatedAt = now
            UserDefaults.standard.set(data, forKey: Self.ratesKey)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.updatedAtKey)
        } catch {
            // Network failure: keep cached rates.
        }
    }

    private func parseRates(data: Data) -> [String: Double] {
        Self.parseRates(data: data)
    }

    private static func parseRates(data: Data) -> [String: Double] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let btc = json["bitcoin"] as? [String: Any]
        else { return [:] }
        var out: [String: Double] = [:]
        for (key, value) in btc {
            if let n = value as? Double {
                out[key.uppercased()] = n
            } else if let n = value as? NSNumber {
                out[key.uppercased()] = n.doubleValue
            }
        }
        return out
    }
}
