import SwiftUI

struct ChemicalStatusCard: View {
    let reading: ChemicalReading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.parameter)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.65))

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(formattedValue)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(PoolColor.cloudWhite)
                        if !reading.unit.isEmpty {
                            Text(reading.unit)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(PoolColor.cloudWhite.opacity(0.55))
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    statusIcon
                    if let trend = reading.trend {
                        trendIndicator(trend)
                    }
                }
            }

            // Range bar
            RangeBar(value: reading.value, parameter: reading.key, status: reading.status)

            // Ideal range label
            Text("Ideal: \(reading.idealRange)")
                .font(.caption2)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.45))
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(reading.status.color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var formattedValue: String {
        if reading.parameter == "pH" {
            return String(format: "%.1f", reading.value)
        }
        return reading.value >= 100
            ? String(format: "%.0f", reading.value)
            : String(format: "%.1f", reading.value)
    }

    private var cardBackground: some ShapeStyle {
        if reading.status == .critical {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [PoolColor.oceanBlue, PoolColor.statusCritical.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(PoolColor.oceanBlue)
    }

    private var statusIcon: some View {
        Image(systemName: reading.status.icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(reading.status.color)
    }

    private func trendIndicator(_ trend: ChemicalReading.Trend) -> some View {
        Image(systemName: trend.icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(PoolColor.cloudWhite.opacity(0.4))
    }
}

// MARK: - Range Bar

struct RangeBar: View {
    let value: Double
    let parameter: String
    let status: ChemicalStatus

    private var range: (min: Double, max: Double, idealMin: Double, idealMax: Double) {
        switch parameter {
        case "pH":              return (6.5, 8.5, 7.2, 7.6)
        case "freeChlorine":    return (0, 6, 1, 3)
        case "totalAlkalinity": return (40, 180, 80, 120)
        case "calciumHardness": return (100, 600, 200, 400)
        case "cyanuricAcid":    return (0, 120, 30, 50)
        case "saltLevel":       return (1500, 5000, 2700, 3400)
        default:                return (0, 100, 30, 70)
        }
    }

    private var progress: CGFloat {
        let r = range
        return CGFloat((value - r.min) / (r.max - r.min)).clamped(to: 0...1)
    }

    private var idealStart: CGFloat {
        let r = range
        return CGFloat((r.idealMin - r.min) / (r.max - r.min)).clamped(to: 0...1)
    }

    private var idealWidth: CGFloat {
        let r = range
        return CGFloat((r.idealMax - r.idealMin) / (r.max - r.min)).clamped(to: 0...0.9)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(PoolColor.deepWater)
                    .frame(height: 6)

                // Ideal zone
                RoundedRectangle(cornerRadius: 3)
                    .fill(PoolColor.statusIdeal.opacity(0.25))
                    .frame(width: idealWidth * w, height: 6)
                    .offset(x: idealStart * w)

                // Indicator
                Circle()
                    .fill(status.color)
                    .frame(width: 10, height: 10)
                    .shadow(color: status.color.opacity(0.6), radius: 4)
                    .offset(x: progress * w - 5, y: -2)
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Previews

#Preview("Ideal pH") {
    ChemicalStatusCard(reading: ChemicalReading(
        parameter: "pH",
        key: "pH",
        value: 7.4,
        unit: "",
        status: .ideal,
        idealRange: "7.2 – 7.6",
        trend: .stable
    ))
    .padding()
    .background(PoolColor.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Critical Chlorine") {
    ChemicalStatusCard(reading: ChemicalReading(
        parameter: "Free Chlorine",
        key: "freeChlorine",
        value: 0.2,
        unit: "ppm",
        status: .critical,
        idealRange: "1 – 3 ppm",
        trend: .falling
    ))
    .padding()
    .background(PoolColor.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Range Bar") {
    VStack(spacing: 16) {
        RangeBar(value: 7.4, parameter: "pH", status: .ideal)
        RangeBar(value: 6.6, parameter: "pH", status: .critical)
        RangeBar(value: 130, parameter: "totalAlkalinity", status: .slightlyHigh)
    }
    .padding()
    .background(PoolColor.appBackground)
    .preferredColorScheme(.dark)
}
