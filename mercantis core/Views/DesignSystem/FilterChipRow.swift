import SwiftUI

struct FilterChipRow: View {
    @Binding var selected: Set<OrderFilterChip>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OrderFilterChip.allCases) { chip in
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
    FilterChipRow(selected: .constant([.orderID, .date]))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FilterChipRow(selected: .constant([.customer]))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.dark)
}
