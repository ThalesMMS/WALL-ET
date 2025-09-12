import SwiftUI

struct BackupFlowView: View {
    @State private var currentStep = BackupStep.intro
    @State private var seedPhrase = ""
    @State private var verificationWords: [String] = ["", "", ""]
    @State private var verificationIndices: [Int] = []
    @State private var backupPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    @Environment(\.dismiss) var dismiss
    
    enum BackupStep {
        case intro
        case display
        case verify
        case cloud
        case complete
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                ModernTheme.Colors.background
                    .ignoresSafeArea()
                
                VStack {
                    // Progress Indicator
                    BackupProgressBar(currentStep: currentStep)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Content
                    Group {
                        switch currentStep {
                        case .intro:
                            BackupIntroView(onContinue: generateSeedPhrase)
                        case .display:
                            SeedPhraseDisplayView(
                                seedPhrase: seedPhrase,
                                onContinue: { currentStep = .verify }
                            )
                        case .verify:
                            SeedPhraseVerificationView(
                                indices: verificationIndices,
                                words: $verificationWords,
                                onVerify: verifySeedPhrase
                            )
                        case .cloud:
                            CloudBackupView(
                                password: $backupPassword,
                                confirmPassword: $confirmPassword,
                                onBackup: performCloudBackup,
                                onSkip: { currentStep = .complete }
                            )
                        case .complete:
                            BackupCompleteView(onDone: { dismiss() })
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
                    .animation(.spring(), value: currentStep)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if currentStep != .intro {
                        Button("Back") {
                            withAnimation {
                                previousStep()
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func generateSeedPhrase() {
        do {
            seedPhrase = try WalletBackupService.shared.generateSeedPhrase()
            
            // Save temporarily for verification
            UserDefaults.standard.set(seedPhrase, forKey: "temp_mnemonic_for_verification")
            
            // Generate verification indices
            let wordCount = seedPhrase.split(separator: " ").count
            verificationIndices = Array(0..<wordCount).shuffled().prefix(3).sorted()
            
            currentStep = .display
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func verifySeedPhrase() {
        let words = seedPhrase.split(separator: " ").map(String.init)
        var allCorrect = true
        
        for (index, wordIndex) in verificationIndices.enumerated() {
            if words[wordIndex].lowercased() != verificationWords[index].lowercased() {
                allCorrect = false
                break
            }
        }
        
        if allCorrect {
            WalletBackupService.shared.markSeedPhraseAsVerified()
            currentStep = .cloud
        } else {
            errorMessage = "Incorrect words. Please try again."
            showError = true
            verificationWords = ["", "", ""]
        }
    }
    
    private func performCloudBackup() {
        guard backupPassword == confirmPassword else {
            errorMessage = "Passwords don't match"
            showError = true
            return
        }
        
        guard backupPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            showError = true
            return
        }
        
        WalletBackupService.shared.backupToiCloud(password: backupPassword) { result in
            switch result {
            case .success:
                currentStep = .complete
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func previousStep() {
        switch currentStep {
        case .intro:
            break
        case .display:
            currentStep = .intro
        case .verify:
            currentStep = .display
        case .cloud:
            currentStep = .verify
        case .complete:
            currentStep = .cloud
        }
    }
}

struct BackupProgressBar: View {
    let currentStep: BackupFlowView.BackupStep
    
    private var progress: Double {
        switch currentStep {
        case .intro: return 0.2
        case .display: return 0.4
        case .verify: return 0.6
        case .cloud: return 0.8
        case .complete: return 1.0
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ModernTheme.Colors.secondaryBackground)
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(ModernTheme.Colors.primaryGradient)
                    .frame(width: geometry.size.width * progress, height: 8)
                    .animation(.spring(), value: progress)
            }
        }
        .frame(height: 8)
    }
}

struct BackupIntroView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: ModernTheme.Spacing.xl) {
            Spacer()
            
            Image(systemName: "key.fill")
                .font(.system(size: 80))
                .foregroundStyle(ModernTheme.Colors.primaryGradient)
            
            VStack(spacing: ModernTheme.Spacing.md) {
                Text("Backup Your Wallet")
                    .font(ModernTheme.Typography.title)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Text("Your recovery phrase is the only way to restore your wallet if you lose access to this device.")
                    .font(ModernTheme.Typography.body)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: ModernTheme.Spacing.md) {
                WarningItem(
                    icon: "pencil.and.ellipsis.rectangle",
                    text: "Write down your recovery phrase"
                )
                
                WarningItem(
                    icon: "lock.shield.fill",
                    text: "Store it in a safe place"
                )
                
                WarningItem(
                    icon: "eye.slash.fill",
                    text: "Never share it with anyone"
                )
                
                WarningItem(
                    icon: "xmark.shield.fill",
                    text: "Never enter it on suspicious websites"
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: ModernTheme.Radius.large)
                    .fill(ModernTheme.Colors.warning.opacity(0.1))
            )
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: onContinue) {
                Text("I Understand, Continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
}

struct WarningItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: ModernTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(ModernTheme.Colors.warning)
                .frame(width: 30)
            
            Text(text)
                .font(ModernTheme.Typography.callout)
                .foregroundColor(ModernTheme.Colors.textPrimary)
        }
    }
}

struct SeedPhraseDisplayView: View {
    let seedPhrase: String
    let onContinue: () -> Void
    
    @State private var copied = false
    @State private var blurred = false
    
    private var words: [String] {
        seedPhrase.split(separator: " ").map(String.init)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: ModernTheme.Spacing.lg) {
                Text("Your Recovery Phrase")
                    .font(ModernTheme.Typography.title2)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                    .padding(.top)
                
                Text("Write down these words in the exact order")
                    .font(ModernTheme.Typography.body)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
                
                // Seed phrase grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: ModernTheme.Spacing.md) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        SeedWordView(number: index + 1, word: word)
                            .blur(radius: blurred ? 10 : 0)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: ModernTheme.Radius.large)
                        .fill(ModernTheme.Colors.secondaryBackground)
                )
                .overlay(
                    Button(action: { blurred.toggle() }) {
                        Image(systemName: blurred ? "eye" : "eye.slash")
                            .font(.system(size: 20))
                            .foregroundColor(ModernTheme.Colors.textSecondary)
                            .padding()
                    },
                    alignment: .topTrailing
                )
                .padding(.horizontal)
                
                Button(action: copySeedPhrase) {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy to Clipboard")
                    }
                    .font(ModernTheme.Typography.callout)
                    .foregroundColor(ModernTheme.Colors.primary)
                }
                .padding()
                
                Text("⚠️ Never share your recovery phrase with anyone!")
                    .font(ModernTheme.Typography.caption)
                    .foregroundColor(ModernTheme.Colors.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer(minLength: 40)
                
                Button(action: onContinue) {
                    Text("I've Written It Down")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
            }
        }
    }
    
    private func copySeedPhrase() {
        UIPasteboard.general.string = seedPhrase
        copied = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct SeedWordView: View {
    let number: Int
    let word: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(number).")
                .font(ModernTheme.Typography.caption)
                .foregroundColor(ModernTheme.Colors.textSecondary)
                .frame(width: 25, alignment: .trailing)
            
            Text(word)
                .font(ModernTheme.Typography.callout.monospaced())
                .foregroundColor(ModernTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: ModernTheme.Radius.small)
                .fill(ModernTheme.Colors.tertiaryBackground)
        )
    }
}

// MARK: - Missing View Components

struct SeedPhraseVerificationView: View {
    let indices: [Int]
    @Binding var words: [String]
    let onVerify: () -> Void
    
    var body: some View {
        VStack(spacing: ModernTheme.Spacing.lg) {
            VStack(spacing: ModernTheme.Spacing.sm) {
                Text("Verify Your Recovery Phrase")
                    .font(ModernTheme.Typography.largeTitle)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Text("Enter the words at the positions shown below")
                    .font(ModernTheme.Typography.body)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            VStack(spacing: ModernTheme.Spacing.md) {
                ForEach(Array(indices.enumerated()), id: \.offset) { index, position in
                    HStack {
                        Text("Word #\(position + 1)")
                            .font(ModernTheme.Typography.callout)
                            .foregroundColor(ModernTheme.Colors.textSecondary)
                            .frame(width: 80, alignment: .leading)
                        
                        TextField("Enter word", text: $words[index])
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
            
            Spacer()
            
            Button(action: onVerify) {
                Text("Verify")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ModernTheme.Colors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(ModernTheme.Radius.medium)
            }
            .padding()
        }
    }
}

struct CloudBackupView: View {
    @Binding var password: String
    @Binding var confirmPassword: String
    let onBackup: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: ModernTheme.Spacing.lg) {
            VStack(spacing: ModernTheme.Spacing.sm) {
                Text("Cloud Backup")
                    .font(ModernTheme.Typography.largeTitle)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Text("Secure your recovery phrase with iCloud")
                    .font(ModernTheme.Typography.body)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            VStack(spacing: ModernTheme.Spacing.md) {
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
            }
            .padding(.vertical)
            
            Spacer()
            
            VStack(spacing: ModernTheme.Spacing.sm) {
                Button(action: onBackup) {
                    Text("Backup to iCloud")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(ModernTheme.Colors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(ModernTheme.Radius.medium)
                }
                
                Button(action: onSkip) {
                    Text("Skip for Now")
                        .font(ModernTheme.Typography.callout)
                        .foregroundColor(ModernTheme.Colors.textSecondary)
                }
            }
            .padding()
        }
    }
}

struct BackupCompleteView: View {
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: ModernTheme.Spacing.lg) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(ModernTheme.Colors.success)
            
            VStack(spacing: ModernTheme.Spacing.sm) {
                Text("Backup Complete!")
                    .font(ModernTheme.Typography.largeTitle)
                    .foregroundColor(ModernTheme.Colors.textPrimary)
                
                Text("Your wallet is now backed up and secure")
                    .font(ModernTheme.Typography.body)
                    .foregroundColor(ModernTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ModernTheme.Colors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(ModernTheme.Radius.medium)
            }
            .padding()
        }
    }
}