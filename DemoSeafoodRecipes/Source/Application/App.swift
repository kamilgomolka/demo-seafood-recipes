import SwiftUI

@main
struct DemoSeafoodRecipesApp: App {
    @State private var client: MealAPIClient
    @State private var viewModel: SeafoodListViewModel

    init() {
        let client = MealAPIClient()
        _client = State(initialValue: client)
        _viewModel = State(initialValue: SeafoodListViewModel(service: client))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                #if DEBUG
                    if let scenario = SeafoodScenario.launchScenario {
                        SeafoodScenarioRoot(scenario: scenario)
                    } else {
                        seafoodRoot
                    }
                #else
                    seafoodRoot
                #endif
            }
        }
    }

    private var seafoodRoot: SeafoodList {
        SeafoodList(viewModel: viewModel, service: client)
    }
}
