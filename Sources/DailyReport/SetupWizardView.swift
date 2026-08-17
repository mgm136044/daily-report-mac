import SwiftUI
import AppKit
import DailyReportKit

/// First-run onboarding wizard: walks the user through the pre-setup the plain
/// Settings fields never explained — create a Notion integration, copy the token,
/// pick a page, SHARE the page with the integration (the step everyone forgets),
/// then connect. Presented as a sheet; reachable any time from Settings.
///
/// The layout mirrors the agreed insane-design mockup (5 steps, hand-drawn mini
/// diagrams, sky-blue accent = Design.accent). Step 5 turns a failure into a remedy
/// that routes the user back to the exact step that fixes it.
struct SetupWizardView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    private static let lastStep = 5

    @State private var step = 1
    @State private var token = ""
    @State private var parentURL = ""
    @State private var connecting = false
    @State private var doneMessage: String?     // success text (step 5)
    @State private var remedy: SetupRemedy?      // failure remedy (step 5)

    /// When set (first-launch onboarding window), close/완료 call this instead of the
    /// SwiftUI `dismiss` (which only closes a sheet, not a standalone NSWindow).
    private let onFinish: (() -> Void)?

    /// Default runtime init + preview seams so `Preview.renderWizard` can render any
    /// step (and step 5's success/failure states) without a live connect.
    init(initialStep: Int = 1, onFinish: (() -> Void)? = nil,
         previewToken: String = "", previewURL: String = "",
         previewDone: String? = nil, previewRemedy: SetupRemedy? = nil) {
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
        _token = State(initialValue: previewToken)
        _parentURL = State(initialValue: previewURL)
        _doneMessage = State(initialValue: previewDone)
        _remedy = State(initialValue: previewRemedy)
    }

    /// Close the wizard — via the onboarding-window callback if present, else dismiss the sheet.
    private func finish() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar
            stepBody
            Spacer(minLength: 4)
            navBar
        }
        .padding(22)
        .frame(width: 380)
        .frame(minHeight: 460, alignment: .top)
        .onAppear {
            // Seed only when empty so re-appearing doesn't clobber what the user typed.
            if parentURL.isEmpty { parentURL = state.config.notion.parentPageURL ?? "" }
        }
    }

    // MARK: - Chrome

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(1...Self.lastStep, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Design.accent : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            Text("\(step) / \(Self.lastStep)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .monospacedDigit()
            Button { finish() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
    }

    @ViewBuilder private var navBar: some View {
        HStack {
            if step > 1 && doneMessage == nil {
                Button("← 이전") { step -= 1; clearResult() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer()
            navPrimary
        }
        .font(.system(size: 12.5))
    }

    @ViewBuilder private var navPrimary: some View {
        switch step {
        case 1:
            Button("시작하기") { step = 2 }
                .buttonStyle(.borderedProminent).tint(Design.accent)
        case 2, 3, 4:
            Button("다음 →") { step += 1; clearResult() }
                .buttonStyle(.plain).foregroundStyle(Design.accent)
                .fontWeight(.semibold)
                .disabled(!canAdvance)
        default:    // step 5
            if doneMessage != nil {
                Button("완료") { finish() }
                    .buttonStyle(.borderedProminent).tint(.green)
            }
        }
    }

    /// Soft gate: can't leave a data step with obviously-wrong input, but hints (not
    /// hard errors) do the teaching. Token step also passes if one is already saved.
    private var canAdvance: Bool {
        switch step {
        case 2: return SetupValidation.looksLikeToken(token) || state.hasToken
        case 3: return SetupValidation.looksLikeNotionURL(parentURL)
        default: return true
        }
    }

    // MARK: - Steps

    @ViewBuilder private var stepBody: some View {
        switch step {
        case 1: stepWelcome
        case 2: stepIntegration
        case 3: stepPageLink
        case 4: stepConnectPage
        default: stepConfirm
        }
    }

    private var stepWelcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            diagram {
                node("🗒️", "DailyReport", strong: true)
                arrow(nil)
                node("📚", "Notion")
            }
            title("노션에 매일 보고서를 쌓아요")
            lede("한 번만 연결하면, 매일 정해진 시각에 하루 정리가 **자동으로** 노션에 기록됩니다. 준비물은 딱 두 가지예요.")
            VStack(alignment: .leading, spacing: 8) {
                bullet("A", "노션 통합 토큰", "앱이 노션에 글을 쓸 수 있는 열쇠")
                bullet("B", "부모 페이지 링크", "보고서가 쌓일 노션 페이지 주소")
            }
            lede("3분이면 끝나요. 순서대로 따라오시면 됩니다.")
        }
    }

    private var stepIntegration: some View {
        VStack(alignment: .leading, spacing: 12) {
            diagram {
                node("📚", "Notion")
                arrow("새 통합")
                node("＋", "통합 생성")
                arrow("발급")
                node("🔑", "ntn_…", strong: true)
            }
            title("통합을 만들고 토큰 복사")
            lede("아래 버튼으로 노션 통합 페이지를 열고 **새 통합**을 만든 뒤, 발급된 토큰(`ntn_`로 시작)을 복사해 붙여넣으세요.")
            openButton("통합 페이지 열기", "https://www.notion.so/my-integrations")
            VStack(alignment: .leading, spacing: 5) {
                fieldLabel("Notion 토큰")
                SecureField(state.hasToken ? "저장됨 · 변경하려면 입력" : "ntn_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                tokenHint
            }
        }
    }

    private var stepPageLink: some View {
        VStack(alignment: .leading, spacing: 12) {
            diagram {
                node("📄", "노션 페이지")
                arrow("주소 복사")
                node("🔗", "페이지 링크", strong: true)
            }
            title("보고서가 쌓일 페이지 링크")
            lede("보고서를 모아둘 노션 페이지를 하나 고르세요(새로 만들어도 됩니다). 그 페이지의 **주소를 복사**해 붙여넣으면 돼요.")
            openButton("노션 열기", "https://www.notion.so")
            VStack(alignment: .leading, spacing: 5) {
                fieldLabel("부모 페이지 링크")
                TextField("https://notion.so/…", text: $parentURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                urlHint
            }
        }
    }

    private var stepConnectPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("⚠ 가장 자주 빠뜨리는 단계")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Design.accent)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Design.accent.opacity(0.14), in: Capsule())
            diagram {
                node("•••", "페이지 우측 상단")
                arrow(nil)
                menuMock
            }
            title("페이지를 통합과 연결")
            lede("노션은 **연결한 페이지만** 통합에게 보여줍니다. 방금 만든 통합을 이 페이지에 붙여줘야 앱이 글을 쓸 수 있어요.")
            lede("페이지 우측 상단 **•••** → **연결** → 방금 만든 통합(예: **DailyReport**) 추가.")
            openButton("이 페이지 열기",
                       SetupValidation.looksLikeNotionURL(parentURL) ? parentURL : "https://www.notion.so")
        }
        .padding(.top, 2)
    }

    private var stepConfirm: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("연결 확인")
            lede("아래 버튼을 누르면 앱이 실제로 노션에 연결을 시도하고, 데이터베이스를 찾거나 만들어 둡니다.")
            Button { connect() } label: {
                HStack(spacing: 6) {
                    if connecting { ProgressView().controlSize(.small) }
                    Text(connecting ? "연결 중…" : "연결하기")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Design.accent)
            .disabled(connecting)

            if let m = doneMessage { successBox(m) }
            if let r = remedy { remedyBox(r) }
        }
    }

    // MARK: - Step-5 result boxes

    private func successBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("연결 완료!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.green)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.35)))
    }

    private func remedyBox(_ r: SetupRemedy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("연결하지 못했어요", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.orange)
            Text(r.message).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let back = r.returnToStep {
                Button("← \(back)단계로 돌아가 고치기") { step = back; clearResult() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.orange.opacity(0.38)))
    }

    // MARK: - Actions

    private func connect() {
        connecting = true; doneMessage = nil; remedy = nil
        Task { @MainActor in
            switch await state.performSetup(token: token, parentURL: parentURL) {
            case .success(let m): doneMessage = m
            case .notion(let e):  remedy = SetupHint.remedy(for: e)
            case .other(let m):   remedy = SetupRemedy(message: m, returnToStep: nil)
            }
            connecting = false
        }
    }

    private func clearResult() { doneMessage = nil; remedy = nil }

    /// Open in the default WEB BROWSER, not whatever claims the link. The Notion desktop
    /// app grabs notion.so https links (universal links) and then shows "페이지 찾지 못함"
    /// for web-only pages like the integrations/settings dashboard. Targeting the browser
    /// explicitly (via the handler for a neutral https URL) bypasses that.
    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        if let neutral = URL(string: "https://example.com"),
           let browser = NSWorkspace.shared.urlForApplication(toOpen: neutral) {
            NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: cfg)
        } else {
            NSWorkspace.shared.open(url)   // fallback: default handler
        }
    }

    // MARK: - Small building blocks

    private func title(_ t: String) -> some View {
        Text(t).font(.system(size: 16, weight: .semibold, design: .rounded))
    }

    private func lede(_ md: String) -> some View {
        Text(.init(md)).font(.system(size: 12.5)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var tokenHint: some View {
        if !token.isEmpty {
            if SetupValidation.looksLikeToken(token) {
                hint("✓ 올바른 토큰 형식이에요", .green)
            } else {
                hint("ntn_(또는 이전 secret_)로 시작하는 토큰이어야 해요", .secondary)
            }
        }
    }

    @ViewBuilder private var urlHint: some View {
        if !parentURL.isEmpty {
            if SetupValidation.looksLikeNotionURL(parentURL) {
                hint("✓ 노션 페이지 주소가 맞아요", .green)
            } else {
                hint("노션 페이지 주소를 붙여넣어 주세요", .secondary)
            }
        }
    }

    private func hint(_ t: String, _ color: Color) -> some View {
        Text(t).font(.system(size: 10.5)).foregroundStyle(color)
    }

    private func bullet(_ tag: String, _ head: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(tag)
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Design.accent)
                .frame(width: 20, height: 20)
                .background(Design.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(head).font(.system(size: 12, weight: .semibold))
                Text(sub).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
    }

    private func openButton(_ label: String, _ url: String) -> some View {
        Button { open(url) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                Text(label)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .contentShape(Rectangle())   // whole box is clickable, not just the text
        }
        .buttonStyle(.plain)
        .foregroundStyle(Design.accent)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Design.accent))
    }

    // MARK: - Diagram

    private func diagram<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .frame(maxWidth: .infinity, minHeight: 84)
            .padding(.vertical, 14).padding(.horizontal, 10)
            .background(Design.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.quaternary))
    }

    private func node(_ glyph: String, _ label: String, strong: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(glyph).font(.system(size: 18))
            Text(label).font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(strong ? Design.accent : .secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 9).padding(.horizontal, 10)
        .frame(minWidth: 62)
        .background((strong ? Design.accent.opacity(0.10) : Color.primary.opacity(0.04)),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(strong ? Design.accent : .clear, lineWidth: strong ? 1 : 0))
    }

    private func arrow(_ caption: String?) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(.tertiary)
            if let caption { Text(caption).font(.system(size: 8.5)).foregroundStyle(.tertiary) }
        }
    }

    /// A stylized Notion "•••" menu — concept, not a screenshot, so it doesn't rot
    /// when Notion changes its UI.
    private var menuMock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("복제").font(.system(size: 10)).foregroundStyle(.tertiary)
            HStack {
                Text("연결").font(.system(size: 10, weight: .semibold))
                Spacer(); Text("▸").font(.system(size: 9))
            }
            .foregroundStyle(Design.accent)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Design.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            Text("＋ DailyReport 추가")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(Design.accent)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(Design.accent))
        }
        .padding(6)
        .frame(width: 118)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }
}
