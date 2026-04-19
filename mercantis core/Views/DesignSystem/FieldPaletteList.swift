import SwiftUI

struct FieldPaletteList: View {
    static let items: [(name: String, icon: String)] = [
        ("Data", "textformat"),
        ("Select", "list.bullet.rectangle"),
        ("Date", "calendar"),
        ("Check", "checkmark.square"),
        ("Int", "number"),
        ("Float", "sum"),
        ("Currency", "dollarsign.circle"),
        ("Table", "tablecells"),
        ("Link", "link"),
        ("Geolocation", "location")
    ]

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Field Palette")
                    .font(.headline)

                List {
                    ForEach(Self.items, id: \.name) { item in
                        Label(item.name, systemImage: item.icon)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 280)
            }
        }
    }
}

#Preview("Light") {
    FieldPaletteList()
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FieldPaletteList()
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.dark)
}
