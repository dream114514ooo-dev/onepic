//
//  OnePicApp.swift
//  OnePic
//
//  Created by Emmaa on 5/8/26.
//

import SwiftUI
import SwiftData

@main
struct OnePicApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Photo.self,
        ])
        #if DEBUG
        #if targetEnvironment(simulator)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        #else
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        #endif
        #else
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        #endif

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
