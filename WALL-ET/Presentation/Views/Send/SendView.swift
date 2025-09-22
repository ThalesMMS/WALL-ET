import SwiftUI

struct SendView: View {
    @ObservedObject var viewModel: SendViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                balanceSection
                recipientSection
                amountSection
                SendFeeSelectorView(viewModel: viewModel)

                Button(action: { Task { await viewModel.prepareReview() } }) {
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
                .disabled(!viewModel.isReviewEnabled)
            }
            .padding()
        }
        .task { await viewModel.handleAppear() }
        .sheet(isPresented: Binding(
            get: { viewModel.showConfirmation },
            set: { if !$0 { viewModel.dismissConfirmation() } }
        )) {
            SendTransactionConfirmationView(
                details: viewModel.confirmationDetails(),
                onConfirm: viewModel.confirmTransaction,
                onCancel: viewModel.dismissConfirmation
            )
        }
    }

    private var balanceSection: some View {
        VStack(spacing: 8) {
            Text("Available Balance")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(viewModel.availableBalance, specifier: "%.8f") BTC")
                .font(.title2)
                .fontWeight(.semibold)

            Text("≈ $\(viewModel.availableBalance * viewModel.btcPrice, specifier: "%.2f")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recipient Address", systemImage: "person")
                .font(.headline)

            HStack {
                TextField("Enter Bitcoin address", text: $viewModel.recipientAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Button(action: { viewModel.showScanner = true }) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2)
                        .foregroundColor(.orange)
                }

                Button(action: viewModel.pasteAddressFromClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.title2)
                        .foregroundColor(.orange)
                }
            }

            if !viewModel.isAddressValid && !viewModel.recipientAddress.isEmpty {
                Text("Invalid address")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Amount", systemImage: "bitcoinsign.circle")
                    .font(.headline)

                Spacer()

                Button(action: viewModel.toggleMaxAmount) {
                    Text("Max")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(viewModel.useMaxAmount ? Color.orange : Color(.systemGray5))
                        .foregroundColor(viewModel.useMaxAmount ? .white : .primary)
                        .cornerRadius(8)
                }
            }

            VStack(spacing: 12) {
                HStack {
                    TextField("0.00000000", text: $viewModel.btcAmount)
                        .keyboardType(.decimalPad)

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

                    TextField("0.00", text: $viewModel.fiatAmount)
                        .keyboardType(.decimalPad)

                    Text("USD")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            if !viewModel.isAmountValid && !viewModel.btcAmount.isEmpty {
                Text("Amount exceeds available balance")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

#Preview {
    let viewModel = SendViewModel(initialBalance: 1.23456789, initialPrice: 62000, skipInitialLoad: true)
    viewModel.recipientAddress = "tb1qexampleaddress1234567890"
    viewModel.btcAmount = "0.01000000"
    viewModel.fiatAmount = "620.00"
    viewModel.selectFeeOption(.fast)
    return SendView(viewModel: viewModel)
}
