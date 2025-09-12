import SwiftUI
import Combine
import CoreImage.CIFilterBuiltins

struct SendReceiveView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack {
                // Tab Selector
                Picker("", selection: $selectedTab) {
                    Text("Send").tag(0)
                    Text("Receive").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selectedTab == 0 {
                    SendView()
                } else {
                    ReceiveView()
                }
            }
            .navigationTitle(selectedTab == 0 ? "Send Bitcoin" : "Receive Bitcoin")
        }
    }
}

struct SendView: View {
    @State private var recipientAddress = ""
    @State private var btcAmount = ""
    @State private var fiatAmount = ""
    @State private var note = ""
    @State private var selectedFeeOption = FeeOption.normal
    @State private var showScanner = false
    @State private var showConfirmation = false
    @State private var useMaxAmount = false
    @State private var btcPrice: Double = 0
    @State private var availableBalance: Double = 0
    @State private var estVBytes: Int = 140
    
    enum FeeOption: String, CaseIterable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
        case custom = "Custom"
        
        var description: String {
            switch self {
            case .slow: return "~60 min"
            case .normal: return "~30 min"
            case .fast: return "~10 min"
            case .custom: return "custom"
            }
        }
        
        var satPerByte: Int {
            switch self {
            case .slow: return 5
            case .normal: return 20
            case .fast: return 50
            case .custom: return 15
            }
        }
        
        // Display-only; actual fee computed in service. Assume ~140 vbytes typical tx
        func estimatedFeeBTC(approxVBytes: Int = 140) -> Double {
            Double(approxVBytes * satPerByte) / 100_000_000.0
        }
    }
    @State private var customSatPerByte: Double = 15
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Available Balance
                VStack(spacing: 8) {
                    Text("Available Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(availableBalance, specifier: "%.8f") BTC")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("≈ $\(availableBalance * btcPrice, specifier: "%.2f")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Recipient Address
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recipient Address", systemImage: "person")
                        .font(.headline)
                    
                    HStack {
                        TextField("Enter Bitcoin address", text: $recipientAddress)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button(action: { showScanner = true }) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                        
                        Button(action: {
                            if let pasteString = UIPasteboard.general.string {
                                recipientAddress = pasteString
                            }
                        }) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.title2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Amount
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Amount", systemImage: "bitcoinsign.circle")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: {
                            useMaxAmount.toggle()
                            if useMaxAmount {
                                let feeBtc = Double(estVBytes * effectiveSatPerByte()) / 100_000_000.0
                                let maxAmount = max(0, availableBalance - feeBtc)
                                btcAmount = String(format: "%.8f", maxAmount)
                                fiatAmount = String(format: "%.2f", maxAmount * btcPrice)
                            }
                        }) {
                            Text("Max")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(useMaxAmount ? Color.orange : Color(.systemGray5))
                                .foregroundColor(useMaxAmount ? .white : .primary)
                                .cornerRadius(8)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        HStack {
                            TextField("0.00000000", text: $btcAmount)
                                .keyboardType(.decimalPad)
                                .onChange(of: btcAmount) { newValue in
                                    if let btc = Double(newValue) {
                                        fiatAmount = String(format: "%.2f", btc * btcPrice)
                                    }
                                }
                            
                            Text("BTC")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                            
                            TextField("0.00", text: $fiatAmount)
                                .keyboardType(.decimalPad)
                                .onChange(of: fiatAmount) { newValue in
                                    if let fiat = Double(newValue) {
                                        btcAmount = String(format: "%.8f", fiat / btcPrice)
                                    }
                                }
                            
                            Text("USD")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                
                feeSelectorSection
                
                // Note (Optional)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Note (Optional)", systemImage: "note.text")
                        .font(.headline)
                    
                    TextField("Add a note for this transaction", text: $note)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Send Button
                Button(action: { Task { await recalcEstimate(); showConfirmation = true } }) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Review Transaction")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .font(.headline)
                }
                .disabled(recipientAddress.isEmpty || btcAmount.isEmpty)
            }
            .padding()
        }
        .task {
            // Load available balance and price
            if let repo: WalletRepositoryProtocol = DIContainer.shared.resolve(WalletRepositoryProtocol.self) {
                // Sum across first wallet account
                if let wallet = try? await repo.getAllWallets().first,
                   let addr = wallet.accounts.first?.address,
                   let bal = try? await repo.getBalance(for: addr) {
                    availableBalance = bal.btcValue
                } else {
                    availableBalance = 0
                }
            }
            btcPrice = (try? await PriceService().fetchBTCPrice().price) ?? 0
            await recalcEstimate()
        }
        .sheet(isPresented: $showConfirmation) {
            TransactionConfirmationView(
                recipientAddress: recipientAddress,
                btcAmount: Double(btcAmount) ?? 0,
                fiatAmount: Double(fiatAmount) ?? 0,
                fee: Double(effectiveSatPerByte()),
                estimatedVBytes: estVBytes,
                note: note
            )
        }
        // Re-estimation is performed on initial task and before showing confirmation.
    }
    
    private func effectiveSatPerByte() -> Int {
        selectedFeeOption == .custom ? Int(customSatPerByte) : selectedFeeOption.satPerByte
    }
    private func currentEstimatedFeeBTC() -> Double {
        Double(estVBytes * effectiveSatPerByte()) / 100_000_000.0
    }
    
    private func recalcEstimate() async {
        guard let amount = Double(btcAmount), amount > 0, !recipientAddress.isEmpty else { return }
        if let est = try? await TransactionService().estimateFee(to: recipientAddress, amount: amount, feeRateSatPerVb: effectiveSatPerByte()) {
            await MainActor.run { estVBytes = est.vbytes }
        }
    }
}

