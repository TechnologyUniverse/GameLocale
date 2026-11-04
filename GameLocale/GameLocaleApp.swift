//
//  GameLocaleApp.swift
//  GameLocale
//
//  Created by Andrei on 11/3/26.
//

import Sparkle
import SwiftUI

@main
struct GameLocaleApp: App {
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup("GameLocale") {
            GameLibraryView(updater: updaterController.updater)
        }
        .defaultSize(width: 1160, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updaterController.updater)
            }
        }
    }
}


struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    @State private var canCheck = false

    var body: some View {
        Button("Проверить обновления…") { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}
