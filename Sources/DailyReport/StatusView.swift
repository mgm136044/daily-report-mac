import SwiftUI
import DailyReportKit

/// The menu bar popover: update banner + header + recent day cards + report actions.
struct StatusView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var pastDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            updateBanner
            if !state.isConnected { notConnectedBanner }

            HStack {
                Text("하루 마감 보고서")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if case .needsAttention(let n) = state.summary.health {
                    Text("밀린 날짜 \(n)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            if state.summary.cards.isEmpty {
                Text("아직 생성된 보고서가 없습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.summary.cards, id: \.date) { DayCardView(card: $0) }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()
            reportMaker

            if let err = state.lastError {
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = state.notice {
                Text(note).font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack(spacing: 12) {
                if case .needsAttention = state.summary.health {
                    Button("밀린 날 처리") { state.runNow() }.disabled(state.running)
                }
                Spacer()
                // An .accessory app must activate before its Settings scene will
                // actually come forward.
                Button("설정") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Button("종료") { NSApplication.shared.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))

            HStack(spacing: 8) {
                Button { state.checkForUpdate(manual: true) } label: {
                    Text(state.update == .checking ? "확인 중…" : "업데이트 확인")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(Design.accent)
                .disabled(updateBusy)
                Spacer()
                Text("v\(AppVersion.current)")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .onAppear { state.reload() }
    }

    // MARK: - Report maker (기능 2·3)

    private var reportMaker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("보고서 만들기").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)

            Button { state.runToday() } label: {
                HStack(spacing: 6) {
                    if state.running { ProgressView().controlSize(.small) }
                    Text(state.running ? "실행 중…" : "오늘 보고서 만들기")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Design.accent)
            .disabled(state.running)

            progressPanel

            HStack(spacing: 8) {
                Text("지난 날짜").font(.system(size: 12)).foregroundStyle(.secondary)
                DatePicker("", selection: $pastDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
                Spacer()
                Button("만들기") {
                    state.runDate(LogicalDate.calendarString(pastDate, config: state.config))
                }
                .disabled(state.running)
            }
            .font(.system(size: 12))
        }
    }

    /// The live progress bar, shown only while a run is in flight. See RunProgressBar.
    @ViewBuilder private var progressPanel: some View {
        if state.running { RunProgressBar(progress: state.progress) }
    }

    /// Shown until Notion is connected. Tapping opens Settings, where the setup
    /// wizard auto-presents (SettingsView.onAppear) so the user is guided, not dumped
    /// onto raw token/URL fields.
    private var notConnectedBanner: some View {
        Button {
            state.pendingWizard = true      // ask Settings to (re-)present the wizard
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                Text("노션을 연결하면 매일 자동으로 기록돼요 · 연결 시작")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Design.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Design.accent)
            .contentShape(Rectangle())   // whole banner is clickable, not just the text
        }
        .buttonStyle(.plain)
    }

    /// The manual "업데이트 확인" button is disabled while a check or download is in
    /// flight (prevents a re-check clobbering an in-progress download).
    private var updateBusy: Bool {
        switch state.update {
        case .checking, .downloading: return true
        default: return false
        }
    }

    @ViewBuilder private var updateBanner: some View {
        switch state.update {
        case .none:
            EmptyView()
        case .checking:
            banner {
                ProgressView().controlSize(.small)
                Text("업데이트 확인 중…").font(.system(size: 11, weight: .medium))
                Spacer()
            }
        case .upToDate:
            banner {
                Image(systemName: "checkmark.circle.fill")
                Text("최신 버전이에요").font(.system(size: 11, weight: .medium))
                Spacer()
            }
        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("업데이트 확인 실패 · 네트워크를 확인하세요").font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.orange)
        case .downloading(let v):
            banner {
                ProgressView().controlSize(.small)
                Text("새 버전 v\(v) 다운로드 중…").font(.system(size: 11, weight: .medium))
                Spacer()
            }
        case .downloaded(_, let v):
            Button { state.installUpdate() } label: {
                banner {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("새 버전 v\(v) 준비됨 · 지금 설치").font(.system(size: 11, weight: .medium))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Sky-blue info banner (accent — an update is positive info, not an error).
    private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8, content: content)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Design.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(Design.accent)
            .contentShape(Rectangle())   // whole banner clickable when wrapped in a Button
    }
}
