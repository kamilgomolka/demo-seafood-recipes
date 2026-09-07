import Foundation
import Testing

@testable import DemoMealRecipes

@Suite(.timeLimit(.minutes(1)))
struct MealAPIClientTests {
    @Test func requestAndDecoding() async throws {
        let fixture = MealHTTPFixture(
            .http(
                200,
                """
                {"meals":[{"idMeal":"12","strMeal":"Salmon","strMealThumb":"https://example.com/salmon.jpg"}]}
                """))
        defer { fixture.close() }
        let meals = try await MealAPIClient(session: fixture.session).fetchMeals()
        #expect(meals == [Meal(id: "12", name: "Salmon", thumbnailURL: URL(string: "https://example.com/salmon.jpg"))])
        var requests = fixture.requests.makeAsyncIterator()
        let request = try #require(await requests.next())
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://www.themealdb.com/api/json/v1/1/filter.php?c=Seafood")
    }

    @Test(arguments: ["{\"meals\":[]}", "{\"meals\":null}"])
    func emptyResults(body: String) async throws {
        let fixture = MealHTTPFixture(.http(200, body))
        defer { fixture.close() }
        #expect(try await MealAPIClient(session: fixture.session).fetchMeals().isEmpty)
    }

    @Test(arguments: ["{}", "not JSON", "{\"meals\":[{\"strMeal\":\"Missing ID\"}]}"])
    func malformedResponses(body: String) async {
        let fixture = MealHTTPFixture(.http(200, body))
        defer { fixture.close() }
        do {
            _ = try await MealAPIClient(session: fixture.session).fetchMeals()
            Issue.record("Expected decoding failure")
        } catch {
            guard case .decoding = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func httpFailurePrecedesDecoding() async {
        let fixture = MealHTTPFixture(.http(503, "Unavailable"))
        defer { fixture.close() }
        do {
            _ = try await MealAPIClient(session: fixture.session).fetchMeals()
            Issue.record("Expected HTTP failure")
        } catch {
            guard case .httpStatus(503) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func transportFailurePreservesCause() async {
        let fixture = MealHTTPFixture(.failure(.notConnectedToInternet))
        defer { fixture.close() }
        do {
            _ = try await MealAPIClient(session: fixture.session).fetchMeals()
            Issue.record("Expected transport failure")
        } catch {
            guard case .transport(let underlying) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect((underlying as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @Test func cancellationStopsURLSessionRequest() async throws {
        let fixture = MealHTTPFixture(.suspended)
        defer { fixture.close() }
        var requests = fixture.requests.makeAsyncIterator()
        var stops = fixture.stops.makeAsyncIterator()
        let task = Task {
            do throws(MealAPIError) {
                _ = try await MealAPIClient(session: fixture.session).fetchMeals()
                Issue.record("Cancelled request must not succeed")
            } catch {
                guard case .cancelled = error else {
                    Issue.record("Unexpected cancellation error: \(error)")
                    return
                }
            }
        }
        _ = try #require(await requests.next())
        task.cancel()
        await task.value
        _ = try #require(await stops.next())
    }

    @Test func urlCancellationIsNotTransportFailure() async {
        let fixture = MealHTTPFixture(.failure(.cancelled))
        defer { fixture.close() }
        do {
            _ = try await MealAPIClient(session: fixture.session).fetchMeals()
            Issue.record("Expected cancellation")
        } catch {
            guard case .cancelled = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }
}
