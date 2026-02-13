//
//  NexMathiOSApp.swift
//  NexMathiOS
//
//  Created by Elias Mendoza on 2/5/26.
//

import SwiftUI
import SwiftData
import FirebaseCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct NexMathiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: ChatSession.self, PersistedMessage.self)
        } catch {
            // Graceful degradation: Fall back to in-memory storage if persistent storage fails
            print("⚠️ Could not create persistent ModelContainer: \(error)")
            print("⚠️ Falling back to in-memory storage")

            do {
                let config = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: ChatSession.self, PersistedMessage.self, configurations: config)
            } catch {
                fatalError("Could not create in-memory ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await AuthManager.shared.ensureSignedIn()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
