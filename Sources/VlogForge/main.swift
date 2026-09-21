import AppKit
import AVFoundation

struct MediaItem {
    let url: URL
    let date: Date
    let duration: Double
    let hasAudio: Bool
    let isImage: Bool
}

final class DropView: NSView {
    var onFolder: ((URL) -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.45).cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let first = urls.first else { return false }
        let folder = first.hasDirectoryPath ? first : first.deletingLastPathComponent()
        onFolder?(folder)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let title = "Arrastra aquí una carpeta de material"
        let subtitle = "Vídeos y fotos · el audio original se conserva"
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
        (title as NSString).draw(at: NSPoint(x: 28, y: bounds.midY + 4), withAttributes: titleAttributes)
        (subtitle as NSString).draw(at: NSPoint(x: 28, y: bounds.midY - 23), withAttributes: subtitleAttributes)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var status = NSTextField(labelWithString: "Selecciona o arrastra una carpeta para empezar.")
    private var detail = NSTextField(labelWithString: "")
    private var progress = NSProgressIndicator()
    private var dropView: DropView!
    private var chooseButton: NSButton!
    private var exportButton: NSButton!
    private var selectedFolder: URL?
    private var analyzedItems: [MediaItem] = []
    private var isBusy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 470))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VlogForge"
        window.contentView = content
        window.center()

        let heading = NSTextField(labelWithString: "VlogForge")
        heading.font = .systemFont(ofSize: 30, weight: .bold)
        heading.frame = NSRect(x: 34, y: 410, width: 300, height: 38)
        content.addSubview(heading)
        let intro = NSTextField(labelWithString: "Crea un primer montaje cronológico a partir de tus recuerdos.")
        intro.textColor = .secondaryLabelColor
        intro.frame = NSRect(x: 36, y: 386, width: 550, height: 22)
        content.addSubview(intro)

        dropView = DropView(frame: NSRect(x: 34, y: 238, width: 612, height: 130))
        dropView.onFolder = { [weak self] url in self?.selectFolder(url) }
        content.addSubview(dropView)

        chooseButton = NSButton(title: "Seleccionar carpeta…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        chooseButton.frame = NSRect(x: 34, y: 190, width: 170, height: 32)
        content.addSubview(chooseButton)
        exportButton = NSButton(title: "Generar vlog", target: self, action: #selector(generate))
        exportButton.bezelStyle = .rounded
        exportButton.keyEquivalent = "\r"
        exportButton.frame = NSRect(x: 475, y: 190, width: 171, height: 32)
        exportButton.isEnabled = false
        content.addSubview(exportButton)

        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.frame = NSRect(x: 36, y: 142, width: 610, height: 24)
        content.addSubview(status)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 36, y: 112, width: 610, height: 22)
        content.addSubview(detail)
        progress.frame = NSRect(x: 36, y: 74, width: 610, height: 16)
        progress.isIndeterminate = true
        content.addSubview(progress)
        progress.isHidden = true
        let note = NSTextField(labelWithString: "MVP: selección cronológica y cortes cortos. No añade música ni efectos generados.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.frame = NSRect(x: 36, y: 35, width: 610, height: 20)
        content.addSubview(note)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analizar"
        if panel.runModal() == .OK, let url = panel.url { selectFolder(url) }
    }

    private func selectFolder(_ url: URL) {
        guard !isBusy else { return }
        selectedFolder = url
        exportButton.isEnabled = false
        progress.isHidden = false
        progress.startAnimation(nil)
        status.stringValue = "Analizando material…"
        detail.stringValue = url.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = Self.scan(url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.analyzedItems = items
                self.progress.stopAnimation(nil)
                self.progress.isHidden = true
                self.exportButton.isEnabled = !items.isEmpty
                let audioCount = items.filter(\.hasAudio).count
                self.status.stringValue = items.isEmpty ? "No se encontraron vídeos compatibles." : "Material listo para montar."
                self.detail.stringValue = "\(items.count) vídeos · \(audioCount) con audio original · ordenados por fecha"
            }
        }
    }

    static func scan(_ folder: URL) -> [MediaItem] {
        let videoExtensions = Set(["mov", "mp4", "m4v", "mkv", "avi", "mts", "m2ts"])
        let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "tif", "tiff"])
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let urls = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])?.compactMap { $0 as? URL } ?? []
        return urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard videoExtensions.contains(ext) || imageExtensions.contains(ext), let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            let isImage = imageExtensions.contains(ext)
            if isImage { return MediaItem(url: url, date: values.contentModificationDate ?? Date.distantPast, duration: 3, hasAudio: false, isImage: true) }
            let asset = AVURLAsset(url: url)
            let duration = asset.duration.seconds
            guard duration.isFinite, duration > 0 else { return nil }
            let date = values.contentModificationDate ?? Date.distantPast
            return MediaItem(url: url, date: date, duration: duration, hasAudio: !asset.tracks(withMediaType: .audio).isEmpty, isImage: false)
        }.sorted { $0.date < $1.date }
    }

    @objc private func generate() {
        guard let folder = selectedFolder, !analyzedItems.isEmpty, !isBusy else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vlog-\(folder.lastPathComponent).mp4"
        panel.allowedFileTypes = ["mp4"]
        guard panel.runModal() == .OK, let output = panel.url else { return }
        isBusy = true
        chooseButton.isEnabled = false
        exportButton.isEnabled = false
        progress.isHidden = false
        progress.startAnimation(nil)
        status.stringValue = "Generando selección cronológica…"
        detail.stringValue = "Preparando planos breves y conservando su audio asociado."
        let items = analyzedItems
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try Self.render(items: items, output: output) { message in
                    DispatchQueue.main.async { self?.status.stringValue = message }
                }
                DispatchQueue.main.async { self?.finished(output: output, error: nil) }
            } catch { DispatchQueue.main.async { self?.finished(output: nil, error: error) } }
        }
    }

    private func finished(output: URL?, error: Error?) {
        isBusy = false; chooseButton.isEnabled = true; exportButton.isEnabled = !analyzedItems.isEmpty
        progress.stopAnimation(nil); progress.isHidden = true
        if let error { status.stringValue = "No se pudo generar el vlog."; detail.stringValue = error.localizedDescription; return }
        status.stringValue = "Vlog generado correctamente."
        detail.stringValue = output?.path ?? ""
        if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
    }

    static func render(items: [MediaItem], output: URL, update: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("vlogforge-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let selected = selectNarrative(items)
        var clipPaths: [URL] = []
        for (index, item) in selected.enumerated() {
            update("Normalizando plano \(index + 1) de \(selected.count)…")
            let clip = temp.appendingPathComponent(String(format: "clip-%03d.mp4", index))
            let start = item.duration > 8 ? max(0, min(item.duration * 0.18, item.duration - 8)) : 0
            let length = min(8, item.duration - start)
            var args = ["-y"]
            if item.isImage { args += ["-loop", "1", "-framerate", "30"] } else { args += ["-ss", String(start)] }
            args += ["-i", item.url.path, "-t", String(length), "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,format=yuv420p", "-r", "30", "-c:v", "libx264", "-preset", "veryfast", "-crf", "22"]
            if item.hasAudio { args += ["-c:a", "aac", "-ar", "48000", "-ac", "2"] } else { args += ["-an"] }
            args += [clip.path]
            try runFFmpeg(args)
            clipPaths.append(clip)
        }
        let list = temp.appendingPathComponent("concat.txt")
        let contents = clipPaths.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: "\n")
        try contents.write(to: list, atomically: true, encoding: .utf8)
        update("Uniendo planos y exportando MP4…")
        try runFFmpeg(["-y", "-f", "concat", "-safe", "0", "-i", list.path, "-c", "copy", output.path])
    }

    static func selectNarrative(_ items: [MediaItem]) -> [MediaItem] {
        let maxClips = 12
        if items.count <= maxClips { return items }
        let stride = Double(items.count - 1) / Double(maxClips - 1)
        return (0..<maxClips).map { items[Int((Double($0) * stride).rounded())] }
    }

    static func runFFmpeg(_ args: [String]) throws {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw NSError(domain: "VlogForge", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encontró FFmpeg. Instálalo con Homebrew: brew install ffmpeg"]) }
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
        let pipe = Pipe(); task.standardError = pipe; task.standardOutput = pipe
        try task.run(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw NSError(domain: "VlogForge", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "FFmpeg no pudo procesar uno de los clips."]) }
    }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--self-test" {
    let folder = URL(fileURLWithPath: CommandLine.arguments[2])
    let items = AppDelegate.scan(folder)
    guard !items.isEmpty else { print("SELF-TEST: no compatible videos"); exit(2) }
    let output = folder.appendingPathComponent("vlogforge-self-test.mp4")
    do {
        try AppDelegate.render(items: items, output: output) { print($0) }
        print("SELF-TEST: created \(output.path)")
    } catch { print("SELF-TEST: failed: \(error.localizedDescription)"); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
