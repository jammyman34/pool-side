import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @State private var selectedTab: Tab = .dashboard
    @State private var showingAddTest = false
    @State private var showingSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content — no TabView wrapper, drive visibility manually
            // to keep the custom tab bar fully in control
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

            // Custom tab bar
            PoolTabBar(
                selectedTab: $selectedTab,
                showingAddTest: $showingAddTest
            )
        }
        .ignoresSafeArea(edges: .bottom)
        .fullScreenCover(isPresented: $showingAddTest) {
            AddTestView()
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
    case dashboard, insights
}

// MARK: - Tab Bar

struct PoolTabBar: View {
    @Binding var selectedTab: Tab
    @Binding var showingAddTest: Bool

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

    private var addButton: some View {
        Button {
            showingAddTest = true
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
