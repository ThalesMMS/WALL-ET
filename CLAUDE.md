# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WALL-ET is a native iOS Bitcoin wallet application written in Swift, using SwiftUI for UI and following MVVM-C architecture with Clean Architecture principles. The app manages Bitcoin wallets with features like multi-account support, transaction management, and security features including biometric authentication.

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

- The app uses two conflicting entry points: `WALL_ETApp.swift` (with SwiftData) and `App/AppMain.swift` (with proper architecture). Use `AppMain.swift` as the primary entry point.
- Extensions in `Core/Extensions/` provide Bitcoin-specific conversions (satoshis to BTC).
- Security features include Face ID/Touch ID support and a "duress mode" for protection.
- The app supports both mainnet Bitcoin and testnet.
- All amounts are stored as satoshis (Int64) and converted for display.