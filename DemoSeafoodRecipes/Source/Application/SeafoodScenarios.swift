#if DEBUG
    import Foundation
    import Observation
    import SwiftUI

    enum SeafoodScenario: String {
        case success
        case failure
        case empty
        case refreshFailure
        case lifecycle
        case refreshLifecycle

        static var launchScenario: SeafoodScenario? {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--seafood-scenario"), arguments.indices.contains(index + 1) {
                return SeafoodScenario(rawValue: arguments[index + 1])
            }
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return .success
            }
            return nil
        }
    }

    @MainActor
    @Observable
    final class ScenarioSeafoodService: MealService {
        private(set) var requestCount = 0
        private(set) var cancellationCount = 0
        private let scenario: SeafoodScenario
        @ObservationIgnored private var pending: CheckedContinuation<[Meal], Never>?
        @ObservationIgnored private var hasRecovered = false

        init(scenario: SeafoodScenario) {
            self.scenario = scenario
        }

        @MainActor
        func fetchMeals() async throws(MealAPIError) -> [Meal] {
            guard !Task.isCancelled else { throw .cancelled }
            requestCount += 1

            switch scenario {
            case .failure where requestCount == 1,
                .refreshFailure where requestCount > 1 && !hasRecovered:
                throw .httpStatus(503)
            case .empty where requestCount == 1:
                return []
            case .lifecycle:
                return await waitForCompletion()
            case .refreshLifecycle where requestCount == 2:
                return await waitForCompletion()
            default:
                return Self.seafood(batch: requestCount)
            }
        }

        @MainActor
        func fetchMeal(id: String) async throws(MealAPIError) -> MealDetails {
            guard !Task.isCancelled else { throw .cancelled }
            return Self.details(id: id)
        }

        func completePendingRequest() {
            pending?.resume(returning: Self.seafood(batch: requestCount))
            pending = nil
        }

        func recover() {
            hasRecovered = true
        }

        private func waitForCompletion() async -> [Meal] {
            await withTaskCancellationHandler {
                await withCheckedContinuation { pending = $0 }
            } onCancel: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.cancellationCount += 1
                    if self?.scenario == .refreshLifecycle {
                        self?.completePendingRequest()
                    }
                }
            }
        }

        private static func seafood(batch: Int) -> [Meal] {
            let prefix = batch == 1 ? "Original" : "Updated"
            return (1...30).map { index in
                Meal(id: String(index), name: "\(prefix) seafood \(index)", thumbnailURL: nil)
            }
        }

        private static func details(id: String) -> MealDetails {
            MealDetails(
                id: id,
                name: "Original seafood \(id)",
                category: "Seafood",
                area: "British",
                instructions: "Simmer the seafood until cooked through.",
                thumbnailURL: nil,
                ingredients: [
                    MealIngredient(name: "Salmon", measure: "200g"),
                    MealIngredient(name: "Salt", measure: "1 tsp"),
                ])
        }
    }

    struct SeafoodScenarioRoot: View {
        @State private var service: ScenarioSeafoodService
        @State private var viewModel: SeafoodListViewModel
        @State private var isVisible = true
        @State private var parentRevision = 0
        private let scenario: SeafoodScenario

        init(scenario: SeafoodScenario) {
            let service = ScenarioSeafoodService(scenario: scenario)
            _service = State(initialValue: service)
            _viewModel = State(initialValue: SeafoodListViewModel(service: service))
            self.scenario = scenario
        }

        var body: some View {
            VStack(spacing: 0) {
                if scenario == .lifecycle || scenario == .refreshLifecycle {
                    Text(
                        "Requests: \(service.requestCount), cancellations: \(service.cancellationCount), revision: \(parentRevision)"
                    )
                    .font(.caption)
                    .accessibilityIdentifier("scenario.status")
                    HStack {
                        Button(isVisible ? "Hide" : "Show") { isVisible.toggle() }
                            .accessibilityIdentifier("scenario.visibility")
                        Button("Complete") { service.completePendingRequest() }
                            .accessibilityIdentifier("scenario.complete")
                        Button("Update parent") { parentRevision += 1 }
                            .accessibilityIdentifier("scenario.updateParent")
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                }
                if isVisible {
                    SeafoodList(viewModel: viewModel, service: service)
                } else {
                    Color.clear
                }
            }
            .safeAreaInset(edge: .bottom) {
                if scenario == .refreshFailure {
                    Button("Restore service") { service.recover() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.bar)
                        .accessibilityIdentifier("scenario.recover")
                }
            }
            .onChange(of: service.requestCount) { _, count in
                if scenario == .refreshLifecycle, count == 2 {
                    isVisible = false
                }
            }
        }
    }

    #Preview("Recipes") {
        NavigationStack {
            SeafoodScenarioRoot(scenario: .success)
        }
    }

    #Preview("Empty") {
        NavigationStack {
            SeafoodScenarioRoot(scenario: .empty)
        }
    }

    #Preview("Failure") {
        NavigationStack {
            SeafoodScenarioRoot(scenario: .failure)
        }
    }
#endif
