import Foundation

nonisolated struct Meal: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let thumbnailURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id = "idMeal"
        case name = "strMeal"
        case thumbnailURL = "strMealThumb"
    }
}
