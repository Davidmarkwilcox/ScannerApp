// ContentView.swift
// File: ContentView.swift
// Description: App-level navigation shell for ScannerApp. Hosts the root UI (tabs + navigation) and provides
// lightweight debug plumbing shared across screens (debug default Off). Applies Theme defaults.
//
// Section 1. Imports
import SwiftUI

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
           // ScannerDebug.writeLog("ContentView appeared")
        }
    }
}

// Section 4. Preview
#Preview {
    ContentView()
}

// End of file: ContentView.swift
