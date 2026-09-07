import SwiftUI

struct MealsView: View {
    @State private var viewModel: MealsViewModel
    @State private var retryCount = 0
    @State private var retryRequested = false
    @State private var refreshTask: Task<Void, Never>?

    init(viewModel: MealsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        List(viewModel.meals) { meal in
            HStack(spacing: 16) {
                AsyncImage(url: meal.thumbnailURL) { phase in
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
        .listStyle(.plain)
        .accessibilityIdentifier("meals.list")
        .overlay {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading recipes…")
                    .accessibilityIdentifier("meals.loading")
                    .allowsHitTesting(false)
            case .failed(let error):
                ContentUnavailableView {
                    Label("Couldn't load recipes", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.message)
                } actions: {
                    retryButton
                }
            case .loaded(let meals, _) where meals.isEmpty:
                ContentUnavailableView("No recipes", systemImage: "fork.knife", description: Text("Pull to try again."))
                    .accessibilityIdentifier("meals.empty")
                    .allowsHitTesting(false)
            case .loaded:
                EmptyView()
            }
        }
        .safeAreaInset(edge: .top) {
            if case .loaded(_, refresh: .failed(let error)) = viewModel.state {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.message)
                    retryButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)
                .accessibilityIdentifier("meals.refreshError")
            }
        }
        .navigationTitle("Seafood recipes")
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
        let task = Task { [viewModel] in
            await viewModel.reload()
        }
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
