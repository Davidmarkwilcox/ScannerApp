//
//  ScannerAppApp.swift
//  ScannerApp
//
//  Created by David Wilcox on 2/7/26.
//

import SwiftUI
import CoreData

@main
struct ScannerAppApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
