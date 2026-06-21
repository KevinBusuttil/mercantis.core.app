//
//  SignatureField.swift
//  mercantis core
//
//  Feature-parity with the Flutter `SignatureField` (signature_field.dart).
//  Captures freehand strokes via a drag gesture on a `Canvas` and stores them
//  as JSON with normalised (0..1) coordinates, so a signature re-renders at any
//  size. The stored shape matches Flutter exactly:
//
//      {"strokes": [[[x, y], [x, y], ...], ...]}
//
//  so signatures round-trip between the Swift and Flutter apps.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct SignatureField: View {
    /// Backing JSON string ("" when unset).
    @Binding var value: String
    let isReadOnly: Bool

    /// Live strokes in normalised (0..1) coordinates.
    @State private var strokes: [[CGPoint]]
    @State private var canvasSize: CGSize = .zero

    public init(value: Binding<String>, isReadOnly: Bool) {
        self._value = value
        self.isReadOnly = isReadOnly
        _strokes = State(initialValue: Self.decodeStrokes(value.wrappedValue))
    }

    private var hasSignature: Bool { strokes.contains { !$0.isEmpty } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    var path = Path()
                    for stroke in strokes where !stroke.isEmpty {
                        let scaled = stroke.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                        if scaled.count == 1 {
                            // A single tap — draw a dot.
                            let p = scaled[0]
                            path.addEllipse(in: CGRect(x: p.x - 1.25, y: p.y - 1.25, width: 2.5, height: 2.5))
                        } else {
                            path.move(to: scaled[0])
                            for p in scaled.dropFirst() { path.addLine(to: p) }
                        }
                    }
                    context.stroke(
                        path,
                        with: .color(MercantisTheme.textPrimary),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                }
                .background(
                    Group {
                        if !hasSignature {
                            Text(isReadOnly ? "No signature" : "Drag to sign")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                )
                .contentShape(Rectangle())
                .gesture(
                    isReadOnly ? nil : DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let size = geo.size
                            canvasSize = size
                            guard size.width > 0, size.height > 0 else { return }
                            let norm = CGPoint(
                                x: min(max(v.location.x / size.width, 0), 1),
                                y: min(max(v.location.y / size.height, 0), 1)
                            )
                            if v.translation == .zero {
                                // Gesture just began — start a new stroke.
                                strokes.append([norm])
                            } else if !strokes.isEmpty {
                                strokes[strokes.count - 1].append(norm)
                            }
                        }
                        .onEnded { _ in commit() }
                )
            }
            .frame(height: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )

            if !isReadOnly && hasSignature {
                Button {
                    strokes = []
                    value = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    private func commit() {
        value = hasSignature ? Self.encodeStrokes(strokes) : ""
    }

    // MARK: - Encoding (matches Flutter signature_field.dart)

    private struct Envelope: Codable {
        let strokes: [[[Double]]]
    }

    /// Decodes the stored JSON into normalised strokes. Tolerates nil / malformed
    /// input by returning an empty list.
    public static func decodeStrokes(_ raw: String?) -> [[CGPoint]] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return [] }
        return env.strokes.map { stroke in
            stroke.compactMap { p in
                p.count >= 2 ? CGPoint(x: p[0], y: p[1]) : nil
            }
        }
    }

    /// Encodes normalised strokes to the stored JSON shape.
    public static func encodeStrokes(_ strokes: [[CGPoint]]) -> String {
        let env = Envelope(strokes: strokes.map { $0.map { [Double($0.x), Double($0.y)] } })
        guard let data = try? JSONEncoder().encode(env),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}
