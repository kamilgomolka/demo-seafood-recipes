# Seafood Recipes

[![CI](https://github.com/kamilgomolka/demo-seafood-recipes/actions/workflows/ci.yml/badge.svg)](https://github.com/kamilgomolka/demo-seafood-recipes/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.2-F05138.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/iOS-26.0%2B-000000.svg)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-26-1575F9.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

An iPhone demo app, with a simple List-Details UI, and a basic networking. The main goal of this project was to exercise good practices around Swift Concurrency (`async`/`await`, actor isolation, Tasks, cooperative cancellation, and unit testing async code). Other aspects of the application are intentionally simplified - it's not a complete product, just a Swift concurrency playground. 

The app uses [TheMealDB](https://www.themealdb.com/documentation) to load Seafood recipes, supports initial loading, pull-to-refresh, local name search, empty results, retry, and a recipe detail screen.

## Run

- Xcode 26 with Swift 6.2 or newer; verified toolchain: Xcode 26.6 / Swift 6.3.3.
- Swift 6 language mode, complete concurrency checking, MainActor default isolation, and Approachable Concurrency.
- iOS 26.0+, iPhone portrait. No third-party dependencies.

Open `DemoSeafoodRecipes.xcodeproj` and run the `DemoSeafoodRecipes` scheme. Simulator builds do not require signing. For a device, copy `Config/Local.xcconfig.example` to the untracked `Config/Local.xcconfig` and set your development team.

```sh
make build
make test
make lint
```

The default destination is iPhone 17 Pro. Override it with `SIMULATOR='device name'`. Formatting and linting use the checked-in `.swift-format` configuration.

## Architecture

| Type | Responsibility |
| --- | --- |
| `SeafoodList` | List, presentation, gestures, navigation, and ownership of screen-bound work |
| `SeafoodListViewModel` | Observable list state, request admission, state transitions, and cancellation-safe result publishing |
| `SeafoodListState` | Initial loading/failure and loaded content with nested refresh state |
| `SeafoodDetailView` | Recipe screen; owns a detail ViewModel in `@State` |
| `SeafoodDetailViewModel` | Single lookup flow with load, retry, and cancellation handling |
| `SeafoodDetailState` | idle, loading, failed, loaded |
| `MealService` | Async contract for list filtering and meal lookup with typed errors |
| `MealAPIClient` | URLSession, HTTP validation, decoding, executor isolation, and error classification |
| `Meal` | Immutable, Sendable list row with an API-provided identity |
| `MealDetails` | Full recipe model with ingredients, instructions, category, and area |

The production app keeps `MealAPIClient` and `SeafoodListViewModel` in `@State` at the application entry point so scene updates reuse the same instances. Debug scenarios live in `Source/Application/SeafoodScenarios.swift` and mount the same feature views with deterministic services for UI testing.

## Observation and identity

`SeafoodList` owns its `@MainActor @Observable` ViewModel in private `@State`. SwiftUI can recreate view values while reconnecting the same state storage, so initializers only assign dependencies and network work starts from view tasks.

`SeafoodListViewModel` imports Observation but not SwiftUI. Its state is externally read-only, and rendering is driven only by screen state. The service dependency and completion coordination are implementation details.

Rows use `idMeal` from the server and navigate with `NavigationLink`. The list stays in the same structural position as loading, error, content, and refresh states change, which keeps view identity stable while requests are cancelled, retried, or refreshed.

## State transitions

```swift
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
}
```

A successful empty response is represented as `loaded([])`. Refresh state is nested inside loaded content, so an initial failure cannot coexist with an active refresh.

| Operation | Success | Failure | Cancellation |
| --- | --- | --- | --- |
| Initial load / initial retry | Replace with loaded content | Show error and retry | Restore idle |
| Refresh / refresh retry | Replace content and clear refresh error | Preserve content and show retry | Preserve content and clear refresh activity |

Automatic appearance loads only from idle. Loaded content, including an empty collection, does not refetch on later appearances. A displayed failure requires explicit retry. Local search filters already loaded names with `localizedStandardContains` and never calls the API.

## Task ownership and cancellation

### Initial load and retry

A `.task(id:)` modifier awaits the ViewModel directly. The ViewModel awaits the service in the same task, so SwiftUI remains the owner of work tied to screen lifetime.

Retry changes the task identifier through a one-shot intent. State changes during loading do not change task identity or start duplicate requests.

### Pull-to-refresh

`.refreshable` awaits the full refresh so the system spinner follows its lifetime. Because disappearance cancellation is not modeled as explicitly as `.task`, the view owns one bounded refresh `Task`, forwards caller cancellation with `withTaskCancellationHandler`, and cancels the task in `onDisappear`.

The ViewModel deliberately stores no task handles. It models state and request admission; the SwiftUI boundary owns UI-triggered task lifetime.

### One request at a time

The ViewModel sets loading state on `MainActor` before awaiting the service. Another refresh or retry while loading returns without starting parallel work.

A rapid reappearance can happen before a cancelled request finishes. `loadIfNeeded()` waits for the in-flight operation to settle with checked continuations, then rechecks state. A cancelled waiting appearance resumes its own wait without cancelling work owned by another caller.

Cancellation is checked before admitting work and before publishing results. The API client also checks before the request, after the network response, and after decoding. Cancellation wins over late success and late error.

## Execution and isolation

`MealAPIClient.fetchMeals()` and `fetchMeal(id:)` are `@concurrent`. They move URL preparation and synchronous JSON decoding away from the caller's actor while staying inside the same task and preserving cancellation context.

The client validates HTTP before decoding the success payload. For the category filter, `meals: null` and an empty array are valid empty results; a missing `meals` field is a decoding failure. For lookup, `null` or an empty array maps to `MealAPIError.notFound`.

Typed `MealAPIError` keeps transport, HTTP, decoding, not-found, and cancellation cases separate. Cancellation is never displayed as a screen failure.

## Verification

Swift Testing exercises `MealAPIClient` through an injected ephemeral `URLSession` and test `URLProtocol`. Tests cover request shape, decoding, null/empty/missing payloads, HTTP errors, transport errors, and cancellation reaching `URLProtocol.stopLoading()`.

ViewModel tests use a controlled actor service that announces each request and waits for the test to provide a result. This makes async behavior deterministic without sleeps or polling loops. Assertions cover state transitions, overlapping call admission, content preservation, cancelled waiters, and rapid reentry.

XCTest UI tests run against Debug scenarios that mount the real SwiftUI screens with deterministic services. They cover scrolling, pull-to-refresh, empty results, retry, failed refresh, detail navigation, lifecycle cancellation, and parent updates preserving view identity.

To select a deterministic scenario, add launch arguments in the scheme:

```text
--seafood-scenario success
--seafood-scenario failure
--seafood-scenario empty
--seafood-scenario refreshFailure
--seafood-scenario lifecycle
--seafood-scenario refreshLifecycle
```

Scenario code is compiled only in Debug. A normal launch uses the real API.

## Scope and limitations

The API test key `1` is intended for development and educational use. The app has no remote search, pagination, persistence, video player, custom image cache, or offline mode. `AsyncImage` handles thumbnails independently of list and lookup requests.

The UI is a small native `List` and detail screen with Dynamic Type, VoiceOver labels, and system light/dark appearance. The project is intentionally scoped around concurrency behavior, not product completeness.

The Xcode toolchain can emit an AppIntents metadata extraction warning for targets that do not link AppIntents. Swift compiler warnings are treated as errors; the app does not add an unused AppIntents dependency to hide toolchain output.

## Tradeoffs

Several rough edges are deliberate because they keep the project focused on Swift Concurrency rather than turning it into a broader product exercise:

- User-facing strings are mostly hardcoded in views instead of being fully wired through localization.
- Loaded state is not persisted across app launches; the app demonstrates task lifecycle, not caching or restoration.
- There is no design system, custom component library, or visual polish layer beyond native SwiftUI controls.
- Networking is intentionally small: no request retry policy, auth layer, pagination abstraction, or image pipeline.
- Dependency injection is explicit and local to the feature instead of using a container.
- Debug scenarios are test fixtures, not a general mocking framework.

## References

- [SwiftUI model ownership and Observation](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [SwiftUI view tasks](https://developer.apple.com/documentation/swiftui/view/task(name:priority:file:line:_:))
- [SwiftUI refreshable](https://developer.apple.com/documentation/swiftui/view/refreshable(action:))
- [SE-0304: Structured concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
- [SE-0461: Async function isolation and @concurrent](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)

## License

MIT - see LICENSE.
