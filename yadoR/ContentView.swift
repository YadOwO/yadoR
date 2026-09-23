import SwiftUI

struct ContentView: View {
    var body: some View {
        ReadinessHomeView()
    }
}

#Preview {
    ContentView()
        .environment(ReadinessStore(preview: true))
}
