# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WALL-ET is a native iOS Bitcoin wallet written in Swift/SwiftUI, following MVVM‑C with Clean Architecture. It supports BIP39/BIP32 derivation (BIP84), Electrum networking for balances/history/broadcast, and testnet/mainnet wallets.

## Build Commands

```bash
# Build the project
xcodebuild -project WALL-ET.xcodeproj -scheme WALL-ET -configuration Debug build

# Run tests
xcodebuild test -project WALL-ET.xcodeproj -scheme WALL-ET -destination 'platform=iOS Simulator,name=iPhone 15'

# Clean build
xcodebuild clean -project WALL-ET.xcodeproj -scheme WALL-ET

# Build for release
xcodebuild -project WALL-ET.xcodeproj -scheme WALL-ET -configuration Release build
```

## Architecture

The codebase follows Clean Architecture with clear separation of concerns:

### Layer Structure
- **App/**: Entry point containing `AppMain.swift` (with @main) and `AppDelegate.swift`. Handles app lifecycle and global configurations.
- **Core/**: Foundation utilities including DI container, extensions (String, Double), observability/logging, and app constants.
- **Domain/**: Business logic layer with models (Wallet, Transaction), protocols for repositories and services, and use cases (CreateWalletUseCase, SendBitcoinUseCase).
- **Data/**: Implementation layer with repositories (WalletRepository), services (KeychainService, StorageService), DTOs, and mappers.
- **Presentation/**: MVVM-C layer with coordinators (AppCoordinator), view models (BalanceViewModel, CreateWalletViewModel), and SwiftUI views.
- **DesignSystem/**: Reusable UI components, colors, typography definitions.

### Key Architectural Patterns
- **MVVM-C Pattern**: ViewModels handle presentation logic, Coordinators manage navigation flow, Views remain declarative SwiftUI.
- **Protocol-Oriented**: Heavy use of protocols for dependency inversion (e.g., WalletRepositoryProtocol, KeychainServiceProtocol).
- **Dependency Injection**: DIContainer manages dependencies, avoiding singletons.

### Domain Models
- `Wallet`: Core entity containing wallet metadata, type (Bitcoin/Testnet), and associated accounts.
- `Account`: Represents individual addresses within a wallet with balance and transaction history.
- `Transaction`: Bitcoin transaction data model.
- `Balance`: Tracks confirmed/unconfirmed satoshi amounts with BTC conversion helpers.

## Important Implementation Notes

- Entry point: `App/AppMain.swift` injects `AppCoordinator` as an environment object.
- Bitcoin:
  - BIP39 seed → BIP32 (HMAC‑SHA512) → BIP84 path m/84'/coin'/account'/change/address
  - libsecp256k1 used for signing and CKDpriv (tweak addition)
  - RIPEMD-160 implemented in Swift for hash160
- Electrum: NWConnection JSON‑RPC client used for scripthash balance/history and broadcasting.
- Network selection: Add Wallet lets you choose mainnet/testnet. Use matching Electrum server in Network Settings.
- QR: CodeScanner integrated; BBQR multi‑part progress supported.
- Amounts stored as satoshis (Int64); conversions via extensions/utilities.
