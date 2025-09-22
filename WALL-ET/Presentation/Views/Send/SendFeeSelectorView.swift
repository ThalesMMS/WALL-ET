import SwiftUI

struct SendFeeSelectorView: View {
    @ObservedObject var viewModel: SendViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Network Fee", systemImage: "gauge")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(SendViewModel.FeeOption.allCases) { option in
                    FeeOptionButton(
                        title: option.rawValue,
                        description: option.description,
                        satPerByte: option == .custom ? Int(viewModel.customSatPerByte) : option.defaultSatPerByte,
                        isSelected: viewModel.selectedFeeOption == option,
                        action: { viewModel.selectFeeOption(option) }
                    )
                }
            }

            if viewModel.selectedFeeOption == .custom {
                HStack {
                    Text("\(Int(viewModel.customSatPerByte)) sat/vB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(
                        value: Binding(
                            get: { viewModel.customSatPerByte },
                            set: { viewModel.updateCustomFeeRate($0) }
                        ),
                        in: 1...200,
                        step: 1
                    )
                }
            }

            HStack {
                Text("Estimated fee:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(viewModel.estimatedFeeBTC, specifier: "%.8f") BTC")
                    .font(.caption)
                    .fontWeight(.medium)

                Text("($\(viewModel.estimatedFeeFiat, specifier: "%.2f"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct FeeOptionButton: View {
    let title: String
    let description: String
    let satPerByte: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("\(satPerByte) sat/B")
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
        .buttonStyle(.plain)
    }
}
