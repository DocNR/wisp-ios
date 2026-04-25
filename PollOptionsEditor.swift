import SwiftUI

/// Inline composer block shown when `pollEnabled` is true. Lets the user pick
/// Standard vs Zap, edit 2–10 option labels, toggle single/multi-choice (standard
/// only), and set min/max sats (zap only). Optionally pick an end date.
struct PollOptionsEditor: View {
    @Bindable var viewModel: ComposeViewModel

    @State private var minSatsText: String = ""
    @State private var maxSatsText: String = ""
    @State private var showEndDatePicker = false
    @State private var endDate: Date = Date().addingTimeInterval(7 * 24 * 3600)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type picker — Standard vs Zap.
            Picker("Poll type", selection: Binding(
                get: { viewModel.isZapPoll },
                set: { newValue in
                    if newValue != viewModel.isZapPoll { viewModel.toggleZapPoll() }
                }
            )) {
                Text("Standard").tag(false)
                Text("Zap").tag(true)
            }
            .pickerStyle(.segmented)

            // Option fields.
            VStack(spacing: 8) {
                ForEach(viewModel.pollOptions.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        TextField("Option \(idx + 1)", text: Binding(
                            get: { viewModel.pollOptions[idx] },
                            set: { viewModel.updatePollOption(at: idx, $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        if viewModel.pollOptions.count > 2 {
                            Button {
                                viewModel.removePollOption(at: idx)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if viewModel.pollOptions.count < 10 {
                    Button {
                        viewModel.addPollOption()
                    } label: {
                        Label("Add option", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.wispPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Mode-specific controls.
            if viewModel.isZapPoll {
                zapControls
            } else {
                standardControls
            }

            endDateControl
        }
        .padding(12)
        .background(Color.wispSurfaceVariant.opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private var standardControls: some View {
        Toggle(isOn: Binding(
            get: { viewModel.pollType == .multiplechoice },
            set: { _ in viewModel.togglePollType() }
        )) {
            Text("Multiple choice").font(.subheadline)
        }
        .tint(Color.wispPrimary)
    }

    private var zapControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Min sats", text: $minSatsText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: minSatsText) { _, new in
                        viewModel.zapPollMinSats = Int(new)
                    }
                TextField("Max sats", text: $maxSatsText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .onChange(of: maxSatsText) { _, new in
                        viewModel.zapPollMaxSats = Int(new)
                    }
            }
            Text("Optional. Voters can zap any amount within this range.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var endDateControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: Binding(
                    get: { viewModel.pollEndsAt != nil },
                    set: { on in
                        if on {
                            viewModel.setPollEndsAt(Int(endDate.timeIntervalSince1970))
                        } else {
                            viewModel.setPollEndsAt(nil)
                        }
                    }
                )) {
                    Text("Set end date").font(.subheadline)
                }
                .tint(Color.wispPrimary)
            }
            if viewModel.pollEndsAt != nil {
                DatePicker(
                    "Ends at",
                    selection: Binding(
                        get: { endDate },
                        set: { d in
                            endDate = d
                            viewModel.setPollEndsAt(Int(d.timeIntervalSince1970))
                        }
                    ),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)
                .datePickerStyle(.compact)
            }
        }
    }
}
