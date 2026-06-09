import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]
    @State private var selectedTab: Tab = .dashboard
    @State private var showingAddTest = false
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DashboardView(showingAddTest: $showingAddTest)
                    .tag(Tab.dashboard)

                HistoryView()
                    .tag(Tab.history)

                TreatmentsView()
                    .tag(Tab.treatments)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom tab bar
            CustomTabBar(
                selectedTab: $selectedTab,
                showingAddTest: $showingAddTest,
                pendingCount: viewModel.pendingTreatments(from: tests).count
            )
        }
        .background(PoolColor.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showingAddTest) {
            AddTestView()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            if !PoolConfiguration.isConfigured {
                showingSettings = true
            }
        }
    }
}

// MARK: - Tab

enum Tab: Hashable {
    case dashboard, history, treatments
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showingAddTest: Bool
    let pendingCount: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .dashboard, icon: "drop.fill", label: "Dashboard")
            Spacer()
            addButton
            Spacer()
            treatmentsTabButton
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(PoolColor.oceanBlue)
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabButton(tab: Tab, icon: String, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(selectedTab == tab ? PoolColor.poolTeal : PoolColor.cloudWhite.opacity(0.5))
        }
        .frame(width: 64)
    }

    private var addButton: some View {
        Button {
            showingAddTest = true
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient.sunshineAction)
                    .frame(width: 60, height: 60)
                    .shadow(color: PoolColor.sunshine.opacity(0.5), radius: 12, y: 4)
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(PoolColor.deepWater)
            }
        }
        .offset(y: -16)
    }

    private var treatmentsTabButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = .treatments
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "checklist")
                        .font(.system(size: 22, weight: .medium))
                    if pendingCount > 0 {
                        Text("\(min(pendingCount, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PoolColor.deepWater)
                            .padding(3)
                            .background(PoolColor.coral, in: Circle())
                            .offset(x: 10, y: -8)
                    }
                }
                Text("Treatments")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundStyle(selectedTab == .treatments ? PoolColor.poolTeal : PoolColor.cloudWhite.opacity(0.5))
        }
        .frame(width: 64)
    }
}
