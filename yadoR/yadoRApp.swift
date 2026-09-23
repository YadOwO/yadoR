//
//  yadoRApp.swift
//  yadoR
//
//  Created by webull_yado on 18/9/26.
//

import SwiftUI
import UIKit

@main
struct yadoRApp: App {
    @UIApplicationDelegateAdaptor(PhoneApplicationDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(delegate.store)
                .task { await delegate.store.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await delegate.store.start() } }
                }
        }
    }
}

@MainActor
final class PhoneApplicationDelegate: NSObject, UIApplicationDelegate {
    let store = ReadinessStore()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        store.activateServices()
        return true
    }
}
