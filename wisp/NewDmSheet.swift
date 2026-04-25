import SwiftUI

struct NewDmSheet: View {
    let keypair: Keypair
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var input: String = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Start a new DM")
                    .font(.headline)
                    .padding(.top, 24)

                Text("Paste an npub or 64-character hex pubkey.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("npub1… or hex pubkey", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 24)

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                Button {
                    submit()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.wispPrimary, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .background(Color.wispBackground)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = parseRecipient(s) {
            error = nil
            onSelect(hex)
        } else {
            error = "Not a valid npub or 64-char hex pubkey."
        }
    }

    private func parseRecipient(_ s: String) -> String? {
        if s.lowercased().hasPrefix("npub1") {
            guard let (hrp, data) = Bech32.decode(s), hrp == "npub", data.count == 32 else { return nil }
            return Hex.encode(data)
        }
        if s.count == 64, Hex.decode(s)?.count == 32 {
            return s.lowercased()
        }
        return nil
    }
}
