import SwiftUI

struct AddressFormatRow: View {
    let format: String
    let address: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(format)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(address)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}
