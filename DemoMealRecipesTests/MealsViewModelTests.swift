import Testing

@testable import DemoMealRecipes

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct MealsViewModelTests {
    private let original = [Meal(id: "1", name: "Salmon", thumbnailURL: nil)]
    private let updated = [Meal(id: "2", name: "Prawns", thumbnailURL: nil)]

    @Test func initialLoadAndRepeatedAppearance() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let load = Task { await model.loadIfNeeded() }
        let request = try #require(await requests.next())
        guard case .loading = model.state else {
            Issue.record("Expected initial loading")
            await service.complete(request, with: .success(original))
            await load.value
            return
        }
        await service.complete(request, with: .success(original))
        await load.value
        #expect(model.meals == original)
        #expect(!model.state.isLoading)
        await model.loadIfNeeded()
        #expect(await service.count == 1)
    }

    @Test func emptyResultIsLoadedAndCanRefresh() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let load = Task { await model.loadIfNeeded() }
        await service.complete(try #require(await requests.next()), with: .success([]))
        await load.value
        guard case .loaded(let meals, refresh: .idle) = model.state else {
            Issue.record("Expected a successfully loaded empty collection")
            return
        }
        #expect(meals.isEmpty)
        await model.loadIfNeeded()
        #expect(await service.count == 1)
        let refresh = Task { await model.reload() }
        await service.complete(try #require(await requests.next()), with: .success(updated))
        await refresh.value
        #expect(model.meals == updated)
    }

    @Test func failureRequiresExplicitRetry() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let load = Task { await model.loadIfNeeded() }
        await service.complete(try #require(await requests.next()), with: .failure(.httpStatus(503)))
        await load.value
        guard case .failed(.httpStatus(503)) = model.state else {
            Issue.record("Expected HTTP failure")
            return
        }
        await model.loadIfNeeded()
        #expect(await service.count == 1)
        let retry = Task { await model.reload() }
        await service.complete(try #require(await requests.next()), with: .success(original))
        await retry.value
        #expect(model.meals == original)
    }

    @Test func refreshPreservesContentOnFailureAndRetryReplacesIt() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let load = Task { await model.loadIfNeeded() }
        await service.complete(try #require(await requests.next()), with: .success(original))
        await load.value

        let refresh = Task { await model.reload() }
        let request = try #require(await requests.next())
        #expect(model.meals == original)
        #expect(model.state.isLoading)
        await model.reload()
        #expect(await service.count == 2)
        await service.complete(request, with: .failure(.httpStatus(503)))
        await refresh.value
        guard case .loaded(let meals, refresh: .failed(.httpStatus(503))) = model.state else {
            Issue.record("Expected content and refresh failure")
            return
        }
        #expect(meals == original)

        let retry = Task { await model.reload() }
        await service.complete(try #require(await requests.next()), with: .success(updated))
        await retry.value
        guard case .loaded(let replacement, refresh: .idle) = model.state else {
            Issue.record("Expected refresh error to clear")
            return
        }
        #expect(replacement == updated)
    }

    @Test func cancellationDiscardsLateSuccessAndAllowsReentry() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let first = Task { await model.loadIfNeeded() }
        let firstRequest = try #require(await requests.next())
        first.cancel()

        let (entered, continuation) = AsyncStream<Void>.makeStream()
        var entries = entered.makeAsyncIterator()
        let reentry = Task {
            continuation.yield(())
            continuation.finish()
            await model.loadIfNeeded()
        }
        await entries.next()
        #expect(await service.count == 1)
        await service.complete(firstRequest, with: .success(original))
        await first.value
        let secondRequest = try #require(await requests.next())
        #expect(model.meals.isEmpty)
        await service.complete(secondRequest, with: .success(updated))
        await reentry.value
        #expect(model.meals == updated)
    }

    @Test func cancellingRefreshPreservesPreviousContentEvenWhenItFails() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let load = Task { await model.loadIfNeeded() }
        await service.complete(try #require(await requests.next()), with: .success(original))
        await load.value
        let refresh = Task { await model.reload() }
        let request = try #require(await requests.next())
        refresh.cancel()
        await service.complete(request, with: .failure(.httpStatus(503)))
        await refresh.value
        guard case .loaded(let meals, refresh: .idle) = model.state else {
            Issue.record("Cancellation must not display a refresh error")
            return
        }
        #expect(meals == original)
    }

    @Test func serviceCancellationRestoresIdle() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let load = Task { await model.loadIfNeeded() }
        await service.complete(try #require(await requests.next()), with: .failure(.cancelled))
        await load.value
        guard case .idle = model.state else {
            Issue.record("Expected idle after cancellation")
            return
        }
        let retry = Task { await model.loadIfNeeded() }
        await service.complete(try #require(await requests.next()), with: .success(original))
        await retry.value
        #expect(model.meals == original)
    }

    @Test func cancelledCallerDoesNotStartRequest() async {
        let service = ControlledMealService()
        let model = MealsViewModel(service: service)
        let load = Task {
            await model.loadIfNeeded()
        }
        load.cancel()
        await load.value
        #expect(await service.count == 0)
    }

    @Test func waitingAppearanceCanBeCancelledWithoutCancellingTheOwner() async throws {
        let service = ControlledMealService()
        var requests = service.requests.makeAsyncIterator()
        let model = MealsViewModel(service: service)
        let owner = Task { await model.loadIfNeeded() }
        let request = try #require(await requests.next())
        let (entered, continuation) = AsyncStream<Void>.makeStream()
        var entries = entered.makeAsyncIterator()
        let waiting = Task {
            continuation.yield(())
            continuation.finish()
            await model.loadIfNeeded()
        }
        await entries.next()
        waiting.cancel()
        await waiting.value
        #expect(model.state.isLoading)
        await service.complete(request, with: .success(original))
        await owner.value
        #expect(model.meals == original)
        #expect(await service.count == 1)
    }
}
