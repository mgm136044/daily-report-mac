import Foundation

/// The summarizer prompt templates (documents, not code) and the field
/// substitution that turns one into a request. A faithful port of
/// `summarize.py:build_prompt` + the `prompts/*.md` documents. Templates are
/// embedded verbatim (flush-left, so Swift strips no indentation).
public enum Prompts {
    public static let weekdayNames: [String: [String]] = [
        "ko": ["월", "화", "수", "목", "금", "토", "일"],
        "en": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    ]

    static let koTemplate = #"""
아래 JSON은 {date_str}({weekday}) 하루 동안의 작업 로그를 프로젝트별로 정리한 것이다.
Claude Code 와 Codex CLI 두 도구의 기록을 프로젝트 단위로 합쳐 놓았다.

각 프로젝트의 필드:
- `tools`: 그 프로젝트에서 쓴 도구 (Claude Code / Codex)
- `prompts`: 사용자가 지시한 내용
- `files_written` / `files_edited` / `files_tracked`: 도구가 직접 만든 · 고친 · 지운 파일
- `files_on_disk`: 같은 시간대에 **디스크에서 바뀐 것이 관찰된** 파일. 도구 기록에는 없다.
  스크립트가 만들어낸 산출물인 경우가 많다(예: 렌더러가 뽑은 이미지, 일괄 생성된 문서).
  **이것도 그날의 산출물이므로 반드시 보고서에 반영한다.** 빠뜨리면 하루가 실제보다
  훨씬 작아 보인다. 개수를 쓸 때는 이 배열에서 **실제로 센 값만** 쓰고, 무엇을 세었는지
  (확장자·상위 폴더)를 함께 밝힌다. 셈이 애매하면 개수를 생략하고 대표 경로만 적는다.
- `bash_commands`: 실행한 명령
- `plans`: Codex 가 세운 작업 계획 단계
- `outcomes`: Codex 턴이 끝날 때 남긴 결과 요약. **Codex 세션에서만 채워진다.**
- `commits`: 그날의 git 커밋
- `skills_used`, `titles`, `branches`
- `active_from` / `active_to`: 그 프로젝트의 작업 시작·종료 시각. **이미 한국시간이다.**
  추가 환산을 하지 말고 그대로 읽는다.

이걸 사람이 읽는 '하루 마감 보고서' 마크다운으로 정리하라.

# {date_str} 하루 마감 보고서

## 오늘의 요약
3~5문장. 무엇에 시간을 썼는지, 어떤 흐름이었는지.

전체 분량은 **{target_chars}자 안팎**을 목표로 한다. 프로젝트가 많으면 활동이 적은 쪽을
한두 줄로 줄여서 맞추되, 활동이 큰 프로젝트의 내용을 깎지는 않는다.

## 프로젝트별 작업
프로젝트마다 아래 형식으로. 활동이 미미한 프로젝트는 한 줄로 줄여도 된다.

### {{프로젝트명}}
- **한 일**: 구체적으로. 무엇을 왜 했는지가 드러나게.
- **만든/고친 파일**: 경로. 많으면 개수를 밝히고 대표적인 것만 적는다.
  (`files_on_disk` 로 관찰된 산출물도 여기 포함한다)
- **다음 할 일**: 로그에서 드러난 미완 작업. 없으면 생략.

## 세운 계획
프롬프트에서 드러난 방침·결정·의도. 없으면 이 절을 생략한다.

규칙:
- 한국어로 쓴다.
- 로그에 없는 내용을 지어내지 않는다. 확실하지 않으면 쓰지 않는다.
- 플러그인 설치, 캐시 정리 같은 단순 유지보수는 제외한다. 제외한 항목을 굳이 한 줄로
  언급할 때도, `bash_commands`·`commits` 에 실행 기록이 없으면 **"지시가 있었다"까지만**
  쓰고 "했다"로 단정하지 않는다.
- 파일 경로는 홈 디렉터리를 `~`로 줄여 쓴다. **경로를 줄이거나 바꾸지 않는다** —
  중간 폴더를 생략하면 나중에 그 경로로 찾아갈 수 없다.
- **어떤 도구로 했는지는 그 자체로 중요하지 않다.** 같은 프로젝트를 Claude Code 와
  Codex 로 나눠 작업했어도 하나의 작업 흐름으로 서술한다. 다만 두 도구가 서로 다른
  일을 했다면(예: 한쪽은 설계, 한쪽은 구현) 그 구분은 드러내라.
  단, **도구 귀속의 근거는 Codex 전용 필드인 `plans`·`outcomes` 와 `skills_used` 뿐이다.**
  `files_written`/`files_edited`/`files_tracked` 에는 도구 표시가 없으므로,
  파일 목록만 보고 "어느 도구가 했다"고 쓰지 않는다.
- **`…[truncated]` 가 보이면 거기서 멈춘다.** 그 뒤를 배경지식으로 완성하지 않는다.
  실제로 있었던 실패: 로그에 `**1. GM Safe …[truncated]` 라고만 있었는데 보고서가
  "GM Safety Alert Seat 등" 이라고 적었다. 세상에 그런 제품이 있어 우연히 맞았을 뿐,
  **로그에서 나온 값이 아니다.** 이런 경우엔 고유명사를 쓰지 말고
  "선행기술 사례를 조사했다" 처럼 잘리지 않은 부분까지만 쓴다.
- **산출물의 제작 방식을 쓰지 않는다.** "crane 빌드로 뽑은", "스크립트로 렌더링한" 같은
  표현은 모두 금지한다. `bash_commands` 에 그 파일을 만든 명령이 실제로 있을 때만
  방식을 쓸 수 있고, 그때는 근거가 된 명령을 함께 밝힌다.
- **프로젝트 이름은 작업 디렉터리에서 유도한 것이라 실제 산출물 위치와 다를 수 있다.**
  파일 경로가 다른 프로젝트의 `root` 아래에 있으면 이름이 아니라 **경로를 기준으로 묶고**,
  묶었다는 사실을 제목이나 첫 문장에 밝힌다.
- `plans` 는 Codex 가 진행 중에 갱신한 계획이라 완료된 것과 미완인 것이 섞여 있다.
  `outcomes` 와 대조해 실제로 끝난 것과 남은 것을 구분하라.
- **로그에 있는 것만 쓴다.** 파일이 수정된 기록이 있다고 해서 "완료했다"고 쓰지 않는다.
  완료·검증·승인 같은 판정은 그렇게 적힌 기록(`outcomes`, 프롬프트, 커밋 메시지)이
  있을 때만 쓴다. 근거가 없으면 "작업했다" 수준으로 남긴다.
- **"다음 할 일" 은 근거가 있을 때만 적는다.** 미완으로 남은 계획 단계, 실패한 명령,
  사용자가 다음으로 하겠다고 말한 것 등이 근거다. 없으면 그 항목을 생략한다.
- 보고서 본문만 출력한다. 인사말이나 "정리했습니다" 같은 머리말을 붙이지 않는다.

--- 작업 로그 ---
{digest}
"""#

    static let enTemplate = #"""
The JSON below is one day's work log for {date_str} ({weekday}), grouped by project.
Records from Claude Code and Codex CLI have been merged per project.

Fields on each project:
- `tools`: which tools were used there (Claude Code / Codex)
- `prompts`: what the person asked for
- `files_written` / `files_edited` / `files_tracked`: files a tool created, changed, or removed
- `files_on_disk`: files **observed to have changed on disk** in the same window, with no
  tool record. Often output produced by a script (rendered images, batch-generated
  documents). **These are part of the day's output and must appear in the report** —
  leaving them out makes the day look far smaller than it was. When giving a count, use
  a number you actually counted from this array, and say what you counted (extension,
  parent folder). If the count is ambiguous, omit it and name representative paths.
- `bash_commands`: commands that ran
- `plans`: plan steps Codex recorded
- `outcomes`: summaries Codex left at the end of a turn. **Only present for Codex sessions.**
- `commits`: that day's git commits
- `skills_used`, `titles`, `branches`
- `active_from` / `active_to`: when work on that project started and ended.
  **Already in local time.** Do not convert; read them as they are.

Turn this into a human-readable end-of-day report in markdown.

# {date_str} Daily Report

## Summary
Three to five sentences: where the time went and how the day flowed.

Aim for about {target_chars} characters overall. If there are many projects, compress the
quiet ones to a line or two rather than cutting detail from the busy ones.

## Work by project
For each project, in this shape. A project with little activity can be a single line.

### {{project}}
- **What happened**: specifically, so that what was done and why is visible.
- **Files created/changed**: paths. If there are many, give the count and name
  representative ones. (Include output observed in `files_on_disk` here.)
- **Next**: unfinished work the log actually shows. Omit if there is none.

## Decisions and plans
Direction, decisions, and intent visible in the prompts. Omit this section if there is none.

Rules:
- Write in English.
- Do not invent anything absent from the log. When unsure, leave it out.
- Skip routine maintenance such as plugin installs and cache clearing. Even when
  mentioning something skipped in one line, if there is no record in `bash_commands`
  or `commits`, say **only that it was requested** — never that it was done.
- Shorten the home directory to `~` in paths. **Do not otherwise abbreviate or alter a
  path** — dropping an intermediate folder makes it impossible to find later.
- **Which tool did the work is not interesting in itself.** Describe one flow even when a
  project was worked on through both Claude Code and Codex. Do surface the split when the
  two did genuinely different things (one designing, the other implementing).
  But **the only evidence for tool attribution is the Codex-only fields `plans`,
  `outcomes`, and `skills_used`.** `files_written` / `files_edited` / `files_tracked`
  carry no tool marker, so never infer "tool X did this" from a file list.
- **Stop at `…[truncated]`.** Do not complete what follows from background knowledge.
  This has actually gone wrong: a log held only `**1. GM Safe …[truncated]` and the report
  wrote "GM Safety Alert Seat". Such a product happens to exist, so it was accidentally
  right — but **it did not come from the log.** In that situation drop the proper noun and
  write only as far as the untruncated text goes.
- **Never state how an artifact was produced.** Phrases like "rendered by the build" or
  "generated by the script" are forbidden. Method may be described only when
  `bash_commands` actually contains the command that made the file, and then the
  supporting command must be named.
- **A project name is derived from a working directory and may differ from where the
  output actually lives.** When a file path sits under another project's `root`, group by
  **path, not by name**, and say in the heading or first sentence that you did so.
- `plans` are Codex's in-progress updates, so finished and unfinished steps are mixed.
  Cross-check against `outcomes` to tell them apart.
- **Write only what the log contains.** A record that a file was modified is not a record
  that the work is finished. Verdicts such as done, verified, or approved may be used only
  when something says so (`outcomes`, a prompt, a commit message). Without that, say the
  work was carried out and nothing more.
- **"Next" only with evidence.** Plan steps left unfinished, commands that failed, or the
  person saying what comes next. Otherwise omit the item.
- Output the report body only. No greeting, no "here is the summary" preamble.

--- work log ---
{digest}
"""#

    public static func template(language: String) -> String {
        language == "en" ? enTemplate : koTemplate
    }

    /// Reproduce Python `str.format`: substitute the four named fields and unescape
    /// `{{`/`}}`, in a single pass so the digest JSON's own braces are inert.
    public static func build(digestJSON: String, date: String, weekday: String,
                             targetChars: Int, language: String) -> String {
        var s = template(language: language)
        // 1) fields → sentinels (before touching braces)
        s = s.replacingOccurrences(of: "{date_str}", with: "\u{1}DATE\u{1}")
        s = s.replacingOccurrences(of: "{weekday}", with: "\u{1}WD\u{1}")
        s = s.replacingOccurrences(of: "{target_chars}", with: "\u{1}TC\u{1}")
        s = s.replacingOccurrences(of: "{digest}", with: "\u{1}DG\u{1}")
        // 2) unescape literal braces
        s = s.replacingOccurrences(of: "{{", with: "{").replacingOccurrences(of: "}}", with: "}")
        // 3) sentinels → values (digest last; its braces are never re-scanned)
        s = s.replacingOccurrences(of: "\u{1}DATE\u{1}", with: date)
        s = s.replacingOccurrences(of: "\u{1}WD\u{1}", with: weekday)
        s = s.replacingOccurrences(of: "\u{1}TC\u{1}", with: String(targetChars))
        s = s.replacingOccurrences(of: "\u{1}DG\u{1}", with: digestJSON)
        return s
    }
}
