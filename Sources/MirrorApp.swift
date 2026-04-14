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
    private var splashWindowController: SplashWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        showSplash()
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
            hideSplash()
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
                self?.hideSplash()
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
            scheduleSplashDismissal()
        } catch {
            hideSplash()
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

    private func showSplash() {
        let controller = SplashWindowController()
        splashWindowController = controller
        controller.showWindow(nil)
    }

    private func scheduleSplashDismissal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.hideSplash()
        }
    }

    private func hideSplash() {
        splashWindowController?.closeWithFade()
        splashWindowController = nil
    }
}

private final class SplashWindowController: NSWindowController {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Mirror")
    private let statusLabel = NSTextField(labelWithString: "Connecting to your phone")

    convenience init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 300))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.contentView = contentView
        window.hasShadow = true
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.transient, .ignoresCycle]

        self.init(window: window)
        configureWindow()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.alphaValue = 0
        window?.makeKeyAndOrderFront(sender)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window?.animator().alphaValue = 1
        }
        startAnimations()
    }

    func closeWithFade() {
        guard let window, window.isVisible else {
            close()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: {
            self.close()
        }
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        contentView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        contentView.layer?.borderWidth = 1

        let glowView = NSView()
        glowView.translatesAutoresizingMaskIntoConstraints = false
        glowView.wantsLayer = true
        glowView.layer?.cornerRadius = 70
        glowView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = splashIcon()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 27, weight: .semibold)
        titleLabel.textColor = .labelColor

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor

        contentView.addSubview(glowView)
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            glowView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            glowView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 44),
            glowView.widthAnchor.constraint(equalToConstant: 140),
            glowView.heightAnchor.constraint(equalToConstant: 140),

            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 58),
            iconView.widthAnchor.constraint(equalToConstant: 112),
            iconView.heightAnchor.constraint(equalToConstant: 112),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 22),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8)
        ])
    }

    private func startAnimations() {
        guard let iconLayer = iconView.layer else {
            return
        }

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.96
        pulse.toValue = 1.06
        pulse.duration = 0.85
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let float = CABasicAnimation(keyPath: "position.y")
        float.byValue = 8
        float.duration = 1.15
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        iconLayer.add(pulse, forKey: "mirrorIconPulse")
        iconLayer.add(float, forKey: "mirrorIconFloat")
    }

    private func splashIcon() -> NSImage {
        if let resourceURL = Bundle.main.url(forResource: "Mirror", withExtension: "png"),
           let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        return NSApp.applicationIconImage
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
