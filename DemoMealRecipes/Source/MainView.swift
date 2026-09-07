import SwiftUI

struct MainView: View {
    static let launchSampleFeatureButtonAccessibilityIdentifier = "main.launchSampleFeatureButton"

    var body: some View {
        ScrollView {
            VStack {
                NavigationLink {
                    SampleFeatureView()
                } label: {
                    Text("Launch Sample Feature")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(Self.launchSampleFeatureButtonAccessibilityIdentifier)
            }
            .padding(16)
        }
        .navigationTitle(String(localized: .mainScreenTitle))
    }
}

#Preview {
    NavigationStack {
        MainView()
    }
}
