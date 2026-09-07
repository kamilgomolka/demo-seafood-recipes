import Foundation

nonisolated struct Meal: Decodable, Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let name: String
    let thumbnailURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id = "idMeal"
        case name = "strMeal"
        case thumbnailURL = "strMealThumb"
    }
}

nonisolated struct MealIngredient: Sendable, Equatable, Hashable {
    let name: String
    let measure: String
}

nonisolated struct MealDetails: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let area: String?
    let instructions: String
    let thumbnailURL: URL?
    let ingredients: [MealIngredient]
}
