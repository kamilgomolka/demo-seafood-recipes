import SwiftUI

@main
struct DemoMealRecipesApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                    if let scenario = MealScenario.launchScenario {
                        MealScenarioRoot(scenario: scenario)
                    } else {
                        MealsView(viewModel: MealsViewModel(service: MealAPIClient()))
                    }
                #else
                    MealsView(viewModel: MealsViewModel(service: MealAPIClient()))
                #endif
            }
        }
    }
}
