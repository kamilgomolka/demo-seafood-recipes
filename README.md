# Meal Recipes

An iPhone demo of SwiftUI state, view identity, and cooperative cancellation using a real HTTP API. It displays Seafood recipes from [TheMealDB](https://www.themealdb.com/documentation), with initial loading, pull-to-refresh, empty results, and retry.

## Run

- Xcode 26 with Swift 6.2 or newer; verified toolchain: Xcode 26.6 / Swift 6.3.3.
- Swift 6 language mode, complete concurrency checking, MainActor default isolation, and Approachable Concurrency.
- iOS 26.0+, iPhone portrait. No third-party dependencies.

Open `DemoMealRecipes.xcodeproj` and run the `DemoMealRecipes` scheme. Simulator builds do not require signing. For a device, copy `Config/Local.xcconfig.example` to the untracked `Config/Local.xcconfig` and set your development team.

```sh
make build
make test
make lint
```

The default destination is iPhone 17 Pro. Override it with `SIMULATOR='device name'`. The existing build phase runs `swift-format` in place before compilation.

## Architecture

| Type | Responsibility |
| --- | --- |
| `MealsView` | List, presentation, gestures, and ownership of work tied to the screen |
| `MealsViewModel` | Observable state, admission of requests, and state transitions |
| `MealsState` | Initial loading/failure and loaded content with its refresh state |
| `MealService` | One asynchronous, typed-throwing operation; injection boundary for tests |
| `MealAPIClient` | URLSession, HTTP validation, decoding, and error classification |
| `Meal` | Immutable, Sendable row with an API-provided identity |

The feature is in `DemoMealRecipes/Source/Features/Meals/`. The application entry point assembles dependencies. Debug scenarios are in `Source/Application/MealScenarios.swift`; they use the same screen and ViewModel as the live application.

## Observation and identity

`MealsView` owns its `@MainActor @Observable` ViewModel in private `@State`. SwiftUI reconnects that state storage when it recreates a view value with the same identity. Initializers only assign dependencies; HTTP work begins in a view task.

`MealsViewModel` imports Observation and has no SwiftUI dependency. Its state is externally read-only. The service and internal completion signals are implementation details; only screen state drives rendering.

Each row uses `idMeal` from the server. The List remains in the same structural position as loading, error, and content change. Refresh updates its collection without assigning a new identity to the List. Existing content remains visible until a successful replacement arrives.

## State transitions

```swift
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
}
```

A successful empty response is `loaded([])`. Refresh state is nested inside loaded content, so an initial failure cannot coexist with an active refresh.

| Operation | Success | Failure | Cancellation |
| --- | --- | --- | --- |
| Initial load / initial retry | Replace with loaded content | Show error and retry | Restore idle |
| Refresh / refresh retry | Replace content and clear refresh error | Preserve content and show retry | Preserve content and clear refresh activity |

Automatic appearance loads from idle. Loaded content, including an empty collection, does not trigger another request. A displayed failure requires explicit retry. Background/foreground transitions do not initiate fetching.

## Task ownership and cancellation

### Initial load and retry

A `.task(id:)` modifier on the stable List awaits the ViewModel directly, which in turn awaits the service. These calls execute within the calling task. SwiftUI owns that task and cancels it when the screen is removed.

The task identifier changes only when the user presses retry. A separate one-shot retry intent distinguishes that action from subsequent appearances with the same identifier. State changes during loading do not change task identity.

### Pull-to-refresh

`.refreshable` awaits the full refresh so the system spinner follows its lifetime. Its documentation does not promise the same removal cancellation behavior as `.task`.

To make disappearance cancellation explicit, the view owns one refresh Task. It awaits that Task, forwards cancellation from the caller with `withTaskCancellationHandler`, and cancels it in `onDisappear`. Cleanup clears only the matching handle. This is a deliberately bounded unstructured task at the UI boundary; the ViewModel stores no task handles.

### One request at a time

The ViewModel sets loading state on MainActor before awaiting the service. Another explicit refresh or retry while loading returns without starting more work. The operation restores its final state and releases completion waiters without an intervening suspension.

A rapid reappearance can arrive before a cancelled request finishes. `loadIfNeeded()` waits for the current operation to settle using a local AsyncStream completion signal, then rechecks state. Finishing the stream signals completion; no values are sent. Cancelling a waiting appearance ends its wait without cancelling the request owned by another caller. This prevents a new appearance from observing loading, returning early, and leaving the screen idle after the previous request finally cancels.

Cancellation is checked before admitting work and before publishing a result. The client also checks before the request, after the network response, and after decoding. A dependency that returns success despite cancellation cannot publish that result. Cancellation takes precedence over presenting a late error.

MainActor protects access to state, but an async method can interleave with another caller at an await. Request admission and post-await state changes therefore have explicit rules.

## Execution and isolation

`MealAPIClient.fetchMeals()` is `@concurrent`. It runs preparation and JSON decoding outside the caller's actor while remaining in the same task. The immutable client and model are Sendable; decoded types and the service contract have explicit nonisolated declarations. Each request owns its JSONDecoder.

URLSession suspends during network I/O. The reason for the explicit executor change is the synchronous decoding work. `@concurrent` does not create a Task and does not discard cancellation context. With Approachable Concurrency, a nonisolated async declaration alone would not express this executor change.

The client validates HTTP before decoding the success payload. `meals: null` and an empty array are valid empty results; a missing `meals` field is a decoding failure. Typed `MealAPIError` preserves underlying transport/decoding errors and HTTP status for diagnosis. Cancellation is a separate case and is never shown as a screen failure.

## Verification

Swift Testing exercises the client through an injected ephemeral URLSession and test URLProtocol. Per-session fixture IDs isolate parallel tests; a Mutex protects the registry accessed by synchronous Foundation callbacks. Tests cover request shape, decoding, null/empty/missing payloads, HTTP errors, underlying transport errors, and cancellation reaching `URLProtocol.stopLoading()`.

ViewModel tests use a controlled actor service that announces each request and waits for the test to provide a result. It deliberately permits a response after cancellation. Assertions cover state transitions, admission of overlapping calls, preservation of content, cancelled waiters, and rapid reentry. There are no timing sleeps or polling loops.

XCTest UI tests exercise scrolling, pull-to-refresh, empty results, retry, and failed refresh. The Debug lifecycle host mounts/unmounts the actual MealsView while retaining its ViewModel and withholding service responses. It checks both cancellation paths, a return before cancellation settles, and parent updates preserving view identity. The initial-load host intentionally reports cancellation before a test explicitly completes the pending response. The refresh host unmounts the screen as soon as refresh starts and completes the cancelled request, allowing XCTest to finish the gesture. The failed-refresh fixture remains unavailable until the test explicitly restores the service, so recovery does not depend on the number of callbacks emitted by a gesture.

To select a deterministic scenario, add launch arguments in the scheme:

```text
--meal-scenario success
--meal-scenario failure
--meal-scenario empty
--meal-scenario refreshFailure
--meal-scenario lifecycle
--meal-scenario refreshLifecycle
```

Fixtures use local placeholders for images. Hosted unit tests select an offline scenario through the XCTest launch environment. Scenario code is compiled only in Debug. A normal launch uses the real API.

## Scope and limitations

The API test key `1` is intended for development and educational use. There are no details, search, pagination, persistence, or custom image cache. AsyncImage handles individual thumbnails independently of the list request. The initial screen is intentionally a small native List with Dynamic Type, VoiceOver labels, and system light/dark appearance.

The Xcode toolchain can emit an AppIntents metadata extraction warning for targets that do not link AppIntents. Swift compiler warnings are treated as errors; the app does not add an unused AppIntents dependency to hide toolchain output.

## References

- [SwiftUI model ownership and Observation](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [SwiftUI view tasks](https://developer.apple.com/documentation/swiftui/view/task(name:priority:file:line:_:))
- [SwiftUI refreshable](https://developer.apple.com/documentation/swiftui/view/refreshable(action:))
- [SE-0304: Structured concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
- [SE-0461: Async function isolation and @concurrent](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)

## License

MIT — see LICENSE.
