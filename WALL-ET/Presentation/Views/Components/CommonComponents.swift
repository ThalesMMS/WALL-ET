import SwiftUI

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Loading View
struct LoadingView: View {
    let message: String?
    
    init(message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).opacity(0.95))
    }
}

// MARK: - Error View
struct ErrorView: View {
    let error: Error
    let retry: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.headline)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let retry = retry {
                Button(action: retry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            
            Spacer()
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Card Container
struct CardContainer<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

// MARK: - Badge View
struct BadgeView: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

// MARK: - Copy Button
struct CopyButton: View {
    let text: String
    @State private var copied = false
    
    var body: some View {
        Button(action: {
            UIPasteboard.general.string = text
            copied = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copied = false
            }
        }) {
            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .foregroundColor(copied ? .green : .orange)
                .animation(.easeInOut(duration: 0.2), value: copied)
        }
    }
}

// MARK: - Amount Input Field
struct AmountInputField: View {
    @Binding var amount: String
    let symbol: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .decimalPad
    
    var body: some View {
        HStack {
            TextField(placeholder, text: $amount)
                .keyboardType(keyboardType)
                .font(.system(.body, design: .monospaced))
            
            Text(symbol)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Segmented Picker
struct SegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    
    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { option in
                Text(option.1).tag(option.0)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var isMonospaced: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if isMonospaced {
                Text(value)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(valueColor)
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(valueColor)
            }
        }
    }
}

// MARK: - Dismissable Sheet Header
struct DismissableSheetHeader: View {
    let title: String
    let dismiss: () -> Void
    
    var body: some View {
        HStack {
            Button("Cancel", action: dismiss)
                .foregroundColor(.orange)
            
            Spacer()
            
            Text(title)
                .font(.headline)
            
            Spacer()
            
            // Invisible button for symmetry
            Button("Cancel", action: {})
                .foregroundColor(.clear)
                .disabled(true)
        }
        .padding()
    }
}

// MARK: - QR Code Scanner View
struct QRCodeScannerView: View {
    @Binding var scannedCode: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack {
            DismissableSheetHeader(title: "Scan QR Code") {
                isPresented = false
            }
            
            // QR Scanner implementation would go here
            // For now, using a placeholder
            ZStack {
                Rectangle()
                    .fill(Color.black)
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 250, height: 250)
                
                VStack {
                    Spacer()
                    Text("Point camera at QR code")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding()
                }
            }
        }
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var currentPage = 0
    
    let pages = [
        OnboardingPage(
            image: "bitcoinsign.circle.fill",
            title: "Welcome to WALL-ET",
            description: "Your secure Bitcoin wallet for iOS"
        ),
        OnboardingPage(
            image: "lock.shield.fill",
            title: "Security First",
            description: "Your keys, your coins. We never have access to your funds."
        ),
        OnboardingPage(
            image: "key.fill",
            title: "Backup Your Wallet",
            description: "Write down your seed phrase and keep it safe. It's the only way to recover your wallet."
        )
    ]
    
    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    VStack(spacing: 30) {
                        Spacer()
                        
                        Image(systemName: pages[index].image)
                            .font(.system(size: 100))
                            .foregroundColor(.orange)
                        
                        Text(pages[index].title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(pages[index].description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            
            // Bottom buttons
            VStack(spacing: 16) {
                if currentPage == pages.count - 1 {
                    Button(action: {
                        coordinator.completeOnboarding()
                        coordinator.showCreateWallet()
                    }) {
                        Text("Create New Wallet")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        coordinator.completeOnboarding()
                        coordinator.showImportWallet()
                    }) {
                        Text("Import Existing Wallet")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                } else {
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        Text("Next")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        coordinator.completeOnboarding()
                    }) {
                        Text("Skip")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

struct OnboardingPage {
    let image: String
    let title: String
    let description: String
}

// MARK: - Custom Alert View
struct CustomAlertView: View {
    let alert: AppCoordinator.AlertItem
    
    var body: some View {
        VStack(spacing: 20) {
            Text(alert.title)
                .font(.headline)
            
            Text(alert.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                if let secondaryButton = alert.secondaryButton,
                   let secondaryAction = alert.secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryButton)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: alert.primaryAction) {
                    Text(alert.primaryButton)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding()
    }
}

// MARK: - Preview Provider
struct CommonComponents_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EmptyStateView(
                icon: "bitcoinsign.circle",
                title: "No Wallets",
                message: "Create your first wallet to get started",
                action: {},
                actionTitle: "Create Wallet"
            )
            .previewDisplayName("Empty State")
            
            LoadingView(message: "Loading wallets...")
                .previewDisplayName("Loading")
            
            ErrorView(
                error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Network connection failed"]),
                retry: {}
            )
            .previewDisplayName("Error")
            
            VStack {
                SectionHeader(title: "Wallets", action: {}, actionTitle: "Add")
                
                CardContainer {
                    Text("Card Content")
                        .frame(maxWidth: .infinity)
                }
                .padding()
                
                HStack {
                    BadgeView(text: "TESTNET", color: .orange)
                    BadgeView(text: "Confirmed", color: .green)
                    BadgeView(text: "Pending", color: .yellow)
                }
            }
            .previewDisplayName("Components")
        }
    }
}