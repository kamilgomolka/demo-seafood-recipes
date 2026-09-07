import SwiftUI
import Testing

@testable import DemoMealRecipes

@MainActor
struct MainViewTests {

    @Test func viewsBuild() {
        let _ = DemoMealRecipesApp().body
        let _ = MainView().body
        let _ = SampleFeatureView().body
    }
}
