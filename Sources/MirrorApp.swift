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
    private var navigationWindowController: NavigationWindowController?
    private var statusItem: NSStatusItem?
    private var alwaysOnTopMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        configureStatusItem()
        showSplash()
        checkForUpdates(silent: true)
        runMirror()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "MirrorScreen.app/Contents/MacOS/MirrorScreen"]
        try? pkill.run()
        pkill.waitUntilExit()

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

    @objc private func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        let url = alwaysOnTopFlagURL()
        let manager = FileManager.default
        let currentlyOn = manager.fileExists(atPath: url.path)

        if currentlyOn {
            try? manager.removeItem(at: url)
            sender.state = .off
        } else {
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data().write(to: url)
            sender.state = .on
        }

        showAlert("Keep on Top is \(currentlyOn ? "off" : "on").\n\nThe change takes effect the next time you open Mirror.")
    }

    private func alwaysOnTopFlagURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Mirror/always-on-top")
    }

    private func configureMenu() {
        // Kept as an NSApp.mainMenu fallback for non-accessory launches; the
        // status item in the menu bar is the real access point.
        NSApp.mainMenu = buildMenu()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            if let image = statusItemImage() {
                button.image = image
                button.image?.isTemplate = true
            } else {
                button.title = "Mirror"
            }
            button.toolTip = "Mirror"
        }

        item.menu = buildMenu()
        statusItem = item
    }

    private func statusItemImage() -> NSImage? {
        let symbolNames = ["iphone.gen3", "iphone", "rectangle.on.rectangle"]
        for name in symbolNames {
            if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Mirror") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                return symbol.withSymbolConfiguration(config)
            }
        }
        return nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let alwaysOnTopItem = NSMenuItem(
            title: "Keep on Top",
            action: #selector(toggleAlwaysOnTop(_:)),
            keyEquivalent: ""
        )
        alwaysOnTopItem.state = FileManager.default.fileExists(atPath: alwaysOnTopFlagURL().path) ? .on : .off
        alwaysOnTopItem.target = self
        menu.addItem(alwaysOnTopItem)
        alwaysOnTopMenuItem = alwaysOnTopItem

        menu.addItem(NSMenuItem.separator())

        let updates = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesFromMenu),
            keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Mirror",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
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
                self?.hideNavigationPanel()
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
            scheduleNavigationPanel()
        } catch {
            hideSplash()
            showAlert("Mirror could not start.\n\n\(error.localizedDescription)")
            NSApp.terminate(nil)
        }
    }

    private func scheduleNavigationPanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.showNavigationPanel()
        }
    }

    private func showNavigationPanel() {
        guard navigationWindowController == nil, let device = readCurrentDevice() else {
            return
        }

        let controller = NavigationWindowController(device: device)
        navigationWindowController = controller
        controller.showWindow(nil)
    }

    private func hideNavigationPanel() {
        navigationWindowController?.close()
        navigationWindowController = nil
    }

    private func readCurrentDevice() -> String? {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = supportURL?.appendingPathComponent("Mirror/current-device") else {
            return nil
        }

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private var splashDismissTimer: Timer?
    private var splashSafetyTimer: Timer?

    private func scheduleSplashDismissal() {
        splashDismissTimer?.invalidate()
        splashSafetyTimer?.invalidate()

        splashDismissTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if self.phoneWindowIsOnScreen() {
                timer.invalidate()
                self.splashDismissTimer = nil
                self.splashSafetyTimer?.invalidate()
                self.splashSafetyTimer = nil
                self.hideSplash()
            }
        }

        splashSafetyTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.splashDismissTimer?.invalidate()
            self?.splashDismissTimer = nil
            self?.splashSafetyTimer = nil
            self?.hideSplash()
        }
    }

    private func phoneWindowIsOnScreen() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for entry in list {
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Mirror" || owner == "MirrorScreen" else { continue }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            if let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
               let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
               rect.width >= 300, rect.height >= 300 {
                return true
            }
        }
        return false
    }

    private func hideSplash() {
        splashDismissTimer?.invalidate()
        splashDismissTimer = nil
        splashSafetyTimer?.invalidate()
        splashSafetyTimer = nil
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
        contentView.layer?.cornerRadius = 14
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        contentView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        contentView.layer?.borderWidth = 1

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = splashIcon()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 64),
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6)
        ])
    }

    private func splashIcon() -> NSImage {
        if let resourceURL = Bundle.main.url(forResource: "Mirror", withExtension: "png"),
           let image = NSImage(contentsOf: resourceURL) {
            return image
        }

        return NSApp.applicationIconImage
    }
}

