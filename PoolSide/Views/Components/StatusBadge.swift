import SwiftUI

struct StatusBadge: View {
    let status: ChemicalStatus
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
            if !compact {
                Text(status.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(status.color.opacity(0.2), in: Capsule())
        .overlay(Capsule().stroke(status.color.opacity(0.4), lineWidth: 0.5))
        .foregroundStyle(status.color)
    }
}

// MARK: - Score Ring

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 48

    private var color: Color {
        switch score {
        case 80...100: return PoolColor.statusIdeal
        case 60..<80:  return PoolColor.statusSlight
        case 40..<60:  return PoolColor.statusOffRange
        default:       return PoolColor.statusCritical
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: score)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.7))
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)
            }
        }
    }
}

// MARK: - Loading Overlay

struct AILoadingOverlay: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(PoolColor.poolTeal)
                .scaleEffect(0.9)
            Text("Analysing chemistry…")
                .font(.subheadline)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.4), radius: 16)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(PoolColor.poolTeal.opacity(0.6))

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PoolColor.cloudWhite)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.cloudWhite.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            if let label = actionLabel, let action {
                Button(action: action) {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.deepWater)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(PoolColor.sunshine, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(32)
    }
}
