import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--verify-model"), index + 1 < CommandLine.arguments.count {
    do {
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let report = output.appendingPathComponent("Model.json")
        if FileManager.default.fileExists(atPath: report.path) { try FileManager.default.removeItem(at: report) }
        let resources = try ClassicResources(directory: Bundle.main.resourceURL!.appendingPathComponent("Resources"))
        let checks = try BitmapTextVerification.run(resources: resources, output: output) + TextModelVerification.run(resources: resources)
            + SelectionVerification.model(resources: resources)
            + DocumentLifecycleVerification.model(resources: resources)
            + PageOverviewVerification.model(resources: resources)
            + FontVerification.model(resources: resources)
            + CatalogVerification.model(resources: resources, output: output)
            + Macintosh128KVerification.model(resources: resources)
        try JSONSerialization.data(withJSONObject: ["checks": checks, "count": checks.count,
            "scope": "Document model and bitmap raster only; no window, keyboard routing, pasteboard or WindowServer verification."], options: [.prettyPrinted, .sortedKeys])
            .write(to: report)
        print("\(checks.count) model and raster checks passed; graphical verification remains separate.")
        exit(0)
    } catch {
        fputs("MODEL VERIFICATION FAILED: \(error)\n", stderr)
        exit(1)
    }
}

let application = PaintApplication.shared
application.setActivationPolicy(.regular)
let delegate = AppController()
if let index = CommandLine.arguments.firstIndex(of: "--verify"), index + 1 < CommandLine.arguments.count {
    delegate.verificationDirectory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
}
if let index = CommandLine.arguments.firstIndex(of: "--verify-reopen"), index + 2 < CommandLine.arguments.count {
    delegate.verificationDirectory = URL(fileURLWithPath: CommandLine.arguments[index + 2], isDirectory: true)
    delegate.verificationReopenURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
}
for mode in ["write", "read"] {
    if let index = CommandLine.arguments.firstIndex(of: "--verify-recovery-" + mode), index + 1 < CommandLine.arguments.count {
        delegate.verificationDirectory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        delegate.verificationRecoveryMode = mode
    }
}
application.delegate = delegate
application.run()
