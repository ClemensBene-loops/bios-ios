import SwiftUI

/// The single main view: Whoop check and outlook from `/v1/summary`
/// (cached offline), push status as a compact footer section.
///
/// Refreshes on appear, on pull-to-refresh, when the app becomes active
/// (BIOSApp) and after a push tap, which also scrolls to and highlights the
/// matching section (`thread-id` "whoop" or "outlook").
struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var store: SummaryStore
    @State private var highlighted: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        FreshnessRow(
                            fetchedAt: store.fetchedAt,
                            isLoading: store.isLoading,
                            error: store.lastError
                        )
                    }

                    WhoopCheckSection(
                        check: store.summary?.whoop,
                        isHighlighted: highlighted == SectionID.whoop
                    )

                    OutlookSections(
                        outlook: store.summary?.outlookModel,
                        isHighlighted: highlighted == SectionID.outlook
                    )

                    PushStatusSection(state: state)
                }
                .listStyle(.insetGrouped)
                .navigationTitle("BIOS")
                .refreshable {
                    await store.refresh(force: true)
                }
                .task {
                    await store.refresh()
                }
                .onAppear {
                    openPendingPush(proxy: proxy)
                }
                .onChange(of: state.pendingOpen) { _, _ in
                    openPendingPush(proxy: proxy)
                }
            }
        }
    }

    /// Consumes `AppState.pendingOpen`: scroll + highlight, then refresh.
    private func openPendingPush(proxy: ScrollViewProxy) {
        guard let push = state.pendingOpen else { return }
        state.pendingOpen = nil
        let target = SectionID.forPush(push)
        Task { @MainActor in
            // Give the list a moment to lay out (cold start from a tap).
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation {
                proxy.scrollTo(target, anchor: .top)
                highlighted = target
            }
            await store.refresh(force: true)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if highlighted == target {
                withAnimation {
                    highlighted = nil
                }
            }
        }
    }
}

#Preview {
    ContentView(state: AppState.preview(), store: SummaryStore(loadCache: false))
}
