import AppKit

@MainActor enum InstallerSmoke {
    private static var started = false
    static func runIfRequested() {
        guard !started, CommandLine.arguments.contains("--install-smoke") else { return }
        started = true
        Task { @MainActor in
            let installation = Installation()
            installation.install()
            let deadline = ProcessInfo.processInfo.systemUptime + 120
            while installation.busy, ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !installation.busy, installation.installed else {
                fputs("Actual installer failed: \(installation.message)\n", stderr)
                exit(1)
            }
            print("Actual installer copied, verified and registered the input method.")
            print(installation.message)
            exit(0)
        }
    }
}
