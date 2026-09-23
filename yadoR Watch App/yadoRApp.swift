//
//  yadoRApp.swift
//  yadoR Watch App
//
//  Created by webull_yado on 18/9/26.
//

import SwiftUI
import WatchKit

@main
struct yadoR_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchApplicationDelegate.self) private var delegate
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
        .backgroundTask(.watchConnectivity) { await delegate.store.receiveBackgroundUpdate() }
    }
}

@MainActor
final class WatchApplicationDelegate: NSObject, WKApplicationDelegate {
    let store = ReadinessStore()
    func applicationDidFinishLaunching() { store.activateServices() }
}
