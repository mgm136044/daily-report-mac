import SwiftUI
import DailyReportKit

/// First-run install wizard: Notion token + parent page → Keychain + find/create DB.
/// Plus summary-engine choice and a reliable "run daily at HH:MM" toggle.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var token = ""
    @State private var parentURL = ""
    @State private var status = ""
    @State private var scheduled = false
    @State private var scheduleTime = Date()
    @State private var engine = "claude"
    @State private var applyTask: Task<Void, Never>?
    @State private var showWizard = false
    @State private var autoWizardTried = false
    @State private var showCoffeeQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("설정").font(.system(size: 15, weight: .semibold, design: .rounded))

            HStack(spacing: 6) {
                Text("Notion 연결").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if state.isConnected {
                    Label("연결됨", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Notion 토큰").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                SecureField(state.hasToken ? "저장됨 · 변경하려면 입력" : "ntn_…", text: $token)
                Text("부모 페이지 링크").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextField("https://notion.so/…", text: $parentURL)
            }
            .textFieldStyle(.roundedBorder)
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button(state.isConnected ? "다시 연결 확인" : "저장하고 데이터베이스 연결") {
                    state.saveSetup(token: token, parentURL: parentURL) { status = $0 }
                }
                .disabled(parentURL.isEmpty || (token.isEmpty && !state.hasToken))
                Spacer()
                Button("연결 안내 보기") { showWizard = true }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Design.accent)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("요약 엔진").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Picker("요약 엔진", selection: $engine) {
                    Text("Claude").tag("claude")
                    Text("Codex").tag("codex")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: engine) { _, e in state.setEngine(e) }
            }

            Toggle("매일 자동 실행", isOn: $scheduled)
                .onChange(of: scheduled) { _, _ in scheduleChanged() }
                // Reflect the real launchd state if it changes underneath us (launch-time
                // refresh, external change) — the debounced apply also reconciles.
                .onChange(of: state.isScheduled) { _, actual in
                    if scheduled != actual { scheduled = actual }
                }
            DatePicker("실행 시각", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                .disabled(!scheduled)
                .onChange(of: scheduleTime) { _, _ in scheduleChanged() }

            if !status.isEmpty {
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button { showCoffeeQR.toggle() } label: {
                    Label("개발자에게 커피 한잔", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(Design.accent)
                .contentShape(Rectangle())
                .popover(isPresented: $showCoffeeQR, arrowEdge: .bottom) { coffeePopover }
                Spacer()
                Text("DailyReport v\(AppVersion.current)")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(18).frame(width: 360)
        .onAppear {
            scheduled = state.isScheduled
            engine = state.engine
            parentURL = state.config.notion.parentPageURL ?? ""   // restore so it doesn't look reset
            if state.isConnected && status.isEmpty { status = "✓ 연결됨 — 저장된 설정 사용 중" }
            var c = DateComponents(); c.hour = state.scheduleHour; c.minute = state.scheduleMinute
            scheduleTime = Calendar.current.date(from: c) ?? Date()
            // An explicit CTA request (from the popover banner) always wins; otherwise
            // auto-open once on first run when not yet connected, so the user isn't
            // dropped onto raw token/URL fields with no explanation.
            if state.pendingWizard {
                state.pendingWizard = false
                showWizard = true
            } else if !state.isConnected && !autoWizardTried {
                autoWizardTried = true
                showWizard = true
            }
        }
        .onChange(of: state.pendingWizard) { _, want in
            // Handles the case where the Settings window already exists (onAppear won't
            // fire again) — the CTA still re-presents the wizard.
            if want { state.pendingWizard = false; showWizard = true }
        }
        .sheet(isPresented: $showWizard) {
            SetupWizardView().environmentObject(state)
        }
    }

    /// KakaoPay 송금 QR 팝오버 — 스캔 안내와 함께. QR은 URL에서 런타임 생성(스크린샷 아님).
    private var coffeePopover: some View {
        VStack(spacing: 10) {
            Text("커피 한 잔의 응원, 고마워요 ☕")
                .font(.system(size: 13, weight: .semibold))
            if let qr = CoffeeQR.image(side: 190) {
                Image(nsImage: qr)
                    .interpolation(.none).resizable()
                    .frame(width: 190, height: 190)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
            Text("휴대폰 카메라나 카카오페이 앱으로\nQR 코드를 스캔해 주세요.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("스캔하면 카카오페이 송금 화면으로 이어져요.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(16).frame(width: 230)
    }

    /// Both the toggle and the time picker funnel through here. Debounced with
    /// cancel-on-change so rapid toggling / scrubbing collapses to a SINGLE apply of the
    /// LATEST state (fixes "the opposite of my last click got saved"). The apply is
    /// awaited off-main; afterward the toggle is reconciled to the REAL launchd state
    /// (so a failed install flips it back to the truth). `changeNeeded` inside
    /// `setSchedule` makes the `onAppear` seed a no-op.
    private func scheduleChanged() {
        applyTask?.cancel()
        applyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
            await state.setSchedule(on: scheduled, hour: c.hour ?? 4, minute: c.minute ?? 5)
            guard !Task.isCancelled else { return }
            if scheduled != state.isScheduled { scheduled = state.isScheduled }   // reconcile to truth
        }
    }
}
