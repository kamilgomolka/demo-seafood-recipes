import Foundation
import Observation

enum SeafoodListState {
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
final class SeafoodListViewModel {
    private(set) var state: SeafoodListState = .idle

    private let service: any MealService
    @ObservationIgnored private var completionWaiters: [CheckedContinuation<Void, Never>] = []

    init(service: any MealService) {
        self.service = service
    }

    var seafood: [Meal] {
        guard case .loaded(let meals, _) = state else { return [] }
        return meals
    }

    func seafood(matching query: String) -> [Meal] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return seafood }
        return seafood.filter { $0.name.localizedStandardContains(query) }
    }

    func loadIfNeeded() async {
        while state.isLoading {
            guard !Task.isCancelled else { return }
            await waitForInFlightLoad()
            guard !Task.isCancelled else { return }
        }
        guard case .idle = state else { return }
        await reload()
    }

    func reload() async {
        guard !Task.isCancelled, !state.isLoading else { return }

        let previousSeafood: [Meal]?
        if case .loaded(let meals, _) = state {
            previousSeafood = meals
            state = .loaded(meals, refresh: .refreshing)
        } else {
            previousSeafood = nil
            state = .loading
        }

        defer { resumeCompletionWaiters() }

        do {
            let meals = try await service.fetchMeals()
            guard !Task.isCancelled else {
                restoreAfterCancellation(previousSeafood: previousSeafood)
                return
            }
            state = .loaded(meals, refresh: .idle)
        } catch {
            if Task.isCancelled || error.isCancelled {
                restoreAfterCancellation(previousSeafood: previousSeafood)
            } else if let previousSeafood {
                state = .loaded(previousSeafood, refresh: .failed(error))
            } else {
                state = .failed(error)
            }
        }
    }

    private func waitForInFlightLoad() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                    return
                }
                completionWaiters.append(continuation)
            }
        } onCancel: {
            Task { @MainActor in
                self.resumeCompletionWaiters()
            }
        }
    }

    private func resumeCompletionWaiters() {
        let waiters = completionWaiters
        completionWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func restoreAfterCancellation(previousSeafood: [Meal]?) {
        if let previousSeafood {
            state = .loaded(previousSeafood, refresh: .idle)
        } else {
            state = .idle
        }
    }
}
