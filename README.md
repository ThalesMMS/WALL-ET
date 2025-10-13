# WALL-ET Bitcoin Wallet (Work in progress)

Native, modern iOS app written in Swift 6 for managing Bitcoin wallets. It uses the MVVM-C architecture and Clean Architecture principles to ensure scalability, testability, and a clear separation of responsibilities.

## Current Features (Testnet)

- BIP39 + BIP32 key derivation with BIP84 (P2WPKH bech32 tb1…) on testnet
- Electrum integration (NWConnection):
  - Live balances via `blockchain.scripthash.get_balance` (sum over wallet addresses)
  - Transaction history via `…get_history` + verbose `…transaction.get` (computed net amounts, confirmations, status)
  - Broadcast raw transactions (`…transaction.broadcast`)
- Build, sign, and broadcast transactions on testnet (P2WPKH, signed with libsecp256k1)
- Gap-limit address discovery (m/84'/1'/0'/0/i) with persistence; ensures change path exists (m/…/1/0)
- Create wallet from mnemonic (24 words) and import mnemonic; keys stored securely in Keychain
- Real QR scanning with CodeScanner; supports BBQR multi-part progress UI
- Send / Receive only (Swap/Buy removed)
- Manage Wallets shows real Core Data items; delete, navigate to Wallet detail
- Empty states on Home/Transactions with Create/Import actions
- Network Settings: host/port/SSL and “Apply & Reconnect” to Electrum (set a mainnet server if using mainnet wallets)
- Dark mode toggle (AppStorage → preferredColorScheme)

Notes
- Mainnet/testnet can be selected when adding a wallet (BIP84 m/84'/0' for mainnet, m/84'/1' for testnet). Use a matching Electrum server in Network Settings.
- Price data and fiat conversion use the internal PriceDataService; historical fiat values are not backfilled yet.

* * *

## Detailed Directory Structure

The proposed directory structure follows Clean Architecture best practices. Each folder contains:

    WALL-ET/
    ├── App/                             # Entry point, lifecycle, and global configuration
    │   ├── AppMain.swift                # Primary @main struct defining the WindowGroup
    │   ├── AppDelegate.swift            # Integrations with third-party services (e.g., push notifications)
    │   ├── Configuration/               # .xcconfig files for Debug/Release/Staging
    │   └── Privacy/                     # PrivacyInfo.xcprivacy
    │
    ├── Core/                            # Low-level, app-agnostic utilities
    │   ├── Concurrency/                 # Helpers for async/await, @MainActor, etc.
    │   ├── Constants/                   # UserDefaults keys, UI insets, fixed URLs
    │   ├── DI/                          # Dependency Injection container (Swinject or manual)
    │   ├── Extensions/                  # Extensions for native types (Date, String, etc.)
    │   └── Observability/               # Structured logging, performance metrics (Firebase, etc.)
    │
    ├── Data/                            # Concrete implementations of Domain protocols
    │   ├── DTOs/                        # Data Transfer Objects (API responses)
    │   ├── Mappers/                     # Converters between DTOs and Domain models
    │   ├── Repositories/                # Repository implementations (e.g., WalletRepositoryImpl)
    │   └── Services/                    # Infrastructure services (APIService, KeychainService, DatabaseService)
    │
    ├── DesignSystem/                    # Shared, reusable design layer
    │   ├── Colors/                      # Color palette for light/dark mode
    │   ├── Components/                  # Generic components (PrimaryButton, AddressTextView, BalanceHeaderView)
    │   ├── Typography/                  # App typography definitions (font tokens)
    │   └── Assets.xcassets              # Icons, logos, images
    │
    ├── Domain/                          # Pure business rules (independent from UI and Data)
    │   ├── Models/                      # Core entities (Account, Wallet, Transaction, Blockchain)
    │   ├── Protocols/                   # Contracts/interfaces (e.g., IWalletRepository, ISendHandler)
    │   └── UseCases/                    # Domain orchestration (e.g., CreateWalletUseCase, SendBitcoinUseCase)
    │
    ├── Presentation/                    # MVVM-C layer bridging Domain and UI
    │   ├── Coordinators/                # Navigation flow controllers (AppCoordinator, SendCoordinator)
    │   ├── ViewModels/                  # Screen state and logic (BalanceViewModel, SendViewModel)
    │   └── Views/                       # SwiftUI interface
    │       ├── Screens/                 # Complete screens (BalanceView, SendView, SettingsView)
    │       └── Components/              # Feature-specific UI components
    │
    ├── Resources/                       # Static resources (.strings localization files)
    └── Tooling/                         # Build scripts, CI/CD, linters

* * *

## Technical Highlights

* **Clean Architecture**: Keeps business logic independent from frameworks, making the app more robust and easier to test.
* **MVVM-C**: Separates presentation logic (ViewModel) from navigation (Coordinator) while keeping SwiftUI views declarative.
* **Protocol-Oriented Programming**: Heavy use of protocols for dependency inversion, simplifying replacements and mocks for testing.
* **Swift Concurrency**: Uses `async/await` to keep asynchronous code clear and safe.
* **Dependency Injection**: Avoids singletons, making dependencies explicit and the code more modular.

* * *

## Features and Primary Screens

### Core Features

* **Multi-Account Management**: Supports multiple wallets, allowing the user to switch between them.
* **Creation and Restoration**:
  * **Creation**: Generates new wallets with a 12- or 24-word seed phrase.
  * **Restoration**: Imports existing wallets via mnemonic (BIP39 and non-standard), private key, or public address (watch-only mode).
* **Advanced Security**:
  * Password and biometric protection (Face ID/Touch ID).
  * **Duress Mode**: A secondary password that opens a different set of wallets to protect the user in high-risk situations.
* **Fee Management (Bitcoin)**: Transaction fee estimation and advanced options such as Replace-by-Fee (RBF).

### 1. Balance Screen

The primary screen where the user views their assets.

* **Total Balance**: Displayed in the user's base fiat currency with an option to hide values.
* **Wallet List**: Displays each active wallet with:
  * Cryptocurrency icon and name (e.g., Bitcoin).
  * Balance in crypto and its fiat equivalent.
  * Price change over the last 24 hours.
  * Synchronization status.
* **Quick Actions**: Primary buttons for **Send**, **Receive**, and **Scan QR Code**.
* **Management and Sorting**:
  * Button to open the "Manage Wallets" screen (add/remove assets).
  * Options to sort by balance, name, or price change.
* **Pull-to-Refresh**: Updates balances and prices.

### 2. Transactions Screen

A complete history of all transactions with advanced filtering options.

* **Transaction List**: Grouped by date ("Today", "Yesterday", etc.). Each item shows:
  * Transaction type (send, receive, etc. icon).
  * Recipient/sender.
  * Primary amount (crypto) and secondary amount (fiat).
  * Status (Pending, Confirmed, Failed).
* **Advanced Filters**: A filter panel to refine by:
  * **Blockchain**: Show transactions from a single network (e.g., Bitcoin).
  * **Token**: Filter by a specific cryptocurrency.
  * **Contact**: Display transactions to or from a saved contact.
  * **Type**: Filter by Sent, Received, Swap, Approvals.
  * **Hide Suspicious Transactions**: Filter to remove potential spam transactions.
* **Transaction Detail Screen**:
  * Detailed information: status, date, amount, network fee, sender, recipient.
  * Link to view the transaction on a block explorer.
  * **Speed Up** or **Cancel** options for Bitcoin transactions with RBF enabled.

### 3. Settings Screen

The hub for personalization and security.

* **Manage Wallets**: Add new wallets, create, restore, or view existing seed phrases.
* **Security**:
  * **Password**: Enable/disable and change the password.
  * **Biometrics**: Enable Face ID/Touch ID.
  * **Auto-Lock**: Define the automatic lock timer.
  * **Duress Mode**: Configure an alternate password and select which wallets appear.
* **Appearance**:
  * **Theme**: Light, Dark, or Automatic (System).
  * **Base Currency**: Choose the main fiat currency (USD, BRL, EUR, etc.).
  * **App Icon**: Allow the user to choose between different icons.
* **App Backup**: Create an encrypted backup of wallets, settings, and contacts, saving to a local file or iCloud.
* **dApp Connections (WalletConnect)**: View and manage active sessions with decentralized applications.
* **About**: App version information, links to social networks, official website, and terms of service.
