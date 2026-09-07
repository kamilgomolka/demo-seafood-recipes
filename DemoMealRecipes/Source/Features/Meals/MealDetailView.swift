import SwiftUI

struct MealRemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
                    .background(.quaternary)
            case .empty:
                Image(systemName: "fork.knife")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
                    .background(.quaternary)
            @unknown default:
                Color.clear
            }
        }
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
                ProgressView("Loading recipe…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("meal.detail.loading")
            case .failed(let error):
                ContentUnavailableView {
                    Label("Couldn't load recipe", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.message)
                } actions: {
                    retryButton
                }
            case .loaded(let details):
                recipe(details)
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

    private var retryButton: some View {
        Button("Try again") {
            retryRequested = true
            retryCount += 1
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.state.isLoading)
        .accessibilityIdentifier("meal.detail.retry")
    }

    private func recipe(_ details: MealDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MealRemoteImage(url: details.thumbnailURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(details.name)
                        .font(.title2)
                        .bold()
                    if let category = details.category, let area = details.area {
                        Text("\(category) · \(area)")
                            .foregroundStyle(.secondary)
                    } else if let category = details.category {
                        Text(category)
                            .foregroundStyle(.secondary)
                    } else if let area = details.area {
                        Text(area)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                if !details.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .font(.headline)
                        ForEach(Array(details.ingredients.enumerated()), id: \.offset) { _, ingredient in
                            HStack(alignment: .top) {
                                Text(ingredient.measure)
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 72, alignment: .leading)
                                Text(ingredient.name)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions")
                        .font(.headline)
                    Text(details.instructions)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
}
