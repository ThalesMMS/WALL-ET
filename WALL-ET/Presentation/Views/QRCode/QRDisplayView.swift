import SwiftUI

struct QRDisplayView: View {
    let data: String
    let title: String
    let subtitle: String?
    
    @State private var qrImages: [UIImage] = []
    @State private var currentImageIndex = 0
    @State private var isBBQR = false
    @State private var animationTimer: Timer?
    @State private var showShareSheet = false
    @State private var copiedToClipboard = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: ModernTheme.Spacing.lg) {
                
                // QR Code Display
                ZStack {
                    if !qrImages.isEmpty {
                        Image(uiImage: qrImages[currentImageIndex])
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                            .padding(ModernTheme.Spacing.lg)
                            .background(Color.white)
                            .cornerRadius(ModernTheme.Radius.large)
                            .shadow(
                                color: ModernTheme.Shadow.large.color,
                                radius: ModernTheme.Shadow.large.radius
                            )
                    } else {
                        ProgressView()
                            .frame(width: 300, height: 300)
                    }
                    
                    if isBBQR && qrImages.count > 1 {
                        VStack {
                            Spacer()
                            BBQRIndicator(
                                current: currentImageIndex + 1,
                                total: qrImages.count
                            )
                            .padding()
                        }
                    }
                }
                
                // Info Section
                VStack(spacing: ModernTheme.Spacing.xs) {
                    Text(title)
                        .font(ModernTheme.Typography.title2)
                        .foregroundColor(ModernTheme.Colors.textPrimary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(ModernTheme.Typography.subheadline)
                            .foregroundColor(ModernTheme.Colors.textSecondary)
                    }
                    
                    if isBBQR {
                        Text("Multi-part QR Code (BBQR)")
                            .font(ModernTheme.Typography.caption)
                            .foregroundColor(ModernTheme.Colors.warning)
                            .padding(.horizontal, ModernTheme.Spacing.sm)
                            .padding(.vertical, ModernTheme.Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(ModernTheme.Colors.warning.opacity(0.1))
                            )
                    }
                }
                .multilineTextAlignment(.center)
                
                // Data Preview
                VStack(alignment: .leading, spacing: ModernTheme.Spacing.xs) {
                    HStack {
                        Text("Data:")
                            .font(ModernTheme.Typography.caption)
                            .foregroundColor(ModernTheme.Colors.textSecondary)
                        
                        Spacer()
                        
                        Button(action: copyToClipboard) {
                            Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundColor(ModernTheme.Colors.primary)
                        }
                    }
                    
                    Text(data)
                        .font(ModernTheme.Typography.caption2)
                        .foregroundColor(ModernTheme.Colors.textPrimary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ModernTheme.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: ModernTheme.Radius.small)
                                .fill(ModernTheme.Colors.secondaryBackground)
                        )
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: ModernTheme.Spacing.sm) {
                    Button(action: { showShareSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    if isBBQR && qrImages.count > 1 {
                        HStack(spacing: ModernTheme.Spacing.sm) {
                            Button(action: previousImage) {
                                Image(systemName: "chevron.left")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            
                            Button(action: toggleAnimation) {
                                Image(systemName: animationTimer != nil ? "pause.fill" : "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            
                            Button(action: nextImage) {
                                Image(systemName: "chevron.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(ModernTheme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            generateQRCodes()
        }
        .onDisappear {
            animationTimer?.invalidate()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: qrImages)
        }
    }
    
    private func generateQRCodes() {
        if data.count > 500 {
            // Generate BBQR for large data
            qrImages = QRCodeService.shared.generateBBQR(from: data)
            isBBQR = true
            
            if qrImages.count > 1 {
                startAnimation()
            }
        } else {
            // Generate single QR code
            if let qr = QRCodeService.shared.generateQRCode(from: data) {
                qrImages = [qr]
            }
            isBBQR = false
        }
    }
    
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            nextImage()
        }
    }
    
    private func toggleAnimation() {
        if animationTimer != nil {
            animationTimer?.invalidate()
            animationTimer = nil
        } else {
            startAnimation()
        }
    }
    
    private func nextImage() {
        guard !qrImages.isEmpty else { return }
        currentImageIndex = (currentImageIndex + 1) % qrImages.count
    }
    
    private func previousImage() {
        guard !qrImages.isEmpty else { return }
        currentImageIndex = currentImageIndex == 0 ? qrImages.count - 1 : currentImageIndex - 1
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = data
        copiedToClipboard = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }
}

struct BBQRIndicator: View {
    let current: Int
    let total: Int
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { index in
                Circle()
                    .fill(index == current ? ModernTheme.Colors.primary : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, ModernTheme.Spacing.sm)
        .padding(.vertical, ModernTheme.Spacing.xxs)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Usage example
struct TransactionQRView: View {
    let transaction: String
    let txid: String
    let amount: Double
    
    var body: some View {
        QRDisplayView(
            data: transaction,
            title: "Transaction",
            subtitle: "\(amount) BTC"
        )
    }
}

struct AddressQRView: View {
    let address: String
    let label: String?
    
    var body: some View {
        QRDisplayView(
            data: "bitcoin:\(address)",
            title: label ?? "Bitcoin Address",
            subtitle: address
        )
    }
}