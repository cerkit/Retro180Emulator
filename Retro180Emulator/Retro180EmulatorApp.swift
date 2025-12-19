//
//  Retro180EmulatorApp.swift
//  Retro180Emulator
//
//  Created by Michael Earls on 12/18/25.
//

import SwiftUI

@main
struct Retro180EmulatorApp: App {
    @AppStorage("monitorColor") private var monitorColor: MonitorColor = .amber

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("Display") {
                Picker("Monitor Color", selection: $monitorColor) {
                    ForEach(MonitorColor.allCases) { color in
                        Text(color.rawValue.capitalized).tag(color)
                    }
                }
            }
        }
    }
}
