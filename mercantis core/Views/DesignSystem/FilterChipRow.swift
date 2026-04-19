import SwiftUI

struct FilterChipRow: View {
    @Binding var selected: Set<RecordFilterChip>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RecordFilterChip.allCases) { chip in
                    Button(chip.rawValue) {
                        if selected.contains(chip) {
                            selected.remove(chip)
                        } else {
                            selected.insert(chip)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(selected.contains(chip) ? .blue : .secondary)
                }
            }
        }
    }
}

#Preview("Light") {
    FilterChipRow(selected: .constant([.recordID, .date]))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FilterChipRow(selected: .constant([.owner]))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.dark)
}
