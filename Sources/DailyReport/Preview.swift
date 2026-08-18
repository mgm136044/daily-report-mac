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

        // DayCardView (rendered inside StatusPreview) now reads @EnvironmentObject
        // AppState for its PDF button — inject one here, same as renderWizard below,
        // so this render path doesn't crash on a missing environment object.
        renderToPNG(
            StatusPreview(summary: sample).environmentObject(AppState()).frame(width: 380),
            to: path)
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

    /// Renders the run progress panel across its key states — start, each stage, the
    /// long summarize step with its note, and a multi-day backfill — for design review.
    /// ImageRenderer can't snapshot a live ProgressView, so the bar is drawn statically
    /// here; the running app uses the real native bar (RunProgressBar).
    @MainActor static func renderProgress(to path: String) {
        func bar(_ fraction: Double) -> some View {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.22)).frame(width: 300, height: 6)
                Capsule().fill(Design.accent).frame(width: 300 * fraction, height: 6)
            }
        }
        func row(_ title: String, fraction: Double?, label: String, note: Bool, spinner: Bool) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                if let f = fraction {
                    bar(f)
                    HStack(spacing: 6) {
                        if spinner {
                            Image(systemName: "circle.dotted").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int((f * 100).rounded()))%").font(.system(size: 10, weight: .medium))
                            .monospacedDigit().foregroundStyle(.tertiary)
                    }
                    .frame(width: 300)
                    if note {
                        Text("요약은 수십 초~수 분 걸릴 수 있어요.")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.dotted").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(width: 300, alignment: .leading)
                }
            }
        }
        let strip = VStack(alignment: .leading, spacing: 16) {
            row("시작 중 (아직 단계 없음)", fraction: nil, label: "시작 중…", note: false, spinner: false)
            row("수집", fraction: 0.0, label: "수집 중", note: false, spinner: false)
            row("살균", fraction: 0.25, label: "살균 중", note: false, spinner: false)
            row("요약 (모델 실행, 긴 대기)", fraction: 0.5, label: "요약 중", note: true, spinner: true)
            row("노션 업로드", fraction: 0.75, label: "노션 업로드 중", note: false, spinner: false)
            row("백필 (3일 중 2일째)", fraction: 0.5, label: "요약 중 · 날짜 2/3", note: true, spinner: true)
        }
        .padding(20)
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
            // mirror StatusView §4: fixed 380 card area, unaffected by notices below. No ScrollView here —
            // ImageRenderer (used by --render) can't snapshot a ScrollView's content; the real StatusView keeps it.
            .frame(height: 380, alignment: .top)

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

            // sample notice — demonstrates the card area above stays 380 even with a notice present
            Text("오늘은 기록된 활동이 없어 보고서를 만들지 않았어요.")
                .font(.system(size: 11)).foregroundStyle(.orange)

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
