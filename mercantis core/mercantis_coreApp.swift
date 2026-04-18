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

    var body: some Scene {
        WindowGroup {
            NavigationShell()
                .environmentObject(docTypeTooling)
        }
    }
}
