import SwiftUI

struct ReceiveView: View {
    @ObservedObject var viewModel: ReceiveViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                qrSection
                addressSection
                requestAmountSection
                addressFormatsSection
            }
            .padding()
        }
        .task { await viewModel.handleAppear() }
        .sheet(isPresented: Binding(
            get: { viewModel.showShareSheet },
            set: { if !$0 { viewModel.dismissShareSheet() } }
        )) {
            SendReceiveShareSheet(activityItems: [viewModel.walletAddress])
        }
    }

    private var qrSection: some View {
        VStack(spacing: 16) {
            Image(uiImage: viewModel.qrCodeImage())
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
    }

    private var addressSection: some View {
        VStack(spacing: 12) {
            Text("Your Bitcoin Address")
                .font(.headline)

            Text(viewModel.walletAddress)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            HStack(spacing: 12) {
                Button(action: viewModel.copyAddressToClipboard) {
                    Label(viewModel.copied ? "Copied!" : "Copy Address", systemImage: viewModel.copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Button(action: viewModel.presentShareSheet) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var requestAmountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Request Specific Amount (Optional)")
                .font(.headline)

            HStack {
                TextField("0.00000000", text: $viewModel.requestAmount)
                    .keyboardType(.decimalPad)

                Text("BTC")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }

    private var addressFormatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Address Formats")
                .font(.headline)

            AddressFormatRow(
                format: "Native SegWit",
                address: viewModel.walletAddress,
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
}

#Preview {
    let viewModel = ReceiveViewModel(initialAddress: "tb1qexampleaddress1234567890", skipInitialLoad: true)
    viewModel.requestAmount = "0.00100000"
    return ReceiveView(viewModel: viewModel)
}
