import Testing

@testable import DemoMealRecipes

actor ControlledMealService: MealService {
    let requests: AsyncStream<Int>
    private let started: AsyncStream<Int>.Continuation
    private var pending: [Int: CheckedContinuation<Result<[Meal], MealAPIError>, Never>] = [:]
    private var requestCount = 0

    init() {
        (requests, started) = AsyncStream<Int>.makeStream()
    }

    func fetchMeals() async throws(MealAPIError) -> [Meal] {
        requestCount += 1
        let request = requestCount
        let result = await withCheckedContinuation { continuation in
            pending[request] = continuation
            started.yield(request)
        }
        return try result.get()
    }

    func complete(_ request: Int, with result: Result<[Meal], MealAPIError>) {
        let continuation = pending.removeValue(forKey: request)
        #expect(continuation != nil)
        continuation?.resume(returning: result)
    }

    var count: Int { requestCount }
}
