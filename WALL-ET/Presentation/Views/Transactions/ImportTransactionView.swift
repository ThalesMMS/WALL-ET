import SwiftUI

struct ImportTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var inputText: String = ""
    @State private var isBroadcasting = false
    @State private var showScanner = false
    @State private var showFileImporter = false
    @State private var errorMessage: String?
    @State private var successTxid: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Paste Signed Transaction")) {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 140)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    HStack {
                        Button("Paste") { if let s = UIPasteboard.general.string { inputText = s } }
                        Spacer()
                        Button("Scan QR / BBQR") { showScanner = true }
                        Button("Import File") { showFileImporter = true }
                    }
                }

                if isPSBT(inputText) {
                    Section(footer: Text("Detected PSBT. Finalization to raw hex will be added together with the send flow. Please import raw transaction hex for broadcast.")) {
                        Button("Broadcast Transaction") { }
                            .frame(maxWidth: .infinity)
                            .disabled(true)
                    }
                } else {
                    Section(footer: Text("Accepts raw transaction hex. For PSBT support we will add finalization later.")) {
                    Button(action: { Task { await broadcast() } }) {
                        if isBroadcasting { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("Broadcast Transaction").frame(maxWidth: .infinity) }
                    }
                    .disabled(isBroadcasting || !isValidHex(inputText))
                }
                }

                if let txid = successTxid {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Broadcasted: \(txid)")
                                .lineLimit(1).truncationMode(.middle)
                        }
                        let url = explorerURL(txid: txid)
                        if let url = url {
                            Link("View on Explorer", destination: url)
                        }
                    }
                }
            }
            .navigationTitle("Import Transaction")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $showScanner) {
                QRScannerView(isPresented: $showScanner) { code in
                    inputText = code
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data, .plainText]) { result in
                switch result {
                case .success(let url):
                    if let data = try? Data(contentsOf: url) {
                        if isPSBTData(data) {
                            inputText = "PSBT: \(data.base64EncodedString())"
                        } else if let text = String(data: data, encoding: .utf8) {
                            inputText = text
                        } else {
                            errorMessage = "Unsupported file encoding"
                        }
                    } else {
                        errorMessage = "Failed to read file"
                    }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }

    private func broadcast() async {
        let hex = normalizedHex(inputText)
        guard isValidHex(hex) else { errorMessage = "Invalid raw transaction hex"; return }
        isBroadcasting = true
        defer { isBroadcasting = false }
        do {
            let txid = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                ElectrumService.shared.broadcastTransaction(hex) { cont.resume(with: $0) }
            }
            successTxid = txid
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isValidHex(_ s: String) -> Bool {
        let hex = normalizedHex(s)
        guard !hex.isEmpty, hex.count % 2 == 0 else { return false }
        return hex.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil
    }

    private func isPSBT(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("cHNidP") { return true } // base64 magic
        if t.hasPrefix("70736274") { return true } // hex magic
        return false
    }

    private func isPSBTData(_ d: Data) -> Bool {
        return d.starts(with: [0x70, 0x73, 0x62, 0x74, 0xff]) // "psbt\xFF"
    }

    private func normalizedHex(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }

    private func explorerURL(txid: String) -> URL? {
        let isTestnet = ElectrumService.shared.currentNetwork == .testnet
        let base = isTestnet ? "https://mempool.space/testnet/tx/" : "https://mempool.space/tx/"
        return URL(string: base + txid)
    }
}
