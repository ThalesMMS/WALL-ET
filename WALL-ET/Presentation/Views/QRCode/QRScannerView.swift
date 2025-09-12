import SwiftUI
import AVFoundation
#if canImport(CodeScanner)
import CodeScanner
#endif

struct QRScannerView: View {
    @State private var scannedCode: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var bbqrParts: [String] = []
    @State private var expectedParts = 0
    @State private var isFlashOn = false
    @Binding var isPresented: Bool
    
    let onScan: (String) -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                scannerView
                
                VStack {
                    Spacer()
                    
                    if expectedParts > 0 {
                        BBQRProgressView(
                            current: bbqrParts.count,
                            total: expectedParts
                        )
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(ModernTheme.Radius.medium)
                        .padding()
                    }
                    
                    HStack(spacing: 40) {
                        Button(action: { isFlashOn.toggle() }) {
                            Image(systemName: isFlashOn ? "bolt.fill" : "bolt")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                )
                        }
                        
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                )
                        }
                    }
                    .padding(.bottom, 40)
                }
                
                ScannerOverlay()
            }
            .navigationBarHidden(true)
            .alert("QR Code Scanned", isPresented: $showingAlert) {
                Button("OK") {
                    showingAlert = false
                    isPresented = false
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    #if canImport(CodeScanner)
    private var scannerView: some View {
        CodeScannerView(
            codeTypes: [.qr],
            simulatedData: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.001",
            completion: handleScan
        )
    }
    
    private func handleScan(result: Result<CodeScanner.ScanResult, CodeScanner.ScanError>) {
        switch result {
        case .success(let result):
            let code = result.string
            if code.hasPrefix("B$") { handleBBQRCode(code) } else { handleRegularCode(code) }
        case .failure(let error):
            alertMessage = "Scanning failed: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    #else
    private var scannerView: some View {
        ZStack {
            Color.black.opacity(0.8)
            Text("Scanner unavailable")
                .foregroundColor(.white)
        }
    }
    
    private func handleScan(result: Result<(string: String), Never>) {
        switch result {
        case .success(let result):
            let code = result.string
            if code.hasPrefix("B$") { handleBBQRCode(code) } else { handleRegularCode(code) }
        }
    }
    #endif
    
    private func handleRegularCode(_ code: String) {
        if let bitcoinURI = QRCodeService.shared.parseBitcoinURI(code) {
            // Handle Bitcoin URI
            var message = "Address: \(bitcoinURI.address)"
            if let amount = bitcoinURI.amount {
                message += "\nAmount: \(amount) BTC"
            }
            if let label = bitcoinURI.label {
                message += "\nLabel: \(label)"
            }
            
            alertMessage = message
            showingAlert = true
            onScan(code)
        } else if code.starts(with: "bc1") || code.starts(with: "tb1") ||
                  code.starts(with: "1") || code.starts(with: "3") ||
                  code.starts(with: "m") || code.starts(with: "n") ||
                  code.starts(with: "2") {
            // Plain Bitcoin address
            alertMessage = "Bitcoin Address: \(code)"
            showingAlert = true
            onScan(code)
        } else {
            // Unknown format
            alertMessage = "Unknown QR code format"
            showingAlert = true
        }
    }
    
    private func handleBBQRCode(_ code: String) {
        // Parse BBQR header to get total parts
        if let (header, _) = QRCodeService.shared.parseBBQRPart(code) {
            expectedParts = header.total
            
            // Add to collected parts
            if !bbqrParts.contains(code) {
                bbqrParts.append(code)
            }
            
            // Check if we have all parts
            if bbqrParts.count == expectedParts {
                if let decoded = QRCodeService.shared.parseBBQR(bbqrParts) {
                    alertMessage = "Successfully decoded BBQR transaction"
                    showingAlert = true
                    onScan(decoded)
                } else {
                    alertMessage = "Failed to decode BBQR data"
                    showingAlert = true
                }
                
                // Reset
                bbqrParts = []
                expectedParts = 0
            }
        }
    }
}

struct ScannerOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.7
            let xOffset = (geometry.size.width - size) / 2
            let yOffset = (geometry.size.height - size) / 2
            
            ZStack {
                // Dark overlay
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                // Clear scanning area
                RoundedRectangle(cornerRadius: ModernTheme.Radius.large)
                    .frame(width: size, height: size)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .blendMode(.destinationOut)
                
                // Corner markers
                VStack {
                    HStack {
                        CornerShape(corner: .topLeft)
                        Spacer()
                        CornerShape(corner: .topRight)
                    }
                    Spacer()
                    HStack {
                        CornerShape(corner: .bottomLeft)
                        Spacer()
                        CornerShape(corner: .bottomRight)
                    }
                }
                .frame(width: size, height: size)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Scanning line animation
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ModernTheme.Colors.primary.opacity(0),
                                ModernTheme.Colors.primary,
                                ModernTheme.Colors.primary.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size - 40, height: 2)
                    .position(x: geometry.size.width / 2, y: yOffset + 20)
                    .modifier(ScanningAnimation(height: size - 40))
            }
            .compositingGroup()
        }
    }
}

struct CornerShape: View {
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    let corner: Corner
    let size: CGFloat = 30
    let thickness: CGFloat = 3
    
    var body: some View {
        Path { path in
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomRight:
                path.move(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size))
                path.addLine(to: CGPoint(x: 0, y: size))
            }
        }
        .stroke(ModernTheme.Colors.primary, lineWidth: thickness)
        .frame(width: size, height: size)
    }
}

struct ScanningAnimation: ViewModifier {
    let height: CGFloat
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .onAppear {
                withAnimation(
                    .linear(duration: 2)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = height
                }
            }
    }
}

struct BBQRProgressView: View {
    let current: Int
    let total: Int
    
    var body: some View {
        VStack(spacing: ModernTheme.Spacing.sm) {
            Text("Scanning Multi-Part QR Code")
                .font(ModernTheme.Typography.headline)
                .foregroundColor(.white)
            
            ProgressView(value: Double(current), total: Double(total))
                .tint(ModernTheme.Colors.primary)
                .scaleEffect(x: 1, y: 2)
            
            Text("\(current) of \(total) parts scanned")
                .font(ModernTheme.Typography.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding()
    }
}

// Removed local placeholder CodeScannerView; using module when available
