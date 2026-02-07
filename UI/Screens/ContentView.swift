// ContentView.swift
// File: ContentView.swift
// Description: App-level navigation shell for ScannerApp. Hosts the root UI (tabs + navigation) and provides
// lightweight debug plumbing shared across screens (debug default Off). Applies Theme defaults.
//
// Section 1. Imports
import SwiftUI

// Section 2. Debug (default Off)
// Note: Central debug helper kept here for now; can be promoted to Core/Services later.
enum ScannerDebug {
    static let isEnabled: Bool = false

    static func writeLog(_ message: String, filename: String = "ScannerApp_DebugLog.txt") {
        guard isEnabled else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"

        do {
            let docs = try FileManager.default.url(for: .documentDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: true)
            let url = docs.appendingPathComponent(filename)

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            // Avoid impacting UX.
        }
    }
}

// Section 3. ContentView
struct ContentView: View {

    // Section 3.1 State
    enum Tab: Hashable {
        case library
        case scan
        case settings
    }

    @State private var selectedTab: Tab = .library

    // Section 3.2 Body
    var body: some View {
        TabView(selection: $selectedTab) {

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "doc.on.doc") }
            .tag(Tab.library)

            NavigationStack {
                ScanView()
            }
            .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
            .tag(Tab.scan)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
        .scannerScreen()
        .onAppear {
            ScannerDebug.writeLog("ContentView appeared")
        }
    }
}

// Section 4. Preview
#Preview {
    ContentView()
}

// End of file: ContentView.swift
