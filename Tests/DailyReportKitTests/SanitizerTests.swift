// pii-allow-file: 살균기를 시험하려면 자격증명 형태의 문자열이 필요하다.
// 아래 값은 전부 합성이며 실제 계정과 무관하다.
import XCTest
@testable import DailyReportKit

final class SanitizerTests: XCTestCase {
    func test_prefixed_env_var_names_are_redacted() {
        // `\b` 앵커는 API_KEY= 는 잡고 OPENAI_API_KEY= 는 놓쳤다 — 접두 이름이 흔한 누출 형태.
        for text in ["OPENAI_API_KEY=sk-abcdefghijklmnop",
                     "DB_PASSWORD=Hunter2Hunter2",
                     "NOTION_SECRET_KEY=abcdefghijklmnop",
                     "MY_ACCESS_TOKEN=abcdefghijklmnop"] {
            let (clean, found) = Sanitizer.redact(text)
            XCTAssertFalse(found.isEmpty, "미탐지: \(text)")
            XCTAssertFalse(clean.contains("Hunter2Hunter2"))
            XCTAssertFalse(clean.contains("abcdefghijklmnop"))
        }
    }

    func test_colon_separator_does_not_leak_value_head() {
        // `PASSWORD: abc=def` 는 `=` 를 먼저 잘라 `abc` 를 남기던 버그가 있었다.
        let (clean, found) = Sanitizer.redact("PASSWORD: abc=defghijk")
        XCTAssertFalse(found.isEmpty)
        XCTAssertFalse(clean.contains("abc"))
    }

    func test_new_credential_shapes_are_covered() {
        let samples: [(String, String)] = [
            ("jwt", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3In0.abcdefghijklmno"),
            ("connection_string", "postgres://admin:Hunter2Pass@db.example.com:5432/app"),
            ("openai_project_key", "sk-proj-abcdefghijklmnopqrstuvwx"),
            ("huggingface_token", "hf_abcdefghijklmnopqrstuvwxyz"),
            ("gitlab_token", "glpat-abcdefghijklmnopqrst"),
            ("stripe_key", "sk_live_abcdefghijklmnopqrst"),
            ("ssh_key_body", "b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAA"),
            ("krn_rrn", "901231-1234567"),
            ("krn_phone", "010-1234-5678"),
            ("anthropic_key", "sk-ant-abcdefghijklmnop"),
            ("notion_token", "ntn_abcdefghijklmnopqrstuvwx"),
            ("github_token", "ghp_abcdefghijklmnopqrstuvwx"),
            ("bearer_token", "Bearer abcdefghijklmnopqrstuvwx"),
        ]
        for (kind, text) in samples {
            let (_, found) = Sanitizer.redact(text)
            XCTAssertNotNil(found[kind], "\(kind) 미탐지: \(text)")
        }
    }

    func test_ordinary_korean_prose_is_untouched() {
        let text = "오늘은 발표자료를 13장으로 재편했다. 비밀번호는 안전하게 관리해야 한다."
        let (clean, found) = Sanitizer.redact(text)
        XCTAssertEqual(clean, text, "정상 문장이 훼손됨: \(clean)")
        XCTAssertTrue(found.isEmpty)
    }

    func test_mask_keeps_the_name_but_not_the_value() {
        let masked = Sanitizer.mask("key_assignment", "OPENAI_API_KEY=sk-secretvalue")
        XCTAssertEqual(masked, "OPENAI_API_KEY=<REDACTED>")
    }

    func test_mask_generic_keeps_head_and_length() {
        let masked = Sanitizer.mask("notion_token", "ntn_abcdefghijklmnop")
        XCTAssertTrue(masked.hasPrefix("<REDACTED:notion_token:ntn_ab"))
        XCTAssertTrue(masked.contains("len20"))
    }

    // MARK: redactStructure + describe (P2-2)

    func test_dict_keys_are_redacted_too() {
        // 프로젝트 이름은 딕셔너리 키이고 Notion 속성이 된다.
        let payload: [String: Any] = ["ntn_abcdefghijklmnopqrstuvwx": ["note": "ok"]]
        let (clean, found) = Sanitizer.redactStructure(payload)
        XCTAssertNotNil(found["notion_token"])
        let dict = clean as! [String: Any]
        XCTAssertFalse(dict.keys.contains { $0.contains("ntn_abcdefghij") })
    }

    func test_nested_structure_is_sanitized() {
        let payload: [String: Any] = ["projects": ["p": ["outcomes":
            ["토큰은 ntn_abcdefghijklmnopqrstuvwx 이다"]]]]
        let (clean, found) = Sanitizer.redactStructure(payload)
        XCTAssertNotNil(found["notion_token"])
        let data = try! JSONSerialization.data(withJSONObject: clean)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("ntn_abcdefghij"))
    }

    func test_describe_summarizes_by_count_descending() {
        XCTAssertEqual(Sanitizer.describe([:]), "탐지 0건")
        let text = Sanitizer.describe(["notion_token": 1, "key_assignment": 3])
        XCTAssertEqual(text, "key_assignment 3건, notion_token 1건")
    }
}
