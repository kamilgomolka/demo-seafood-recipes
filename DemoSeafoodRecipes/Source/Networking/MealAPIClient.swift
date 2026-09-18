import Foundation

nonisolated protocol MealService: Sendable {
    func fetchMeals() async throws(MealAPIError) -> [Meal]
    func fetchMeal(id: String) async throws(MealAPIError) -> MealDetails
}

nonisolated enum MealAPIError: Error, Equatable {
    case transport(any Error)
    case invalidResponse
    case httpStatus(Int)
    case decoding(any Error)
    case notFound
    case cancelled

    static func == (lhs: MealAPIError, rhs: MealAPIError) -> Bool {
        switch (lhs, rhs) {
        case (.transport, .transport),
            (.invalidResponse, .invalidResponse),
            (.decoding, .decoding),
            (.notFound, .notFound),
            (.cancelled, .cancelled):
            true
        case (.httpStatus(let lhsStatus), .httpStatus(let rhsStatus)):
            lhsStatus == rhsStatus
        default:
            false
        }
    }

    var isCancelled: Bool {
        self == .cancelled
    }

    var message: String {
        switch self {
        case .transport:
            "Couldn't connect. Check your connection and try again."
        case .invalidResponse, .httpStatus:
            "The server couldn't complete the request. Please try again."
        case .decoding:
            "The recipes couldn't be read. Please try again."
        case .notFound:
            "This recipe isn't available. Please try again."
        case .cancelled:
            ""
        }
    }
}

nonisolated struct MealAPIClient: MealService {
    private static let filterURL = "https://www.themealdb.com/api/json/v1/1/filter.php?c=Seafood"
    private static let lookupURL = "https://www.themealdb.com/api/json/v1/1/lookup.php"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    @concurrent
    func fetchMeals() async throws(MealAPIError) -> [Meal] {
        let meals = try await decode(MealsResponse.self, from: Self.filterURL).meals
        try throwIfCancelled()
        return meals
    }

    @concurrent
    func fetchMeal(id: String) async throws(MealAPIError) -> MealDetails {
        var components = URLComponents(string: Self.lookupURL)
        components?.queryItems = [URLQueryItem(name: "i", value: id)]
        guard let url = components?.url else { throw MealAPIError.invalidResponse }

        let meals = try await decode(LookupResponse.self, from: url).meals ?? []
        try throwIfCancelled()
        guard let meal = meals.first else { throw MealAPIError.notFound }
        return meal.details
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from urlString: String) async throws(MealAPIError)
        -> Value
    {
        guard let url = URL(string: urlString) else { throw MealAPIError.invalidResponse }
        return try await decode(type, from: url)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from url: URL) async throws(MealAPIError) -> Value {
        let body = try await loadData(from: url)
        do {
            return try JSONDecoder().decode(type, from: body)
        } catch {
            throw .decoding(error)
        }
    }

    private func throwIfCancelled() throws(MealAPIError) {
        if Task.isCancelled { throw .cancelled }
    }

    private func loadData(from url: URL) async throws(MealAPIError) -> Data {
        do {
            try Task.checkCancellation()
            let (body, response) = try await session.data(for: URLRequest(url: url))
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw MealAPIError.invalidResponse
            }
            guard (200..<300).contains(response.statusCode) else {
                throw MealAPIError.httpStatus(response.statusCode)
            }
            return body
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw .cancelled
            }
            if let error = error as? MealAPIError {
                throw error
            }
            throw .transport(error)
        }
    }

    private struct MealsResponse: Decodable {
        let meals: [Meal]

        private enum CodingKeys: String, CodingKey { case meals }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            meals = try container.decode([Meal]?.self, forKey: .meals) ?? []
        }
    }

    private struct LookupResponse: Decodable {
        let meals: [LookupMeal]?
    }

    private struct LookupMeal: Decodable {
        let details: MealDetails

        private struct Field: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ stringValue: String) { self.stringValue = stringValue }
            init?(stringValue: String) { self.init(stringValue) }
            init?(intValue: Int) { nil }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Field.self)
            func field(_ name: String) throws -> String? {
                try container.decodeIfPresent(String.self, forKey: Field(name))
            }
            func trimmed(_ name: String) throws -> String {
                try field(name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            var ingredients: [MealIngredient] = []
            for index in 1...20 {
                let name = try trimmed("strIngredient\(index)")
                guard !name.isEmpty else { continue }
                ingredients.append(MealIngredient(name: name, measure: try trimmed("strMeasure\(index)")))
            }

            details = MealDetails(
                id: try container.decode(String.self, forKey: Field("idMeal")),
                name: try container.decode(String.self, forKey: Field("strMeal")),
                category: try field("strCategory"),
                area: try field("strArea"),
                instructions: try field("strInstructions") ?? "",
                thumbnailURL: try field("strMealThumb").flatMap(URL.init(string:)),
                ingredients: ingredients)
        }
    }
}
