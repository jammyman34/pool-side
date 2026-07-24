import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

    @State private var selectedTab: Tab = .dashboard
    @State private var showingAddTest = false
    @State private var showingSettings = false
    @State private var showingStartupSplash = true
    @State private var hasStartedFirstUseSetup = false
    @State private var firstTestFlowInProgress = false
    @State private var firstTestTreatmentPlanDisplayed = false
    @State private var testCountWhenOpeningAddTest = 0

    private var firstUseState: FirstUseStateResolver.State {
        FirstUseStateResolver.resolve(
            isConfigurationPersisted: PoolConfiguration.isConfigured,
            configuration: viewModel.poolConfig,
            savedTestCount: tests.count,
            hasStartedSetup: hasStartedFirstUseSetup,
            firstTestFlowInProgress: firstTestFlowInProgress,
            firstTestTreatmentPlanDisplayed: firstTestTreatmentPlanDisplayed
        )
    }

    var body: some View {
        ZStack {
            rootContent

            if showingStartupSplash {
                StartupSplashView()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .fullScreenCover(isPresented: $showingAddTest, onDismiss: handleAddTestDismissed) {
            AddTestView(onFirstTestTreatmentPlanDisplayed: {
                firstTestTreatmentPlanDisplayed = true
            })
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            viewModel.refreshConfigFromStorage(reconcilingWith: tests)
        }
        .onChange(of: tests.count) { _, _ in
            viewModel.refreshConfigFromStorage(reconcilingWith: tests)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeOut(duration: 0.2)) {
                showingStartupSplash = false
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch firstUseState {
        case .welcome:
            FirstUseWelcomeView {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    hasStartedFirstUseSetup = true
                }
            }
        case .poolSetup:
            FirstUsePoolSetupView {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    hasStartedFirstUseSetup = false
                }
            }
        case .firstTestEmptyDashboard, .firstTestInProgress, .firstTestCompletedTreatmentPlan:
            firstTestDashboard
        case .normalDashboard:
            normalDashboard
        }
    }

    private var normalDashboard: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(
                        showingAddTest: $showingAddTest,
                        showingSettings: $showingSettings
                    )
                case .insights:
                    InsightsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PoolTabBar(
                selectedTab: $selectedTab,
                showingAddTest: $showingAddTest,
                onAddTest: openAddTest,
                plusNamespace: nil,
                isAddButtonEnabled: true
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var firstTestDashboard: some View {
        FirstTestEmptyDashboardView(
            onAddFirstTest: openAddTest,
            onOpenSettings: {
                showingSettings = true
            },
            isTransitioning: false,
            plusNamespace: nil
        )
    }

    private func openAddTest() {
        testCountWhenOpeningAddTest = tests.count
        firstTestFlowInProgress = tests.isEmpty
        firstTestTreatmentPlanDisplayed = false
        showingAddTest = true
    }

    private func handleAddTestDismissed() {
        defer {
            firstTestFlowInProgress = false
            firstTestTreatmentPlanDisplayed = false
        }

        if testCountWhenOpeningAddTest == 0 && tests.count > 0 {
            selectedTab = .dashboard
        }
    }
}

// MARK: - Startup Splash

private struct StartupSplashView: View {
    var body: some View {
        ZStack {
            Image("Pool Water BG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            Color.white
                .opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("PoolSide")
                    .font(.custom("AvenirNext-DemiBold", size: 42))
                    .foregroundStyle(PoolColor.deepWater)
                    .minimumScaleFactor(0.78)
//                    .offset(y: 128)

                Image("Test Data Hero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 330)

                Text("Know when it’s ready to swim")
                    .font(.custom("AvenirNext-Medium", size: 20))
                    .foregroundStyle(PoolColor.deepWater.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
                    //.offset(y: 0)
            }
            .padding(.horizontal, 32)
            .offset(y: 4)
        }
    }
}

// MARK: - Tab

enum Tab: Hashable {
    case dashboard, insights
}

// MARK: - Tab Bar

struct PoolTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showingAddTest: Bool
    var onAddTest: (() -> Void)? = nil
    var plusNamespace: Namespace.ID? = nil
    var isAddButtonEnabled: Bool = true

    private let raisedHeight: CGFloat = 24
    private let buttonSize: CGFloat = 80

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .dashboard, icon: "house.fill", label: "Dashboard")
            Spacer()
            Color.clear.frame(width: buttonSize + 28, height: 1)
            Spacer()
            tabButton(tab: .insights, icon: "chart.bar.fill", label: "Insights")
        }
        .padding(.horizontal, 40)
        .padding(.top, raisedHeight + 34)
        .padding(.bottom, 28)
        .background(
            RaisedCenterTabBarShape(raisedHeight: raisedHeight)
                .fill(PoolColor.sand)
                .shadow(color: .black.opacity(0.08), radius: 16, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            addButton
                .offset(y: raisedHeight - (buttonSize / 2) + 30)
        }
    }

    private func tabButton(tab: Tab, icon: String, label: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selectedTab == tab ? PoolColor.poolTeal : PoolColor.secondaryText)
            .opacity(selectedTab == tab ? 1.0 : 0.85)
        }
        .frame(width: 84)
    }

    @ViewBuilder
    private var addButton: some View {
        let button = Button {
            if let onAddTest {
                onAddTest()
            } else {
                showingAddTest = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(PoolColor.sunshine)
                    .frame(width: buttonSize, height: buttonSize)
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .shadow(color: PoolColor.sunshine.opacity(0.35), radius: 14, y: 8)
        }
        .disabled(!isAddButtonEnabled)

        if let plusNamespace {
            button.matchedGeometryEffect(id: "firstUsePlus", in: plusNamespace)
        } else {
            button
        }
    }
}

// MARK: - Raised Center Tab Bar Shape

struct RaisedCenterTabBarShape: Shape {
    var raisedHeight: CGFloat = 24
    var cornerRadius: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        Path { p in
            let cx = rect.midX
            let topY = rect.minY + raisedHeight
            let r = min(cornerRadius, rect.width / 2, rect.height / 2)
            let capWidth: CGFloat = 116
            let capHeight: CGFloat = 18
            let capStart = cx - capWidth / 2
            let capEnd = cx + capWidth / 2

            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: topY + r))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX + r, y: topY),
                control: CGPoint(x: rect.minX, y: topY)
            )
            p.addLine(to: CGPoint(x: capStart, y: topY))
            p.addCurve(
                to: CGPoint(x: cx, y: topY - capHeight),
                control1: CGPoint(x: capStart + 22, y: topY),
                control2: CGPoint(x: cx - 34, y: topY - capHeight)
            )
            p.addCurve(
                to: CGPoint(x: capEnd, y: topY),
                control1: CGPoint(x: cx + 34, y: topY - capHeight),
                control2: CGPoint(x: capEnd - 22, y: topY)
            )
            p.addLine(to: CGPoint(x: rect.maxX - r, y: topY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: topY + r),
                control: CGPoint(x: rect.maxX, y: topY)
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
// MARK: - Preview

#Preview {
    ContentView()
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
}
