import SwiftUI

struct ContextualEducationTipView: View {
    let content: ContextualTipContent
    let showsCloseButton: Bool
    let primaryActionTitle: String
    let onClose: (() -> Void)?
    let onPrimaryAction: () -> Void

    private var cardBackground: Color {
        Color.black.opacity(0.74)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(content.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(content.body)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, showsCloseButton ? 42 : 0)

            Button(action: onPrimaryAction) {
                Text(primaryActionTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel(primaryActionTitle)
        }
        .padding(22)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if showsCloseButton, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close walkthrough")
                .padding(.top, 22)
                .padding(.trailing, 22)
            }
        }
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        .padding(20)
    }
}

struct ContextualTipSheetModifier: ViewModifier {
    @Bindable var educationStore: ContextualEducationStore
    let tip: ContextualTipContent
    let isEligible: Bool
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    floatingOverlay {
                        ContextualEducationTipView(
                            content: tip,
                            showsCloseButton: false,
                            primaryActionTitle: "Got It",
                            onClose: nil,
                            onPrimaryAction: {
                                educationStore.markSeen(tip.id)
                                withAnimation(.easeOut(duration: 0.18)) {
                                    isPresented = false
                                }
                            }
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(100)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isPresented)
            .onAppear(perform: presentIfNeeded)
            .onChange(of: isEligible) { _, _ in presentIfNeeded() }
    }

    private func presentIfNeeded() {
        guard isEligible, !educationStore.hasSeen(tip.id) else { return }
        DispatchQueue.main.async {
            guard isEligible, !educationStore.hasSeen(tip.id) else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isPresented = true
            }
        }
    }

    private func floatingOverlay<OverlayContent: View>(@ViewBuilder content: () -> OverlayContent) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()

            content()
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

extension View {
    func contextualTip(_ tip: ContextualTipContent, isEligible: Bool = true, store: ContextualEducationStore = .shared) -> some View {
        modifier(ContextualTipSheetModifier(educationStore: store, tip: tip, isEligible: isEligible))
    }
}

struct DashboardWalkthroughSheetModifier: ViewModifier {
    @Bindable var educationStore: ContextualEducationStore
    let isEligible: Bool
    @State private var isPresented = false
    @State private var stepIndex = 0

    private let steps: [ContextualTipContent] = ContextualWalkthroughID.dashboard.tipIDs.map(ContextualTipContent.content(for:))

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()

                        VStack(spacing: 0) {
                            ContextualEducationTipView(
                                content: steps[stepIndex],
                                showsCloseButton: true,
                                primaryActionTitle: stepIndex == steps.count - 1 ? "Got It" : "Next",
                                onClose: dismissWalkthrough,
                                onPrimaryAction: advance
                            )
                            .frame(maxWidth: 420)

                            if stepIndex > 0 {
                                Button("Previous") {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        stepIndex -= 1
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PoolColor.poolTeal)
                                .padding(.bottom, 20)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(100)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isPresented)
            .onAppear(perform: presentIfNeeded)
            .onChange(of: isEligible) { _, _ in presentIfNeeded() }
    }

    private func presentIfNeeded() {
        guard isEligible, !educationStore.hasSeen(.dashboard) else { return }
        DispatchQueue.main.async {
            guard isEligible, !educationStore.hasSeen(.dashboard) else { return }
            stepIndex = 0
            withAnimation(.easeOut(duration: 0.18)) {
                isPresented = true
            }
        }
    }

    private func advance() {
        if stepIndex < steps.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                stepIndex += 1
            }
        } else {
            dismissWalkthrough()
        }
    }

    private func dismissWalkthrough() {
        educationStore.markSeen(.dashboard)
        withAnimation(.easeOut(duration: 0.18)) {
            isPresented = false
        }
    }
}

extension View {
    func dashboardWalkthrough(isEligible: Bool, store: ContextualEducationStore = .shared) -> some View {
        modifier(DashboardWalkthroughSheetModifier(educationStore: store, isEligible: isEligible))
    }
}
