//
//  mercantis_coreApp.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI

@main
struct mercantis_coreApp: App {
    static let visualBuilderWindowID = "visual-builder"

    @StateObject private var docTypeTooling = DocTypeToolingContext()
    @StateObject private var shellRouter = UIShellRouter()

    var body: some Scene {
        WindowGroup {
            NavigationShell()
                .environmentObject(docTypeTooling)
                .environmentObject(shellRouter)
                #if os(macOS)
                .font(.system(size: 13, weight: .regular, design: .default))
                #else
                .font(.system(size: 15, weight: .regular, design: .default))
                #endif
        }
        #if os(macOS)
        WindowGroup("Visual Builder", id: Self.visualBuilderWindowID, for: String.self) { $docTypeID in
            NavigationStack {
                FormBuilderView(initialDocTypeID: docTypeID.wrappedValue) {
                    docTypeTooling.reload()
                }
            }
            .frame(minWidth: 1000, idealWidth: 1280, minHeight: 620, idealHeight: 760)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environmentObject(docTypeTooling)
        }
        #endif
        #if os(macOS)
        .commands {
            CommandMenu("DocTypes") {
                Button("Open DocTypes") {
                    shellRouter.openDocTypes()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
        }
        #endif
    }
}
