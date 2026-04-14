import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct Release: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/heisenbergg-labs/Mirror/releases/latest")!
    private let downloadURL = URL(string: "https://github.com/heisenbergg-labs/Mirror/releases/latest/download/Mirror.dmg")!
    private let releasesURL = URL(string: "https://github.com/heisenbergg-labs/Mirror/releases/latest")!
    private var task: Process?
    private var outputData = Data()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        checkForUpdates(silent: true)
        runMirror()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let task, task.isRunning {
            task.terminate()
        }
    }

    @objc private func checkForUpdatesFromMenu() {
        checkForUpdates(silent: false)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            NSMenuItem(
                title: "Check for Updates...",
                action: #selector(checkForUpdatesFromMenu),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "Quit Mirror",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func runMirror() {
        guard let runtimeURL = Bundle.main.resourceURL?.appendingPathComponent("mirror-runtime.sh") else {
            showAlert("Mirror could not find its launcher.")
            NSApp.terminate(nil)
            return
        }

        let pipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [runtimeURL.path]
        task.standardOutput = pipe
        task.standardError = pipe
        self.task = task

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                self?.outputData.append(data)
            }
        }

        task.terminationHandler = { [weak self] task in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                guard task.terminationStatus != 0 else {
                    NSApp.terminate(nil)
                    return
                }

                let output = self?.messageFromOutput() ?? "Mirror could not open your phone."
                self?.showAlert(output)
                NSApp.terminate(nil)
            }
        }

        do {
            try task.run()
        } catch {
            showAlert("Mirror could not start.\n\n\(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    private func messageFromOutput() -> String {
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output.isEmpty ? "Mirror could not open your phone." : output
    }

    private func checkForUpdates(silent: Bool) {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleUpdateResponse(data: data, response: response, error: error, silent: silent)
            }
        }.resume()
    }

    private func handleUpdateResponse(data: Data?, response: URLResponse?, error: Error?, silent: Bool) {
        if let error {
            if !silent {
                showUpdateFallback("Mirror could not check for updates.\n\n\(error.localizedDescription)")
            }
            return
        }

        guard let httpResponse = response as? HTTPURLResponse, let data else {
            if !silent {
                showUpdateFallback("Mirror could not check for updates.")
            }
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if !silent {
                showUpdateFallback("Mirror could not read the latest private GitHub release.")
            }
            return
        }

        do {
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latestVersion = normalizedVersion(release.tagName)
            let currentVersion = normalizedVersion(
                Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            )

            if compareVersions(latestVersion, currentVersion) == .orderedDescending {
                showUpdateAvailable(version: release.tagName)
            } else if !silent {
                showAlert("Mirror is up to date.")
            }
        } catch {
            if !silent {
                showUpdateFallback("Mirror could not read the latest release details.")
            }
        }
    }

    private func showUpdateAvailable(version: String) {
        let alert = NSAlert()
        alert.messageText = "Mirror Update Available"
        alert.informativeText = "\(version) is ready to download."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private func showUpdateFallback(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Mirror Updates"
        alert.informativeText = "\(message)\n\nYou can still open the latest Mirror release in your browser."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releasesURL)
        }
    }

    private func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(leftParts.count, rightParts.count)

        for index in 0..<count {
            let left = index < leftParts.count ? leftParts[index] : 0
            let right = index < rightParts.count ? rightParts[index] : 0

            if left < right {
                return .orderedAscending
            }

            if left > right {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Mirror"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
