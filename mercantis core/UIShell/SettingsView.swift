//
//  SettingsView.swift
//  mercantis core
//
//  Feature-parity port of the Flutter `SettingsView`
//  (`mercantis_core_ui/lib/src/views/settings_view.dart`). Real settings
//  surface for the Core shell: an appearance (color-scheme) picker backed by
//  `@AppStorage`, plus an About section showing app name / version.
//
//  Replaces the three-static-label placeholder that `NavigationShell` renders
//  for `NavigationSection.settings`. Wiring is described in
//  `CORE_VIEWS_WIRING.md` — this file does not edit `NavigationShell`.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// User-facing appearance preference. Mirrors Flutter's `ThemeMode`
/// (`system` / `light` / `dark`). Persisted as a raw string under
/// `MercantisAppearancePreference.storageKey` so `@AppStorage` can drive the
/// picker and any host that wants to apply `.preferredColorScheme`.
public enum MercantisColorSchemePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// Stable key shared between the picker and any host applying the scheme.
    public static let storageKey = "mercantis.appearance.colorScheme"

    public var label: String {
        switch self {
        case .system: return "System default"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    public var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// The SwiftUI `ColorScheme` to apply, or `nil` to follow the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Real settings screen for Mercantis Core. Theme-mode picker + About section,
/// mirroring the Flutter port. Read-only apart from the appearance preference,
/// which is persisted via `@AppStorage`.
public struct SettingsView: View {

    /// App name shown in the About row. Defaults to the bundle display name.
    private let appName: String
    /// Version string shown in the About row. Defaults to the bundle version.
    private let appVersion: String?

    @AppStorage(MercantisColorSchemePreference.storageKey)
    private var rawScheme: String = MercantisColorSchemePreference.system.rawValue

    public init(appName: String? = nil, appVersion: String? = nil) {
        self.appName = appName ?? Self.bundleAppName
        self.appVersion = appVersion ?? Self.bundleAppVersion
    }

    private var selection: Binding<MercantisColorSchemePreference> {
        Binding(
            get: { MercantisColorSchemePreference(rawValue: rawScheme) ?? .system },
            set: { rawScheme = $0.rawValue }
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appearanceCard
                aboutCard
            }
            .padding()
        }
        .background(MercantisTheme.background)
        .navigationTitle("Settings")
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").font(.headline)
            // A radio-style picker mirrors the Flutter `RadioListTile` group.
            ForEach(MercantisColorSchemePreference.allCases) { mode in
                Button {
                    selection.wrappedValue = mode
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbol)
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        Text(mode.label)
                        Spacer()
                        Image(systemName: selection.wrappedValue == mode
                              ? "largecircle.fill.circle"
                              : "circle")
                            .foregroundStyle(selection.wrappedValue == mode
                                             ? MercantisTheme.accent
                                             : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == mode ? [.isSelected] : [])
            }
        }
        .mercantisCard()
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About").font(.headline)
            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(MercantisTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appName)
                        .font(.body.weight(.semibold))
                    if let appVersion {
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .mercantisCard()
    }

    // MARK: - Bundle metadata

    private static var bundleAppName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "Mercantis"
    }

    private static var bundleAppVersion: String? {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil):    return short
        case let (nil, build?):    return build
        default:                   return nil
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(appName: "Mercantis Core", appVersion: "1.0.0 (42)")
        .frame(width: 480, height: 420)
}
#endif
