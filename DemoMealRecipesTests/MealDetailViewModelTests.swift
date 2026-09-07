import Testing

@testable import DemoMealRecipes

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct MealDetailViewModelTests {
    private let details = MealDetails(
        id: "52772",
        name: "Teriyaki Chicken",
        category: "Chicken",
        area: "Japanese",
        instructions: "Fry the chicken.",
        thumbnailURL: nil,
        ingredients: [MealIngredient(name: "Chicken", measure: "400g")])

    @Test func initialLoadAndRepeatedAppearance() async throws {
        let service = ControlledMealService()
        var requests = service.mealDetailRequests.makeAsyncIterator()
        let model = MealDetailViewModel(mealID: "52772", service: service)
        let load = Task { await model.loadIfNeeded() }
        _ = try #require(await requests.next())
        guard case .loading = model.state else {
            Issue.record("Expected initial loading")
            await service.completeDetail(1, with: .success(details))
            await load.value
            return
        }
        await service.completeDetail(1, with: .success(details))
        await load.value
        guard case .loaded(let loaded) = model.state else {
            Issue.record("Expected loaded details")
            return
        }
        #expect(loaded == details)
        await model.loadIfNeeded()
        #expect(await service.detailCount == 1)
    }

    @Test func failureRequiresExplicitRetry() async throws {
        let service = ControlledMealService()
        var requests = service.mealDetailRequests.makeAsyncIterator()
        let model = MealDetailViewModel(mealID: "52772", service: service)
        let load = Task { await model.loadIfNeeded() }
        _ = try #require(await requests.next())
        await service.completeDetail(1, with: .failure(.notFound))
        await load.value
        guard case .failed(.notFound) = model.state else {
            Issue.record("Expected not found")
            return
        }
        await model.loadIfNeeded()
        #expect(await service.detailCount == 1)
        let retry = Task { await model.reload() }
        _ = try #require(await requests.next())
        await service.completeDetail(2, with: .success(details))
        await retry.value
        guard case .loaded = model.state else {
            Issue.record("Expected loaded after retry")
            return
        }
    }

    @Test func cancellationDiscardsLateSuccess() async throws {
        let service = ControlledMealService()
        var requests = service.mealDetailRequests.makeAsyncIterator()
        let model = MealDetailViewModel(mealID: "52772", service: service)
        let load = Task { await model.loadIfNeeded() }
        _ = try #require(await requests.next())
        load.cancel()
        await service.completeDetail(1, with: .success(details))
        await load.value
        guard case .idle = model.state else {
            Issue.record("Cancellation must not publish details")
            return
        }
    }
}
