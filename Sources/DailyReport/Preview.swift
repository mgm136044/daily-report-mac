import SwiftUI
import DailyReportKit

enum Preview {
    /// Render the status popover with sample data to `path` and exit. Lets the
    /// design be reviewed without launching the menu bar app interactively.
    @MainActor static func render(to path: String) {
        let sample = LedgerSummary(cards: [
            DayCard(date: "2026-08-13", kind: .done, projects: 4, sessions: 42, files: 398,
                    commits: 12, reportChars: 6025, skippedReason: nil, at: nil),
            DayCard(date: "2026-08-12", kind: .done, projects: 2, sessions: 18, files: 140,
                    commits: 5, reportChars: 4200, skippedReason: nil, at: nil),
            DayCard(date: "2026-08-11", kind: .skipped, projects: 0, sessions: 0, files: 0,
                    commits: 0, reportChars: 0, skippedReason: "활동 없음", at: nil),
        ], pendingCount: 1, health: .needsAttention(pending: 1))

        renderToPNG(StatusPreview(summary: sample).frame(width: 380), to: path)
    }

    /// Renders the setup wizard's five steps (plus step-5 success and failure states)
    /// side by side, for pre-ship design review without a live Notion connect.
    @MainActor static func renderWizard(to path: String) {
        let sampleURL = "https://notion.so/한-일-정리-1a259c31abcd1234ef567890abcdef12"
        let strip = HStack(alignment: .top, spacing: 24) {
            SetupWizardView(initialStep: 1)
            SetupWizardView(initialStep: 2, previewToken: "ntn_v1aBcDeFgHiJkLmNoPqRsTuVwXyZ012345")
            SetupWizardView(initialStep: 3, previewURL: sampleURL)
            SetupWizardView(initialStep: 4, previewURL: sampleURL)
            SetupWizardView(initialStep: 5,
                            previewDone: "연결 완료 (DB 1a259c31…) · 기존 보고서 13일 동기화")
            SetupWizardView(initialStep: 5,
                            previewRemedy: SetupHint.remedy(for: .http(404, "object_not_found", "")))
        }
        .environmentObject(AppState())
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))

        renderToPNG(strip, to: path)
    }

    @MainActor private static func renderToPNG(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("렌더 실패\n".utf8)); return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("rendered → \(path)\n".utf8))
    }
}

/// A non-EnvironmentObject variant of StatusView for rendering with fixed data.
struct StatusPreview: View {
    let summary: LedgerSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // update banner (sky-blue info)
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                Text("새 버전 v1.2.0 준비됨 · 지금 설치").font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Design.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Design.accent)

            HStack {
                Text("하루 마감 보고서")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if case .needsAttention(let n) = summary.health {
                    Text("밀린 날짜 \(n)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            VStack(spacing: 8) {
                ForEach(summary.cards, id: \.date) { DayCardView(card: $0) }
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("보고서 만들기").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Text("오늘 보고서 만들기")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Design.accent, in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 8) {
                    Text("지난 날짜").foregroundStyle(.secondary)
                    Text("2026-08-01").padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    Spacer()
                    Text("만들기")
                }
                .font(.system(size: 12))
            }

            Divider()
            HStack(spacing: 12) {
                Text("밀린 날 처리").foregroundStyle(Design.accent)
                Spacer()
                Text("설정")
                Text("종료").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            HStack(spacing: 8) {
                Text("업데이트 확인").font(.system(size: 10)).foregroundStyle(Design.accent)
                Spacer()
                Text("v\(AppVersion.current)").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.background)
    }
}
