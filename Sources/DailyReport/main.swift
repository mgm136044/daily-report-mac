import DailyReportKit

// `--render <path>` renders the status view to a PNG (for design review) and
// exits; otherwise the normal menu bar app runs.
let arguments = CommandLine.arguments
if let i = arguments.firstIndex(of: "--render"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Preview.render(to: arguments[i + 1]) }
} else if let i = arguments.firstIndex(of: "--render-wizard"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Preview.renderWizard(to: arguments[i + 1]) }
} else if let i = arguments.firstIndex(of: "--render-progress"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Preview.renderProgress(to: arguments[i + 1]) }
} else {
    DailyReportApp.main()
}
