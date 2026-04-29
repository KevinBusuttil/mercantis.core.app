//
//  ImageField.swift
//  mercantis core
//
//  W8: Inline image preview + chooser for FieldType.image. (ADR-034)
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(PhotosUI) && os(iOS)
import PhotosUI
#endif
#if os(macOS)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public struct ImageField: View {
    @Binding var value: Data?
    let isReadOnly: Bool

#if canImport(PhotosUI) && os(iOS)
    @State private var pickerItem: PhotosPickerItem?
#endif

    public init(value: Binding<Data?>, isReadOnly: Bool) {
        self._value = value
        self.isReadOnly = isReadOnly
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
            if !isReadOnly { chooser }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let data = value, let img = platformImage(from: data) {
            img.resizable().scaledToFit().frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(MercantisTheme.surfaceMuted)
                .frame(height: 80)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder
    private var chooser: some View {
#if canImport(PhotosUI) && os(iOS)
        PhotosPicker("Choose image…", selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let item, let data = try? await item.loadTransferable(type: Data.self) {
                        value = data
                    }
                }
            }
#elseif os(macOS)
        Button("Choose image…") {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
                value = data
            }
        }
#else
        EmptyView()
#endif
        if value != nil {
            Button("Clear", role: .destructive) { value = nil }.font(.caption)
        }
    }

    private func platformImage(from data: Data) -> Image? {
#if os(macOS)
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
#else
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
#endif
    }
}
