import SwiftUI

struct MealsView: View {
    @State private var viewModel: MealsViewModel
    @State private var retryCount = 0
    @State private var retryRequested = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var searchText = ""
    private let service: any MealService

    init(viewModel: MealsViewModel, service: any MealService) {
        _viewModel = State(initialValue: viewModel)
        self.service = service
    }

    var body: some View {
        List(viewModel.meals(matching: searchText)) { meal in
            NavigationLink(value: meal) {
                HStack(spacing: 16) {
                    MealRemoteImage(url: meal.thumbnailURL)
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityHidden(true)

                    Text(meal.name)
                        .font(.headline)
                        .padding(.vertical, 8)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("meal.\(meal.id)")
            }
            .buttonStyle(.plain)
        }
        .navigationDestination(for: Meal.self) { meal in
            MealDetailView(meal: meal, service: service)
        }
        .listStyle(.plain)
        .accessibilityIdentifier("meals.list")
        .overlay {
            switch viewModel.state {
            case .idle, .loading:
                loadingView
            case .failed(let error):
                errorView(error)
            case .loaded(let meals, _) where meals.isEmpty:
                emptyView
            case .loaded where viewModel.meals(matching: searchText).isEmpty:
                searchEmptyView
            case .loaded:
                EmptyView()
            }
        }
        .safeAreaInset(edge: .top) {
            if case .loaded(_, refresh: .failed(let error)) = viewModel.state {
                errorView(error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.bar)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("meals.refreshError")
            }
        }
        .navigationTitle("Seafood recipes")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search recipes")
        .task(id: retryCount) {
            if retryRequested {
                retryRequested = false
                await viewModel.reload()
            } else {
                await viewModel.loadIfNeeded()
            }
        }
        .refreshable {
            await refresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private var loadingView: some View {
        ProgressView("Loading recipes…")
            .accessibilityIdentifier("meals.loading")
            .allowsHitTesting(false)
    }

    private func errorView(_ error: MealAPIError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.message)
            retryButton
        }
    }

    private var emptyView: some View {
        ContentUnavailableView("No recipes", systemImage: "fork.knife", description: Text("Pull to try again."))
            .accessibilityIdentifier("meals.empty")
            .allowsHitTesting(false)
    }

    private var searchEmptyView: some View {
        ContentUnavailableView.search
            .accessibilityIdentifier("meals.searchEmpty")
            .allowsHitTesting(false)
    }

    private var retryButton: some View {
        Button("Try again") {
            retryRequested = true
            retryCount += 1
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.state.isLoading)
        .accessibilityIdentifier("meals.retry")
    }

    private func refresh() async {
        guard !Task.isCancelled, refreshTask == nil else { return }
        let task = Task { await viewModel.reload() }
        refreshTask = task
        defer {
            if refreshTask == task {
                refreshTask = nil
            }
        }
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
