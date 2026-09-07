import Testing

@testable import DemoMealRecipes

actor ControlledMealService: MealService {
    let requests: AsyncStream<Int>
    let mealDetailRequests: AsyncStream<String>
    private let started: AsyncStream<Int>.Continuation
    private let startedDetails: AsyncStream<String>.Continuation
    private var pending: [Int: CheckedContinuation<Result<[Meal], MealAPIError>, Never>] = [:]
    private var pendingDetails: [Int: CheckedContinuation<Result<MealDetails, MealAPIError>, Never>] = [:]
    private var requestCount = 0
    private var mealDetailCount = 0

    init() {
        (requests, started) = AsyncStream<Int>.makeStream()
        (mealDetailRequests, startedDetails) = AsyncStream<String>.makeStream()
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

    func fetchMeal(id: String) async throws(MealAPIError) -> MealDetails {
        mealDetailCount += 1
        let request = mealDetailCount
        let result = await withCheckedContinuation { continuation in
            pendingDetails[request] = continuation
            startedDetails.yield(id)
        }
        return try result.get()
    }

    func complete(_ request: Int, with result: Result<[Meal], MealAPIError>) {
        let continuation = pending.removeValue(forKey: request)
        #expect(continuation != nil)
        continuation?.resume(returning: result)
    }

    func completeDetail(_ request: Int, with result: Result<MealDetails, MealAPIError>) {
        let continuation = pendingDetails.removeValue(forKey: request)
        #expect(continuation != nil)
        continuation?.resume(returning: result)
    }

    var count: Int { requestCount }
    var detailCount: Int { mealDetailCount }
}
