import SwiftUI

// MARK: - Service alerts sheet

/// Modal list of every *actionable* FGC alert, sorted by severity (most severe first).
///
/// `.info` alerts are filtered out entirely — they're announcements, not disruptions, and
/// including them makes the sheet feel noisy. Each row unpacks what the inline pill can only
/// summarize: full title, full details, affected line badges, and (when present) a validity
/// window.
struct ServiceAlertsSheet: View {
    let alerts: [ServiceAlert]

    @Environment(\.dismiss) private var dismiss

    private var sortedAlerts: [ServiceAlert] {
        alerts
            .filter { $0.severity != .info }
            .sorted { lhs, rhs in
                let lRank = ServiceAlertPresentation.rank(for: lhs.severity)
                let rRank = ServiceAlertPresentation.rank(for: rhs.severity)
                if lRank != rRank { return lRank > rRank }
                // Stable tiebreaker so the list doesn't shuffle across refreshes.
                return lhs.id < rhs.id
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedAlerts.isEmpty {
                    ContentUnavailableView(
                        "All clear",
                        systemImage: "checkmark.circle",
                        description: Text("FGC isn't reporting any disruptions right now.")
                    )
                } else {
                    List {
                        ForEach(sortedAlerts) { alert in
                            ServiceAlertRow(alert: alert)
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Service alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ServiceAlertRow: View {
    let alert: ServiceAlert

    var body: some View {
        let tint = ServiceAlertPresentation.color(for: alert.severity)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(ServiceAlertPresentation.label(for: alert.severity).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint, in: Capsule())

                if !alert.affectedLines.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(alert.affectedLines, id: \.self) { line in
                            Text(line)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            Text(alert.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let details = alert.details, !details.isEmpty {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let window = validityWindowLabel {
                Label(window, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Formats `startDate` / `endDate` into a short human-readable window, or `nil` when we
    /// have neither. Three shapes: both set (`"10:30 → 14:00"`, same-day short), start-only
    /// (`"From 10:30"`), end-only (`"Until 14:00"`).
    private var validityWindowLabel: String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .short

        switch (alert.startDate, alert.endDate) {
        case (let start?, let end?):
            let calendar = Calendar.current
            if calendar.isDate(start, inSameDayAs: end) {
                return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
            }
            return "\(dayFormatter.string(from: start)) → \(dayFormatter.string(from: end))"
        case (let start?, nil):
            return "From \(dayFormatter.string(from: start))"
        case (nil, let end?):
            return "Until \(dayFormatter.string(from: end))"
        case (nil, nil):
            return nil
        }
    }
}
