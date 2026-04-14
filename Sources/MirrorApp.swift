import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var task: Process?
    private var outputData = Data()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
