import Foundation

/// A human-facing remedy for a failed setup attempt: what to tell the user, and
/// which wizard step (1-based) to send them back to. `returnToStep == nil` means
/// there is no single step to blame (e.g. a transient server error).
public struct SetupRemedy: Equatable {
    public let message: String
    public let returnToStep: Int?
    public init(message: String, returnToStep: Int?) {
        self.message = message
        self.returnToStep = returnToStep
    }
}

/// Translates a raw `NotionError` into an actionable remedy. The point is to close
/// the loop: instead of dumping `http(404, "object_not_found", …)` on the user, we
/// name the likely cause and route them to the exact step that fixes it.
///
/// Step map (matches SetupWizardView): 2 = 토큰, 3 = 페이지 링크, 4 = 페이지↔통합 연결.
public enum SetupHint {
    public static func remedy(for error: NotionError) -> SetupRemedy {
        switch error {
        case let .http(status, code, message):
            // Bad/expired token → the app can't authenticate at all.
            if status == 401 || code == "unauthorized" {
                return SetupRemedy(
                    message: "토큰이 올바르지 않아요. 2단계에서 통합 토큰을 다시 복사해 붙여넣어 주세요.",
                    returnToStep: 2)
            }
            // The token works, but Notion can't see this page — the integration was
            // never connected to it. This is the single most common real failure.
            if code == "object_not_found" || code == "restricted_resource"
                || status == 404 || status == 403 {
                return SetupRemedy(
                    message: "노션이 이 페이지를 볼 수 없어요. 4단계에서 페이지를 통합과 연결했는지 "
                        + "확인해 주세요 (••• → 연결 → 만든 통합 추가).",
                    returnToStep: 4)
            }
            // Malformed request — usually a bad parent page link.
            if code == "validation_error" || status == 400 {
                return SetupRemedy(
                    message: "페이지 링크에 문제가 있어요. 3단계에서 부모 페이지 링크를 다시 확인해 주세요.",
                    returnToStep: 3)
            }
            let detail = message.isEmpty ? code : message
            return SetupRemedy(message: "연결에 실패했어요: \(detail)", returnToStep: nil)

        case let .shape(msg):
            // pageId(fromURL:) throws .shape("page id not found in url: …") for a bad
            // link — that's a step-3 (link) problem, not a transient server error.
            if msg.contains("url") || msg.contains("page id") {
                return SetupRemedy(
                    message: "페이지 링크에 문제가 있어요. 3단계에서 부모 페이지 링크를 다시 확인해 주세요.",
                    returnToStep: 3)
            }
            return SetupRemedy(
                message: "노션 응답을 해석하지 못했어요. 잠시 후 다시 시도해 주세요.",
                returnToStep: nil)
        }
    }
}
