import Foundation

nonisolated protocol MealService: Sendable {
    func fetchMeals() async throws(MealAPIError) -> [Meal]
}

nonisolated enum MealAPIError: Error {
    case transport(any Error)
    case invalidResponse
    case httpStatus(Int)
    case decoding(any Error)
    case cancelled

    var message: String {
        switch self {
        case .transport:
            "Couldn't connect. Check your connection and try again."
        case .invalidResponse, .httpStatus:
            "The server couldn't complete the request. Please try again."
        case .decoding:
            "The recipes couldn't be read. Please try again."
        case .cancelled:
            ""
        }
    }
}

nonisolated struct MealAPIClient: MealService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    @concurrent
    func fetchMeals() async throws(MealAPIError) -> [Meal] {
        do {
            try Task.checkCancellation()
            guard let url = URL(string: "https://www.themealdb.com/api/json/v1/1/filter.php?c=Seafood") else {
                throw MealAPIError.invalidResponse
            }

            let (body, response) = try await session.data(for: URLRequest(url: url))
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw MealAPIError.invalidResponse
            }
            guard (200..<300).contains(response.statusCode) else {
                throw MealAPIError.httpStatus(response.statusCode)
            }

            let meals: [Meal]
            do {
                meals = try JSONDecoder().decode(MealsResponse.self, from: body).meals
            } catch {
                throw MealAPIError.decoding(error)
            }
            try Task.checkCancellation()
            return meals
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

        private enum CodingKeys: String, CodingKey {
            case meals
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            meals = try container.decode([Meal]?.self, forKey: .meals) ?? []
        }
    }
}