private final class NavigationWindowController: NSWindowController {
    private let device: String
    private let adbPath = "/opt/homebrew/bin/adb"
    private var trackingTimer: Timer?
    private var lastPersistedFrame: CGRect?

    private static let panelHeight: CGFloat = 48

    init(device: String) {
        self.device = device

        let rect = NSRect(x: 0, y: 0, width: 240, height: Self.panelHeight)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        super.init(window: panel)
        buildButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        positionBelowMirrorWindow()
        startTracking()
    }

    override func close() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        super.close()
    }

    private func buildButtons() {
        guard let contentView = window?.contentView else {
            return
        }

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        contentView.layer?.borderWidth = 1

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        stack.addArrangedSubview(makeButton(symbol: "chevron.left", fallback: "◁", accessibility: "Back", action: #selector(pressBack)))
        stack.addArrangedSubview(makeButton(symbol: "circle", fallback: "○", accessibility: "Home", action: #selector(pressHome)))
        stack.addArrangedSubview(makeButton(symbol: "square", fallback: "▢", accessibility: "Recents", action: #selector(pressRecents)))

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func makeButton(symbol: String, fallback: String, accessibility: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.title = ""
        button.setAccessibilityLabel(accessibility)
        button.toolTip = accessibility
        button.contentTintColor = NSColor.white.withAlphaComponent(0.92)

        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility) {
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            button.image = image.withSymbolConfiguration(config)
            button.imagePosition = .imageOnly
        } else {
            button.title = fallback
            button.font = .systemFont(ofSize: 20, weight: .regular)
        }

        return button
    }

    @objc private func pressBack() { sendKeyevent("4") }
    @objc private func pressHome() { sendKeyevent("3") }
    @objc private func pressRecents() { sendKeyevent("187") }

    private func sendKeyevent(_ code: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = ["-s", device, "shell", "input", "keyevent", code]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.positionBelowMirrorWindow()
        }
    }

    private func positionBelowMirrorWindow() {
        guard let window else {
            return
        }

        guard let mirrorFrame = findMirrorWindowFrame() else {
            if window.isVisible {
                window.orderOut(nil)
            }
            return
        }

        let targetFrame = NSRect(
            x: mirrorFrame.minX,
            y: mirrorFrame.minY - Self.panelHeight,
            width: mirrorFrame.width,
            height: Self.panelHeight
        )

        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
        }
        if !window.isVisible {
            window.orderFront(nil)
        }
    }

    private func findMirrorWindowFrame() -> NSRect? {
        guard let cgFrame = findMirrorCGFrame() else {
            return nil
        }
        persistFrameIfChanged(cgFrame)
        return flipToScreenCoordinates(cgFrame)
    }

    private func findMirrorCGFrame() -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownWindowNumber = window?.windowNumber ?? 0
        var best: CGRect?
        var bestArea: CGFloat = 0

        for entry in list {
            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Mirror" || owner == "MirrorScreen" else {
                continue
            }

            if let windowNumber = entry[kCGWindowNumber as String] as? Int,
               windowNumber == ownWindowNumber {
                continue
            }

            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else {
                continue
            }

            guard let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  cgRect.width >= 300, cgRect.height >= 300 else {
                continue
            }

            let area = cgRect.width * cgRect.height
            if area > bestArea {
                best = cgRect
                bestArea = area
            }
        }

        return best
    }

    private func persistFrameIfChanged(_ frame: CGRect) {
        guard isFrameOnVisibleScreen(frame) else {
            return
        }
        if let previous = lastPersistedFrame, framesMatch(previous, frame) {
            return
        }
        lastPersistedFrame = frame

        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let directory = supportURL?.appendingPathComponent("Mirror") else {
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("window-frame")

        let line = "\(Int(frame.origin.x)) \(Int(frame.origin.y)) \(Int(frame.size.width)) \(Int(frame.size.height))\n"
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }

    private func isFrameOnVisibleScreen(_ cgFrame: CGRect) -> Bool {
        let ns = flipToScreenCoordinates(cgFrame)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(ns) }
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 4 &&
            abs(lhs.origin.y - rhs.origin.y) < 4 &&
            abs(lhs.size.width - rhs.size.width) < 4 &&
            abs(lhs.size.height - rhs.size.height) < 4
    }

    private func flipToScreenCoordinates(_ rect: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else {
            return rect
        }

        let primaryHeight = primary.frame.height
        let flippedY = primaryHeight - rect.origin.y - rect.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.width, height: rect.height)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
