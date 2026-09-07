import SwiftUI

struct MealRemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder("exclamationmark.triangle")
            case .empty:
                placeholder("fork.knife")
            @unknown default:
                Color.clear
            }
        }
    }

    private func placeholder(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
            .background(.quaternary)
    }
}

struct MealDetailView: View {
    @State private var viewModel: MealDetailViewModel
    @State private var retryCount = 0
    @State private var retryRequested = false
    private let title: String

    init(meal: Meal, service: any MealService) {
        title = meal.name
        _viewModel = State(initialValue: MealDetailViewModel(mealID: meal.id, service: service))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView
            case .failed(let error):
                errorView(error)
            case .loaded(let details):
                loadedView(details)
            }
        }
        .accessibilityIdentifier("meal.detail")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retryCount) {
            if retryRequested {
                retryRequested = false
                await viewModel.reload()
            } else {
                await viewModel.loadIfNeeded()
            }
        }
    }

    private var loadingView: some View {
        ProgressView("Loading recipe…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("meal.detail.loading")
    }

    private func errorView(_ error: MealAPIError) -> some View {
        ContentUnavailableView {
            Label("Couldn't load recipe", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error.message)
        } actions: {
            retryButton
        }
    }

    private var retryButton: some View {
        Button("Try again") {
            retryRequested = true
            retryCount += 1
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.state.isLoading)
        .accessibilityIdentifier("meal.detail.retry")
    }

    private func loadedView(_ details: MealDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MealRemoteImage(url: details.thumbnailURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .accessibilityHidden(true)

                mealHeaderView(details)
                ingredientsView(details)
                instructionsView(details)
            }
        }
    }

    private func mealHeaderView(_ details: MealDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(details.name)
                .font(.title2)
                .bold()
            let subtitle = [details.category, details.area]
                .compactMap { $0 }
                .joined(separator: " · ")
            if !subtitle.isEmpty {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func ingredientsView(_ details: MealDetails) -> some View {
        if !details.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("🛒 Ingredients")
                    .font(.title3).bold()
                ForEach(Array(details.ingredients.enumerated()), id: \.offset) { _, ingredient in
                    HStack(alignment: .top) {
                        Text("• \(ingredient.name)")
                            .font(.subheadline)
                            .frame(alignment: .leading)
                            .padding(.leading, 4.0)
                        Text("(\(ingredient.measure))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top)
            .padding(.horizontal)
        }
    }

    private func instructionsView(_ details: MealDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📖 Instructions")
                .font(.title3).bold()
            Text(details.instructions)
                .padding(.leading, 4.0)
        }
        .padding()
    }
}
