# [Demo Name]

[![CI](https://github.com/kamilgomolka/<repo-name>/actions/workflows/ci.yml/badge.svg)](https://github.com/kamilgomolka/<repo-name>/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/iOS-26.0%2B-000000.svg)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-26-1575F9.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

<!-- Replace <repo-name> in the CI badge above, then delete this line once the sections below are filled in. -->

<!-- One or two sentences: what this demo explores and why (e.g. the WWDC session, article, or interview prompt it's based on — link the source material if there is one). Mention target platform(s) if not "iPhone + iPad" (e.g. "iPad only"). -->

## What It Shows

<!--
One bullet per notable API/technique/pattern this demo showcases, e.g.:

- `UITabBarController.mode = .tabSidebar` — floating tab bar, collapsible sidebar

If the app has more than one independent screen reachable from the root menu, use a table instead:

| Demo | What it shows | Key API |
| --- | --- | --- |
| ... | ... | ... |
-->

## Screenshots / Recordings

<!--
Drag a screenshot or screen recording into a GitHub PR/issue comment (or the editor toolbar when editing this file on GitHub) to get a hosted URL, then embed it below:

<img width="400" alt="Description" src="https://github.com/user-attachments/assets/..." />
https://github.com/user-attachments/assets/...
-->

## Architecture

Plain SwiftUI — no UIKit app lifecycle, no Storyboards/XIBs, no third-party dependencies. One `View` per feature under `Source/Features/`, pushed from `MainView` onto a `NavigationStack` in `App`.

<!-- State the specific pattern this demo uses if it's not plain MVC (MVVM, coordinator, etc.), and why. -->

```
Config/                                     # Project and target configuration, kept out of the Xcode UI
├── Local.xcconfig.example                  # Template for the untracked Local.xcconfig (Team ID)
├── Project/
│   ├── ProjectBase.xcconfig                # Platform, Swift language mode and strictness, signing style
│   ├── ProjectDebug.xcconfig               # Warnings-as-errors
│   └── ProjectRelease.xcconfig
└── Target/
    ├── TargetBase.xcconfig                 # Versioning, product name, bundle identifier, actor isolation
    ├── TargetDemoMealRecipes.xcconfig         # App: generated Info.plist keys, asset catalog names
    ├── TargetDemoMealRecipesTests.xcconfig
    └── TargetDemoMealRecipesUITests.xcconfig

DemoMealRecipes/
├── Source/
│   ├── Application/
│   │   └── App.swift                       # `@main` SwiftUI App, `WindowGroup` + `NavigationStack`
│   ├── MainView.swift                      # Entry point: one button per feature
│   └── Features/
│       └── ...                             # One folder/file per feature demo
└── SupportingFiles/
    ├── Assets.xcassets
    └── Localizable.xcstrings
```

Xcode's own default warning flags still live in `project.pbxproj`; everything this project decides for itself lives in `Config/`.

## Trade-offs & Production Notes

<!-- Replace or extend the template-level notes below with ones specific to this demo. This is where deliberate omissions belong, so a reader can tell a shortcut from an oversight. -->

- **iOS 26 only.** The deployment target tracks the newest SDK so demos can use current APIs without availability checks. A shipping app would support at least two major versions back.
- **No coordinator, router, or dependency injection.** Features are pushed directly by `NavigationLink` from `MainView`. At production scale this becomes a navigation abstraction with injected dependencies; at demo scale it would be indirection without a payoff.
- **Localization is wired up, not completed.** Screen titles go through `Localizable.xcstrings` so the string catalog and its generated symbols stay exercised; incidental demo copy is inlined.
- **Test coverage is a smoke layer, not a safety net.** A unit test that the SwiftUI view graph builds, plus UI tests that launch the app and open the sample feature. Enough to keep CI honest about the app actually starting.

## Requirements

- Xcode 26 or later
- iOS 26.0+ (`IPHONEOS_DEPLOYMENT_TARGET`)
- Swift 6 language mode, strict concurrency, strict memory safety, `MainActor` default isolation

## Getting Started

```bash
git clone https://github.com/kamilgomolka/<repo-name>.git
cd <repo-name>
open DemoMealRecipes.xcodeproj
```

Build and run the `DemoMealRecipes` scheme on an iOS 26+ Simulator. Signing is not required for the Simulator. To run on a device, copy the local configuration template and fill in your Apple Developer Team ID:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

`Config/Local.xcconfig` is untracked, so no Team ID ever lands in version control.

## Tooling

```bash
make build         # compile for the Simulator
make format        # apply swift-format in place
make destinations  # list available Simulator destinations
```

`swift-format` ships with the Xcode toolchain, so there is nothing to install.
Automation: Command `make format` is configured as a Run Script build phase (before Compile Sources), so every build formats sources in place.

Override the Simulator with `make build SIMULATOR='iPhone 17 Pro'`.

## Built with an Agentic Workflow

This repository doubles as an experiment in AI-assisted development. The specification, architectural decisions, code review, and verification are mine; [Cursor](https://cursor.com/) executes against them in a **Plan > Review > Implement > Review** loop. Nothing lands without passing the review step and a green CI run.

## License

MIT — see [LICENSE](LICENSE).
