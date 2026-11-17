import SwiftUI

@main
struct SoundBarApp: App {
    @StateObject private var model = AudioModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            Image(systemName: model.menuIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
