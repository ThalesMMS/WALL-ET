# Repository Guidelines

## Project Structure & Module Organization
- Source lives under `WALL-ET/` with feature layers such as `App/`, `Core/`, `Data/`, `Domain/`, `Presentation/`, `DesignSystem/`, `Resources/`, and `Tooling/`; mirror this when adding new types.
- Tests reside in `WALL-ETTests/` (unit & integration) and `WALL-ETUITests/` (UI). Match the source hierarchy, e.g. add `Domain/UseCases/CreateWalletUseCaseTests.swift` when touching `Domain/UseCases/CreateWalletUseCase.swift`.
- Package manifest (`Package.swift`) targets iOS 16+; the Xcode project `WALL-ET.xcodeproj` provides the `WALL-ET` app and test schemes.

## Build, Test, and Development Commands
- `swift build` / `swift build -c release` — resolve dependencies and compile via SwiftPM.
- `swift test` or `swift test --filter TypeName/testName` — run the SwiftPM test suite or focused tests.
- `xcodebuild -project WALL-ET.xcodeproj -scheme WALL-ET build` — build the app target for Xcode-based workflows.
- `xcodebuild -project WALL-ET.xcodeproj -scheme WALL-ET test -destination 'platform=iOS Simulator,name=iPhone 15'` — execute UI and integration tests in the simulator.

## Coding Style & Naming Conventions
- Swift 5.9/6, 4-space indentation, ~120 character lines; rely on Xcode's formatter to avoid churn.
- Types use PascalCase (`CryptoService`), methods/vars camelCase, enums singular, cases lowerCamelCase.
- One top-level type per file; name files after the type and place them in the appropriate module folder.

## Testing Guidelines
- Prefer XCTest; supplement with `import Testing` when lightweight test declarations help clarity.
- Keep coverage ≥80% in `Core` and `Domain`; stub network or crypto dependencies with fakes.
- Name files with `Tests.swift`; test functions start with `test...` (or `@Test`). Ensure determinism—no real network calls.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`) with concise, imperative subjects.
- PRs require a clear rationale, linked issues, testing notes, and screenshots for UI updates (include device + iOS version).
- Confirm all automated checks are green and mention any gaps or follow-up work.

## Security & Configuration Tips
- Never commit secrets or mainnet keys; use `KeychainAccess` and test with Bitcoin testnet data.
- Network settings live under `App/Configuration/` and `Resources/`; update Electrum servers there rather than hardcoding.
- Validate send flows against reachable Electrum endpoints and keep transaction values small during development.
