//
//  BarcodeField.swift
//  mercantis core
//
//  W9: Barcode/QR input field. (ADR-035)
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct BarcodeField: View {
    @Binding var value: String
    let isReadOnly: Bool
    @State private var isScannerPresented = false

    public init(value: Binding<String>, isReadOnly: Bool) {
        self._value = value
        self.isReadOnly = isReadOnly
    }

    public var body: some View {
        HStack(spacing: 6) {
            TextField("Code", text: $value)
                .mercantisInput()
                .disabled(isReadOnly)
#if os(iOS)
            if !isReadOnly {
                Button {
                    isScannerPresented = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $isScannerPresented) {
                    BarcodeScannerView { scanned in
                        value = scanned
                        isScannerPresented = false
                    }
                }
            }
#endif
        }
    }
}
