import SwiftUI

struct SendTransactionConfirmationView: View {
    let details: TransactionConfirmationDetails
    let onConfirm: () async -> Bool
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)

                        Text("Confirm Transaction")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Please review the details below")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    VStack(spacing: 16) {
                        ConfirmationRow(label: "To", value: details.recipientAddress, truncate: true)
                        ConfirmationRow(label: "Amount", value: String(format: "%.8f BTC", details.btcAmount))
                        ConfirmationRow(label: "Amount (USD)", value: String(format: "$%.2f", details.fiatAmount))
                        ConfirmationRow(label: "Fee rate", value: "\(details.feeRateSatPerVb) sat/vB")
                        ConfirmationRow(label: "Est. Fee", value: String(format: "%.8f BTC", details.estimatedFeeBTC))
                        Divider()
                        ConfirmationRow(label: "Total", value: String(format: "%.8f BTC", details.totalBTC), isTotal: true)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

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

                    VStack(spacing: 12) {
                        Button(action: confirm) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
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

                        Button("Cancel", action: close)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }

    private func confirm() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            let shouldClose = await onConfirm()
            await MainActor.run {
                isProcessing = false
                if shouldClose {
                    close()
                }
            }
        }
    }

    private func close() {
        dismiss()
        onCancel()
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
