import Observation

enum MealDetailState {
    case idle
    case loading
    case failed(MealAPIError)
    case loaded(MealDetails)

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}

@MainActor
@Observable
final class MealDetailViewModel {
    private(set) var state: MealDetailState = .idle

    private let mealID: String
    private let service: any MealService

    init(mealID: String, service: any MealService) {
        self.mealID = mealID
        self.service = service
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await reload()
    }

    func reload() async {
        guard !Task.isCancelled, !state.isLoading else { return }
        state = .loading
        do {
            let details = try await service.fetchMeal(id: mealID)
            guard !Task.isCancelled else {
                state = .idle
                return
            }
            state = .loaded(details)
        } catch {
            state = (Task.isCancelled || error.isCancelled) ? .idle : .failed(error)
        }
    }
}
