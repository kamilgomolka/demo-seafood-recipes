import Foundation
import Testing

@testable import DemoSeafoodRecipes

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

    @Test func lookupRequestAndIngredients() async throws {
        let fixture = MealHTTPFixture(
            .http(
                200,
                """
                {"meals":[{
                  "idMeal":"52772",
                  "strMeal":"Teriyaki Chicken",
                  "strCategory":"Chicken",
                  "strArea":"Japanese",
                  "strInstructions":"Fry the chicken.",
                  "strMealThumb":"https://example.com/chicken.jpg",
                  "strIngredient1":"Chicken",
                  "strMeasure1":"400g",
                  "strIngredient2":"Soy sauce",
                  "strMeasure2":" ",
                  "strIngredient3":"",
                  "strMeasure3":"1 tbsp",
                  "strIngredient4":null,
                  "strMeasure4":null
                }]}
                """))
        defer { fixture.close() }
        let details = try await MealAPIClient(session: fixture.session).fetchMeal(id: "52772")
        #expect(
            details
                == MealDetails(
                    id: "52772",
                    name: "Teriyaki Chicken",
                    category: "Chicken",
                    area: "Japanese",
                    instructions: "Fry the chicken.",
                    thumbnailURL: URL(string: "https://example.com/chicken.jpg"),
                    ingredients: [
                        MealIngredient(name: "Chicken", measure: "400g"),
                        MealIngredient(name: "Soy sauce", measure: ""),
                    ]))
        var requests = fixture.requests.makeAsyncIterator()
        let request = try #require(await requests.next())
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://www.themealdb.com/api/json/v1/1/lookup.php?i=52772")
    }

    @Test(arguments: ["{\"meals\":[]}", "{\"meals\":null}"])
    func lookupMissingMeal(body: String) async {
        let fixture = MealHTTPFixture(.http(200, body))
        defer { fixture.close() }
        do {
            _ = try await MealAPIClient(session: fixture.session).fetchMeal(id: "52772")
            Issue.record("Expected not found")
        } catch {
            guard case .notFound = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func lookupHTTPFailure() async {
        let fixture = MealHTTPFixture(.http(503, "Unavailable"))
        defer { fixture.close() }
        do {
            _ = try await MealAPIClient(session: fixture.session).fetchMeal(id: "52772")
            Issue.record("Expected HTTP failure")
        } catch {
            guard case .httpStatus(503) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
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
