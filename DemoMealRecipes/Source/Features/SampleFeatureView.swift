import SwiftUI

struct SampleFeatureView: View {
    static let bodyLabelAccessibilityIdentifier = "sampleFeature.bodyLabel"

    var body: some View {
        Text("Body Label")
            .font(.title)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .accessibilityIdentifier(Self.bodyLabelAccessibilityIdentifier)
            .navigationTitle(String(localized: .sampleFeatureTitle))
    }
}

#Preview {
    NavigationStack {
        SampleFeatureView()
    }
}
