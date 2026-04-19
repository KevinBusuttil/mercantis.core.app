//
//  mercantis_coreApp.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI

@main
struct mercantis_coreApp: App {
    @StateObject private var docTypeTooling = DocTypeToolingContext()
    @StateObject private var shellRouter = UIShellRouter()

    var body: some Scene {
        WindowGroup {
            NavigationShell()
                .environmentObject(docTypeTooling)
                .environmentObject(shellRouter)
                .tint(MercantisTheme.primary)
                #if os(macOS)
                .font(.system(size: 13, weight: .regular, design: .default))
                #else
                .font(.system(size: 15, weight: .regular, design: .default))
                #endif
        }
        #if os(macOS)
        .commands {
            CommandMenu("Setup") {
                Button("Setup Home") {
                    shellRouter.showSetupOverview()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Divider()

                Button("New DocType") {
                    shellRouter.openNewDocType()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Visual Builder") {
                    shellRouter.openVisualBuilder()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}
