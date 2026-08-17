import Foundation

/// RefinedDay → the snake_case JSON object the summarizer prompt and the runner
/// both emit. Single source, matching `refine.py`'s output shape.
public enum DigestJSON {
    public static func object(_ r: RefinedDay) -> [String: Any] {
        func commit(_ k: GitCommit) -> [String: Any] {
            ["repo": k.repo, "project": k.project, "sha": k.sha, "at": k.at,
             "authored_at": k.authoredAt, "author": k.author, "subject": k.subject,
             "files": k.files, "insertions": k.insertions, "deletions": k.deletions, "paths": k.paths]
        }
        func project(_ p: RefinedProject) -> [String: Any] {
            ["label": p.label, "root": p.root as Any, "tools": p.tools,
             "session_count": p.sessionCount, "branches": p.branches, "titles": p.titles,
             "skills_used": p.skillsUsed, "prompts": p.prompts,
             "files_written": p.filesWritten, "files_edited": p.filesEdited,
             "files_tracked": p.filesTracked, "files_on_disk": p.filesOnDisk,
             "bash_commands": p.bashCommands, "todos": p.todos, "plans": p.plans,
             "outcomes": p.outcomes, "commits": p.commits.map(commit),
             "active_from": p.activeFrom as Any, "active_to": p.activeTo as Any]
        }
        return ["date": r.date, "window": ["start": r.windowStart, "end": r.windowEnd],
                "projects": r.projects.map(project),
                "stats": ["projects": r.stats.projects, "sessions": r.stats.sessions,
                          "files": r.stats.files, "commits": r.stats.commits,
                          "noise_commands_dropped": r.stats.noiseCommandsDropped,
                          "cwds_dropped": r.stats.cwdsDropped],
                "dropped_cwds": r.droppedCwds]
    }
}