private extension SendView {
    @ViewBuilder
    var feeSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Network Fee", systemImage: "gauge")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(FeeOption.allCases, id: \.self) { option in
                    FeeOptionButton(
                        option: option,
                        isSelected: selectedFeeOption == option,
                        action: { selectedFeeOption = option }
                    )
                }
            }
            if selectedFeeOption == .custom {
                HStack {
                    Text("\(Int(customSatPerByte)) sat/vB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $customSatPerByte, in: 1...200, step: 1)
                }
            }
            
            HStack {
                Text("Estimated fee:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(currentEstimatedFeeBTC(), specifier: "%.8f") BTC")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("($\(currentEstimatedFeeBTC() * btcPrice, specifier: "%.2f"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct FeeOptionButton: View {
    let option: SendView.FeeOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(option.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Text(option.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("\(option.satPerByte) sat/B")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.orange.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ReceiveView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var walletAddress = ""
    @AppStorage("gap_limit") private var gapLimit: Int = 20
    @AppStorage("auto_rotate_receive") private var autoRotate = true
    @State private var requestAmount = ""
    @State private var note = ""
    @State private var showShareSheet = false
    @State private var copied = false
    // Removed polling; react to Electrum scripthash notifications instead
    
    var qrCodeImage: UIImage {
        generateQRCode(from: buildBitcoinURI())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // QR Code
                VStack(spacing: 16) {
                    Image(uiImage: qrCodeImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 250, height: 250)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                    
                    Text("Scan to send Bitcoin to this address")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Wallet Address
                VStack(spacing: 12) {
                    Text("Your Bitcoin Address")
                        .font(.headline)
                    
                    Text(walletAddress)
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            UIPasteboard.general.string = walletAddress
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copied = false
                            }
                        }) {
                            Label(copied ? "Copied!" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        
                        Button(action: { showShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Request Specific Amount (Optional)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Request Specific Amount (Optional)")
                        .font(.headline)
                    
                    HStack {
                        TextField("0.00000000", text: $requestAmount)
                            .keyboardType(.decimalPad)
                        
                        Text("BTC")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    TextField("Add a note or description", text: $note)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Different Address Formats
                VStack(alignment: .leading, spacing: 12) {
                    Text("Address Formats")
                        .font(.headline)
                    
                    AddressFormatRow(
                        format: "Native SegWit",
                        address: walletAddress,
                        description: "Lowest fees, recommended"
                    )
                    
                    AddressFormatRow(
                        format: "SegWit",
                        address: "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy",
                        description: "Compatible with most wallets"
                    )
                    
                    AddressFormatRow(
                        format: "Legacy",
                        address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
                        description: "Universal compatibility"
                    )
                }
            }
            .padding()
        }
        .onAppear { refreshReceiveAddress() }
        .onReceive(ElectrumService.shared.transactionUpdatePublisher) { _ in
            refreshReceiveAddress()
        }
        .onReceive(ElectrumService.shared.addressStatusPublisher) { update in
            if autoRotate, update.address == walletAddress, update.hasHistory {
                refreshReceiveAddress()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            SendReceiveShareSheet(activityItems: [walletAddress])
        }
    }
    
    private func buildBitcoinURI() -> String {
        var uri = "bitcoin:\(walletAddress)"
        if !requestAmount.isEmpty, let amount = Double(requestAmount) {
            uri += "?amount=\(amount)"
            if !note.isEmpty {
                uri += "&message=\(note.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            }
        }
        return uri
    }
    
    private func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }

    private func refreshReceiveAddress() {
        Task { @MainActor in
            if let selected = coordinator.selectedWallet {
                if let next = await WalletService().getNextReceiveAddress(for: selected.id, gap: gapLimit) {
                    walletAddress = next
                    ElectrumService.shared.subscribeToAddress(next)
                    return
                }
                walletAddress = selected.address
                ElectrumService.shared.subscribeToAddress(selected.address)
            } else if let active = await WalletService().getActiveWallet() {
                if let next = await WalletService().getNextReceiveAddress(for: active.id, gap: gapLimit) {
                    walletAddress = next
                    ElectrumService.shared.subscribeToAddress(next)
                    return
                }
                walletAddress = active.address
                ElectrumService.shared.subscribeToAddress(active.address)
            } else if let first = try? await WalletService().fetchWallets().first {
                if let next = await WalletService().getNextReceiveAddress(for: first.id, gap: gapLimit) {
                    walletAddress = next
                    ElectrumService.shared.subscribeToAddress(next)
                } else {
                    walletAddress = first.address
                    ElectrumService.shared.subscribeToAddress(first.address)
                }
            }
        }
    }

    // Polling removed; rotation now driven by Electrum notifications
}

struct AddressFormatRow: View {
    let format: String
    let address: String
    let description: String
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(format)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    UIPasteboard.general.string = address
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(.orange)
                }
            }
            
            Text(address)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct TransactionConfirmationView: View {
    let recipientAddress: String
    let btcAmount: Double
    let fiatAmount: Double
    // Pass sat/vB as fee for the service; we show estimated BTC here
    let fee: Double
    let estimatedVBytes: Int
    let note: String
    @Environment(\.dismiss) var dismiss
    @State private var isProcessing = false
    
    private var feeRateSatPerVb: Int { Int(fee) }
    private var estimatedFeeBTC: Double { Double(estimatedVBytes * feeRateSatPerVb) / 100_000_000.0 }
    var totalBTC: Double { btcAmount + estimatedFeeBTC }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Confirm Transaction")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Please review the details below")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    // Transaction Details
                    VStack(spacing: 16) {
                        ConfirmationRow(label: "To", value: recipientAddress, truncate: true)
                        ConfirmationRow(label: "Amount", value: "\(String(format: "%.8f", btcAmount)) BTC")
                        ConfirmationRow(label: "Amount (USD)", value: "$\(String(format: "%.2f", fiatAmount))")
                        ConfirmationRow(label: "Fee rate", value: "\(feeRateSatPerVb) sat/vB")
                        ConfirmationRow(label: "Est. Fee", value: "\(String(format: "%.8f", estimatedFeeBTC)) BTC")
                        Divider()
                        ConfirmationRow(
                            label: "Total",
                            value: "\(String(format: "%.8f", totalBTC)) BTC",
                            isTotal: true
                        )
                        
                        if !note.isEmpty {
                            ConfirmationRow(label: "Note", value: note)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Warning
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text("Bitcoin transactions cannot be reversed. Please verify the recipient address is correct.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            isProcessing = true
                            // Simulate sending
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                dismiss()
                            }
                        }) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Confirm & Send")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .font(.headline)
                        .disabled(isProcessing)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.orange)
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}

struct ConfirmationRow: View {
    let label: String
    let value: String
    var truncate: Bool = false
    var isTotal: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(isTotal ? .headline : .subheadline)
                .foregroundColor(isTotal ? .primary : .secondary)
            
            Spacer()
            
            if truncate {
                Text(String(value.prefix(20)) + "..." + String(value.suffix(6)))
                    .font(isTotal ? .headline : .subheadline)
                    .fontWeight(isTotal ? .bold : .regular)
                    .lineLimit(1)
            } else {
                Text(value)
                    .font(isTotal ? .headline : .subheadline)
                    .fontWeight(isTotal ? .bold : .regular)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

struct SendReceiveShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SendReceiveView()
}
