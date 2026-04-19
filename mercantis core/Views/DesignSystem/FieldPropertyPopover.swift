import SwiftUI

struct FieldPropertyPopover: View {
    @State private var label = "Customer Name"
    @State private var selectedType = "Data"
    @State private var options = ""
    @State private var mandatory = true
    @State private var readOnly = false
    @State private var unique = false

    private let fieldTypes = ["Data", "Select", "Date", "Check", "Int", "Float", "Currency", "Table", "Link", "Geolocation"]

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Field Properties")
                    .font(.headline)

                TextField("Label", text: $label)
                    .textFieldStyle(.roundedBorder)

                Picker("Type", selection: $selectedType) {
                    ForEach(fieldTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }

                TextField("Options", text: $options)
                    .textFieldStyle(.roundedBorder)

                Toggle("Mandatory", isOn: $mandatory)
                Toggle("Read Only", isOn: $readOnly)
                Toggle("Unique", isOn: $unique)
            }
        }
        .frame(width: 280)
    }
}

#Preview("Light") {
    FieldPropertyPopover()
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FieldPropertyPopover()
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.dark)
}
