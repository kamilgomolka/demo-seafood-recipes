import SwiftUI

@main
struct DemoMealRecipesApp: App {
    @State private var client: MealAPIClient
    @State private var viewModel: MealsViewModel

    init() {
        let client = MealAPIClient()
        _client = State(initialValue: client)
        _viewModel = State(initialValue: MealsViewModel(service: client))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                    if let scenario = MealScenario.launchScenario {
                        MealScenarioRoot(scenario: scenario)
                    } else {
                        MealsView(viewModel: viewModel)
                    }
                #else
                    MealsView(viewModel: viewModel)
                #endif
            }
        }
    }
}
