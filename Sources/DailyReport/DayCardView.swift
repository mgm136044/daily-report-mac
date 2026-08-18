import SwiftUI
import DailyReportKit

/// One day's card: date + rolled-up counts, in the app's material/stroke look.
struct DayCardView: View {
    @EnvironmentObject var state: AppState
    let card: DayCard
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.date).font(.system(size: 13, weight: .semibold))
                if card.synced {
                    Text("Notion에 기록됨")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if card.kind == .skipped {
                    Text(card.skippedReason ?? "건너뜀")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("프로젝트 \(card.projects) · 세션 \(card.sessions) · 파일 \(card.files) · 커밋 \(card.commits)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if card.kind == .done && !card.synced {
                Text("\(card.reportChars)자")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            }
            // Only offer PDF for a day that actually has a report — a skipped day has
            // no report_<date>.md to render.
            if card.kind == .done {
                Button {
                    state.generateAndViewPDF(for: card.date)
                } label: {
                    Image(systemName: "doc.richtext")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Design.accent)
                .help("이 날짜를 PDF로 보기")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .card(active: card.kind == .done)
    }
}
