import SwiftUI

struct CreateWalletView: View {
    @StateObject private var viewModel: CreateWalletViewModel
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedOption: WalletCreationOption = .create
    @State private var showMnemonicView = false
    @State private var mnemonicInput = ""
    @State private var addressInput = ""
    
    init() {
        let createUseCase = DIContainer.shared.resolve(CreateWalletUseCaseProtocol.self)!
        let repository = DIContainer.shared.resolve(WalletRepositoryProtocol.self)!
        _viewModel = StateObject(wrappedValue: CreateWalletViewModel(
            createWalletUseCase: createUseCase,
            walletRepository: repository
        ))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Creation Options
                walletOptionsView
                
                // Wallet Details Form
                walletDetailsForm
                
                Spacer()
                
                // Action Button
                actionButton
            }
            .padding()
            .background(Color.Wallet.background)
            .navigationTitle("Add Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showMnemonicView) {
                if let mnemonic = viewModel.mnemonic {
                    MnemonicDisplayView(mnemonic: mnemonic) {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.createdWallet) { wallet in
                if wallet != nil && selectedOption == .create {
                    showMnemonicView = true
                } else if wallet != nil {
                    dismiss()
                }
            }
        }
    }
    
    private var walletOptionsView: some View {
        VStack(spacing: 12) {
            ForEach(WalletCreationOption.allCases, id: \.self) { option in
                WalletOptionRow(
                    option: option,
                    isSelected: selectedOption == option
                ) {
                    selectedOption = option
                }
            }
        }
    }
    
    private var walletDetailsForm: some View {
        VStack(spacing: 16) {
            // Wallet Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Wallet Name")
                    .font(.caption)
                    .foregroundColor(Color.Wallet.secondaryText)
                
                TextField("My Bitcoin Wallet", text: $viewModel.walletName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Wallet Type
            VStack(alignment: .leading, spacing: 8) {
                Text("Network")
                    .font(.caption)
                    .foregroundColor(Color.Wallet.secondaryText)
                
                Picker("Network", selection: $viewModel.walletType) {
                    ForEach(WalletType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Additional Input based on selection
            if selectedOption == .import {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recovery Phrase")
                        .font(.caption)
                        .foregroundColor(Color.Wallet.secondaryText)
                    
                    TextEditor(text: $mnemonicInput)
                        .frame(height: 100)
                        .padding(8)
                        .background(Color.Wallet.secondaryBackground)
                        .cornerRadius(Constants.UI.smallCornerRadius)
                }
            } else if selectedOption == .watchOnly {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bitcoin Address")
                        .font(.caption)
                        .foregroundColor(Color.Wallet.secondaryText)
                    
                    TextField("bc1q...", text: $addressInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
    }
    
    private var actionButton: some View {
        PrimaryButton(
            title: actionButtonTitle,
            action: handleAction,
            isLoading: viewModel.isCreating,
            isDisabled: !viewModel.isValidName
        )
    }
    
    private var actionButtonTitle: String {
        switch selectedOption {
        case .create: return "Create Wallet"
        case .import: return "Import Wallet"
        case .watchOnly: return "Add Watch-Only"
        }
    }
    
    private func handleAction() {
        Task {
            switch selectedOption {
            case .create:
                await viewModel.createWallet()
            case .import:
                await viewModel.importWallet(mnemonic: mnemonicInput)
            case .watchOnly:
                await viewModel.importWatchOnlyWallet(address: addressInput)
            }
        }
    }
}

enum WalletCreationOption: String, CaseIterable {
    case create = "Create New Wallet"
    case `import` = "Import Existing"
    case watchOnly = "Watch-Only"
    
    var icon: String {
        switch self {
        case .create: return "plus.circle"
        case .import: return "arrow.down.doc"
        case .watchOnly: return "eye"
        }
    }
    
    var description: String {
        switch self {
        case .create: return "Generate a new wallet with seed phrase"
        case .import: return "Restore from recovery phrase or private key"
        case .watchOnly: return "Monitor an address without private keys"
        }
    }
}

struct WalletOptionRow: View {
    let option: WalletCreationOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: option.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? Color.Wallet.bitcoinOrange : Color.Wallet.secondaryText)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.rawValue)
                        .font(.headline)
                        .foregroundColor(Color.Wallet.primaryText)
                    
                    Text(option.description)
                        .font(.caption)
                        .foregroundColor(Color.Wallet.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.Wallet.bitcoinOrange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                    .fill(isSelected ? Color.Wallet.bitcoinOrange.opacity(0.1) : Color.Wallet.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                    .stroke(isSelected ? Color.Wallet.bitcoinOrange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MnemonicDisplayView: View {
    let mnemonic: String
    let onDismiss: () -> Void
    @State private var hasCopied = false
    
    var words: [String] {
        mnemonic.split(separator: " ").map(String.init)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(Color.Wallet.warning)
                    
                    Text("Write Down Your Recovery Phrase")
                        .font(.title2)
                        .bold()
                    
                    Text("This is the only way to recover your wallet. Store it somewhere safe and never share it with anyone.")
                        .font(.body)
                        .foregroundColor(Color.Wallet.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // Mnemonic Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundColor(Color.Wallet.secondaryText)
                            
                            Text(word)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(Color.Wallet.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.Wallet.secondaryBackground)
                        .cornerRadius(Constants.UI.smallCornerRadius)
                    }
                }
                .padding()
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: {
                        UIPasteboard.general.string = mnemonic
                        hasCopied = true
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            hasCopied = false
                        }
                    }) {
                        HStack {
                            Image(systemName: hasCopied ? "checkmark" : "doc.on.doc")
                            Text(hasCopied ? "Copied!" : "Copy to Clipboard")
                        }
                        .foregroundColor(Color.Wallet.bitcoinOrange)
                    }
                    
                    PrimaryButton(title: "I've Written It Down", action: onDismiss)
                }
                .padding()
            }
            .navigationTitle("Recovery Phrase")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    CreateWalletView()
        .environmentObject(AppCoordinator())
}