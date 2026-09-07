import Observation

enum MealsState {
    case idle
    case loading
    case failed(MealAPIError)
    case loaded([Meal], refresh: RefreshState)

    enum RefreshState {
        case idle
        case refreshing
        case failed(MealAPIError)
    }

    var isLoading: Bool {
        switch self {
        case .loading, .loaded(_, refresh: .refreshing): true
        default: false
        }
    }
}

@MainActor
@Observable
final class MealsViewModel {
    private(set) var state: MealsState = .idle

    private let service: any MealService
    @ObservationIgnored private var completionWaiters: [AsyncStream<Void>.Continuation] = []

    init(service: any MealService) {
        self.service = service
    }

    var meals: [Meal] {
        guard case .loaded(let meals, _) = state else { return [] }
        return meals
    }

    func loadIfNeeded() async {
        while state.isLoading {
            let (completion, continuation) = AsyncStream<Void>.makeStream()
            completionWaiters.append(continuation)
            for await _ in completion {}
            guard !Task.isCancelled else { return }
        }
        guard case .idle = state else { return }
        await reload()
    }

    func reload() async {
        guard !Task.isCancelled, !state.isLoading else { return }

        let previousMeals: [Meal]?
        if case .loaded(let meals, _) = state {
            previousMeals = meals
            state = .loaded(meals, refresh: .refreshing)
        } else {
            previousMeals = nil
            state = .loading
        }

        defer {
            for waiter in completionWaiters {
                waiter.finish()
            }
            completionWaiters.removeAll()
        }

        do {
            let meals = try await service.fetchMeals()
            guard !Task.isCancelled else {
                restoreAfterCancellation(previousMeals: previousMeals)
                return
            }
            state = .loaded(meals, refresh: .idle)
        } catch {
            if Task.isCancelled {
                restoreAfterCancellation(previousMeals: previousMeals)
                return
            }
            if case .cancelled = error {
                restoreAfterCancellation(previousMeals: previousMeals)
                return
            }
            if let previousMeals {
                state = .loaded(previousMeals, refresh: .failed(error))
            } else {
                state = .failed(error)
            }
        }
    }

    private func restoreAfterCancellation(previousMeals: [Meal]?) {
        if let previousMeals {
            state = .loaded(previousMeals, refresh: .idle)
        } else {
            state = .idle
        }
    }
}
