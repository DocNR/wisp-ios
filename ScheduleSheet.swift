import SwiftUI

/// Sheet for picking a future date+time for a scheduled post. Returns the
/// chosen `Date` to the caller via `onConfirm`, or nil via `onCancel`.
struct ScheduleSheet: View {
    let initialDate: Date?
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(initialDate: Date? = nil,
         onConfirm: @escaping (Date) -> Void,
         onCancel: @escaping () -> Void) {
        self.initialDate = initialDate
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        let fallback = Date().addingTimeInterval(60 * 15) // 15 min from now
        _selectedDate = State(initialValue: initialDate ?? fallback)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 12)

                Spacer()
            }
            .navigationTitle("Schedule Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set") {
                        onConfirm(selectedDate)
                        dismiss()
                    }
                    .disabled(selectedDate <= Date())
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
