import Foundation

nonisolated struct MealDetails: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let area: String?
    let instructions: String
    let thumbnailURL: URL?
    let ingredients: [MealIngredient]
}

nonisolated struct MealIngredient: Sendable, Equatable, Hashable {
    let name: String
    let measure: String
}
