# Repository Guidelines

## Project Structure & Modules
- Source: `WALL-ET/` (library target `WALL-ET`). Key layers: `App/`, `Core/`, `Data/`, `Domain/`, `Presentation/`, `DesignSystem/`, `Resources/`, `Tooling/`.
- Tests: `WALL-ETTests/` (unit/integration) and `WALL-ETUITests/` (UI, Xcode project).
- SwiftPM: `Package.swift` (iOS 16+, library product). Xcode project: `WALL-ET.xcodeproj`.

## Build, Test, and Development Commands
- Resolve + build (SwiftPM): `swift build` (use `-c release` for optimized).
- Run tests (SwiftPM): `swift test` (example: `swift test --filter RealCryptoTests/testGeneratePrivateKey`).
- Xcode build: `xcodebuild -project WALL-ET.xcodeproj -scheme WALL-ET build`.
- Xcode tests (including UI): `xcodebuild -project WALL-ET.xcodeproj -scheme WALL-ET test -destination 'platform=iOS Simulator,name=iPhone 15'`.

## Coding Style & Naming Conventions
- Language: Swift 5.9/6. Indentation: 4 spaces; line length ~120.
- Types: PascalCase (`CryptoService`, `BalanceViewModel`). Methods/vars: camelCase. Enums: singular (`Network`), cases lowerCamelCase.
- Protocols: no `I` prefix; add `Protocol` suffix only when disambiguating.
- Files mirror types: one top-level type per file; group by layer (e.g., `Domain/UseCases/CreateWalletUseCase.swift`).
- Formatting: use Xcode’s formatter. Avoid churn-only reformatting.

## Testing Guidelines
- Frameworks: XCTest (primary) and Swift Testing (`import Testing`) where appropriate.
- Location: mirror source structure under `WALL-ETTests/` (e.g., `Core/`, `Helpers/`).
- Naming: files end with `Tests.swift`; functions start with `test...` or `@Test` cases.
- Coverage: aim ≥ 80% for `Domain` and `Core`. Provide deterministic tests (no network; use fakes/mocks).
- Run focused tests: `swift test --filter <TypeName>/<testName>`.

## Commit & Pull Request Guidelines
- Commits: concise, imperative subject. Prefer Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`).
- PRs: clear description, linked issues, rationale, testing notes, and risks. Include screenshots for UI changes (device + iOS version).
- Status: all checks green; tests required for new domain/data logic.

## Security & Configuration
- Never commit secrets or real keys. Use `KeychainAccess` for credentials and test with Bitcoin testnet.
- Environment/config: keep settings under `App/Configuration/` and `Resources/` (e.g., privacy, strings). Avoid hardcoded endpoints.

## Current Progress
- Testnet‑only wallet with BIP39 + BIP32 (BIP84 P2WPKH tb1…) derivation.
- Electrum integration for balances, history (verbose parsing), and broadcasting.
- Real send flow: build, sign (libsecp256k1), and broadcast on testnet.
- Gap‑limit discovery (m/84'/1'/0'/0/i) persisted; change path ensured.
- CodeScanner wired for QR/BBQR; legacy placeholder removed.
- Settings → Manage Wallets uses Core Data (list, delete, navigate to detail).
- Empty states (Home/Transactions) with Create/Import actions.
- Network Settings (testnet server host/port/SSL) with apply + reconnect.
- Dark mode toggle via AppStorage + preferredColorScheme.
 - Home quick actions wired (Send/Receive open sheets).
 - Add Wallet supports mainnet/testnet selection; repository derives correct coin type.

Developer tips
- Build app target `WALL-ET` in Xcode; simulator iPhone 16 works out of the box.
- For sending tx: ensure Electrum testnet server reachable; use small amounts and confirm UTXOs appear under the first derived address.
 - For mainnet wallets, update Network Settings to a mainnet Electrum server before fetching history or broadcasting.
 - Price/fiat is live for totals; historical fiat values are not backfilled yet.
