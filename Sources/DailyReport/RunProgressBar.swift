import SwiftUI
import DailyReportKit

/// The live progress panel for a run. Determinate by stage so it visibly advances;
/// during the long "요약" (model) step it adds a spinner and a note so a multi-minute
/// wait doesn't look frozen. `progress == nil` means the run has started but no stage
/// line has arrived yet (or the lock is being checked) → an indeterminate "시작 중…".
///
/// Shared by the live popover (StatusView) and the `--render-progress` design preview
/// so the two can never drift.
struct RunProgressBar: View {
    let progress: RunProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let p = progress {
                ProgressView(value: p.fraction).tint(Design.accent)
                HStack(spacing: 6) {
                    if p.stage == .summarize { ProgressView().controlSize(.mini) }
                    Text(label(p)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((p.fraction * 100).rounded()))%")
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                if p.stage == .summarize {
                    Text("요약은 수십 초~수 분 걸릴 수 있어요.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("시작 중…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Stage label, with "날짜 i/N" appended when a backfill spans multiple days.
    private func label(_ p: RunProgress) -> String {
        p.totalDates > 1 ? "\(p.stage.label) · 날짜 \(p.dateIndex)/\(p.totalDates)" : p.stage.label
    }
}
