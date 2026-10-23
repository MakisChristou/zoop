import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("snoop").font(.largeTitle)
            Text("Next: connect to the strap and show live heart rate.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
