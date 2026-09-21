import AppKit
import AVFoundation

struct MediaItem {
    let url: URL
    let date: Date
    let duration: Double
    let hasAudio: Bool
    let isImage: Bool
    let transcript: String?
    let speechSegments: [SpeechSegment]
}

struct SpeechSegment {
    let start: Double
    let end: Double
    let text: String
}

struct EditSegment {
    let item: MediaItem
    let start: Double
    let length: Double
    let score: Double
    let summary: String?
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var status = NSTextField(labelWithString: "Selecciona o arrastra una carpeta para empezar.")
    private var detail = NSTextField(labelWithString: "")
    private var progress = NSProgressIndicator()
    private var dropView: DropView!
    private var chooseButton: NSButton!
    private var photosButton: NSButton!
    private var ollamaButton: NSButton!
    private var whisperButton: NSButton!
    private var whisperLanguagePopup: NSPopUpButton!
    private var dateStampButton: NSButton!
    private var summaryStampButton: NSButton!
    private var exportButton: NSButton!
    private var selectedFolder: URL?
    private var analyzedItems: [MediaItem] = []
    private var isBusy = false
    private var lastAnalysisStatus = "Análisis local"
    private var lastStampStatus = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window = NSWindow(contentRect: content.frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VlogForge"
        window.delegate = self
        window.contentView = content
        window.center()

        let heading = NSTextField(labelWithString: "VlogForge · creador automático de vlogs")
        heading.font = .systemFont(ofSize: 30, weight: .bold)
        heading.frame = NSRect(x: 34, y: 500, width: 690, height: 38)
        content.addSubview(heading)
        let intro = NSTextField(labelWithString: "Convierte una carpeta de vídeos y fotos en un montaje cronológico usando solo el audio original.")
        intro.textColor = .secondaryLabelColor
        intro.frame = NSRect(x: 36, y: 475, width: 690, height: 22)
        content.addSubview(intro)

        let step1 = sectionLabel("1  ·  Añade tu material")
        step1.frame = NSRect(x: 34, y: 440, width: 690, height: 24)
        content.addSubview(step1)

        dropView = DropView(frame: NSRect(x: 34, y: 300, width: 692, height: 125))
        dropView.onFolder = { [weak self] url in self?.selectFolder(url) }
        content.addSubview(dropView)

        let dropHint = NSTextField(labelWithString: "Puedes arrastrar una carpeta de Google Drive, siempre que sus archivos estén descargados y disponibles sin conexión.")
        dropHint.font = .systemFont(ofSize: 11)
        dropHint.textColor = .tertiaryLabelColor
        dropHint.frame = NSRect(x: 38, y: 280, width: 680, height: 18)
        content.addSubview(dropHint)

        let step2 = sectionLabel("2  ·  Decide cómo analizar y rotular")
        step2.frame = NSRect(x: 34, y: 258, width: 690, height: 24)
        content.addSubview(step2)

        chooseButton = NSButton(title: "Seleccionar carpeta…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .rounded
        chooseButton.frame = NSRect(x: 34, y: 220, width: 170, height: 32)
        content.addSubview(chooseButton)
        photosButton = NSButton(checkboxWithTitle: "Incluir fotos", target: self, action: #selector(photosPreferenceChanged))
        photosButton.state = .on
        photosButton.frame = NSRect(x: 220, y: 224, width: 125, height: 24)
        content.addSubview(photosButton)
        ollamaButton = NSButton(checkboxWithTitle: "Usar Ollama local", target: self, action: nil)
        ollamaButton.state = .off
        ollamaButton.frame = NSRect(x: 350, y: 224, width: 145, height: 24)
        content.addSubview(ollamaButton)
        whisperButton = NSButton(checkboxWithTitle: "Transcribir con Whisper", target: self, action: nil)
        whisperButton.state = .off
        whisperButton.frame = NSRect(x: 505, y: 224, width: 190, height: 24)
        content.addSubview(whisperButton)
        dateStampButton = NSButton(checkboxWithTitle: "Marca día y hora", target: self, action: nil)
        dateStampButton.state = .on
        dateStampButton.frame = NSRect(x: 34, y: 184, width: 155, height: 24)
        content.addSubview(dateStampButton)
        summaryStampButton = NSButton(checkboxWithTitle: "Marca lo que pasa", target: self, action: nil)
        summaryStampButton.state = .on
        summaryStampButton.frame = NSRect(x: 205, y: 184, width: 170, height: 24)
        content.addSubview(summaryStampButton)
        whisperLanguagePopup = NSPopUpButton(frame: NSRect(x: 380, y: 181, width: 180, height: 26), pullsDown: false)
        whisperLanguagePopup.addItems(withTitles: ["Whisper: Auto (CA + ES)", "Whisper: Català", "Whisper: Castellano"])
        whisperLanguagePopup.selectItem(at: 0)
        content.addSubview(whisperLanguagePopup)
        exportButton = NSButton(title: "Generar vlog", target: self, action: #selector(generate))
        exportButton.bezelStyle = .rounded
        exportButton.keyEquivalent = "\r"
        exportButton.frame = NSRect(x: 570, y: 180, width: 156, height: 32)
        exportButton.isEnabled = false
        content.addSubview(exportButton)

        let optionHint = NSTextField(labelWithString: "Ollama elige mejores momentos · Whisper entiende el diálogo · las marcas solo afectan al texto visible.")
        optionHint.font = .systemFont(ofSize: 11)
        optionHint.textColor = .tertiaryLabelColor
        optionHint.frame = NSRect(x: 38, y: 158, width: 680, height: 18)
        content.addSubview(optionHint)

        let step3 = sectionLabel("3  ·  Revisa el estado y genera el MP4")
        step3.frame = NSRect(x: 34, y: 130, width: 690, height: 24)
        content.addSubview(step3)

        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.frame = NSRect(x: 36, y: 104, width: 692, height: 24)
        content.addSubview(status)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 36, y: 78, width: 692, height: 22)
        content.addSubview(detail)
        progress.frame = NSRect(x: 36, y: 54, width: 692, height: 16)
        progress.isIndeterminate = true
        content.addSubview(progress)
        progress.isHidden = true
        let note = NSTextField(labelWithString: "Ollama local: antes de generar, ejecuta «ollama serve» en Terminal. Whisper es opcional.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.frame = NSRect(x: 36, y: 25, width: 692, height: 20)
        content.addSubview(note)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .controlAccentColor
        return label
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Salir de VlogForge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func photosPreferenceChanged() {
        guard let folder = selectedFolder, !isBusy else { return }
        selectFolder(folder)
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
            let items = Self.scan(url, includePhotos: self?.photosButton.state == .on)
            DispatchQueue.main.async {
                guard let self else { return }
                self.analyzedItems = items
                self.progress.stopAnimation(nil)
                self.progress.isHidden = true
                self.exportButton.isEnabled = !items.isEmpty
                let audioCount = items.filter(\.hasAudio).count
                self.status.stringValue = items.isEmpty ? "No se encontró material compatible." : "Material listo para montar."
                self.detail.stringValue = "\(items.count) elementos locales y legibles · \(audioCount) con audio original · se incluirán todos los vídeos"
            }
        }
    }

    static func scan(_ folder: URL, includePhotos: Bool = true) -> [MediaItem] {
        let videoExtensions = Set(["mov", "mp4", "m4v", "mkv", "avi", "mts", "m2ts"])
        let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "tif", "tiff"])
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .isReadableKey, .fileSizeKey]
        let urls = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])?.compactMap { $0 as? URL } ?? []
        return urls.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard videoExtensions.contains(ext) || (includePhotos && imageExtensions.contains(ext)), let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isReadable != false, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            if let fileSize = values.fileSize, fileSize == 0 { return nil }
            let isImage = imageExtensions.contains(ext)
            if isImage { return MediaItem(url: url, date: values.contentModificationDate ?? Date.distantPast, duration: 3, hasAudio: false, isImage: true, transcript: nil, speechSegments: []) }
            let asset = AVURLAsset(url: url)
            let duration = asset.duration.seconds
            guard duration.isFinite, duration > 0 else { return nil }
            if isMostlyBlank(url, duration: duration) { return nil }
            let date = values.contentModificationDate ?? Date.distantPast
            return MediaItem(url: url, date: date, duration: duration, hasAudio: !asset.tracks(withMediaType: .audio).isEmpty, isImage: false, transcript: nil, speechSegments: [])
        }.sorted { $0.date < $1.date }
    }

    static func isMostlyBlank(_ url: URL, duration: Double) -> Bool {
        guard duration > 1 else { return false }
        guard let output = try? runFFmpegCapture(["-hide_banner", "-i", url.path, "-vf", "blackdetect=d=1:pix_th=0.015", "-an", "-f", "null", "-"]) else { return false }
        guard let regex = try? NSRegularExpression(pattern: "black_start:0(?:\\.0+)? black_end:([0-9]+(?:\\.[0-9]+)?)") else { return false }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range), let endRange = Range(match.range(at: 1), in: output), let end = Double(output[endRange]) else { return false }
        return end >= duration * 0.90
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
        lastAnalysisStatus = "Análisis local"
        let useOllama = ollamaButton.state == .on
        let useWhisper = whisperButton.state == .on
        let whisperLanguage = selectedWhisperLanguage()
        let includeDateStamp = dateStampButton.state == .on
        let includeSummaryStamp = summaryStampButton.state == .on
        lastStampStatus = "Marcas: día/hora \(includeDateStamp ? "sí" : "no"), resumen \(includeSummaryStamp ? "sí" : "no")"
        let items = analyzedItems
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try Self.render(items: items, output: output, useOllama: useOllama, useWhisper: useWhisper, whisperLanguage: whisperLanguage, includeDateStamp: includeDateStamp, includeSummaryStamp: includeSummaryStamp) { message in
                    DispatchQueue.main.async {
                        if message.hasPrefix("Whisper listo") || message.hasPrefix("Whisper no") || message.hasPrefix("Ollama listo") || message.hasPrefix("Ollama no") {
                            self?.lastAnalysisStatus = message
                        }
                        self?.status.stringValue = message
                    }
                }
                DispatchQueue.main.async { self?.finished(output: output, error: nil) }
            } catch { DispatchQueue.main.async { self?.finished(output: nil, error: error) } }
        }
    }

    private func selectedWhisperLanguage() -> String {
        switch whisperLanguagePopup.indexOfSelectedItem {
        case 1: return "ca"
        case 2: return "es"
        default: return "auto"
        }
    }

    private func finished(output: URL?, error: Error?) {
        isBusy = false; chooseButton.isEnabled = true; exportButton.isEnabled = !analyzedItems.isEmpty
        progress.stopAnimation(nil); progress.isHidden = true
        if let error { status.stringValue = "No se pudo generar el vlog."; detail.stringValue = error.localizedDescription; return }
        status.stringValue = "Vlog generado correctamente · \(lastAnalysisStatus) · \(lastStampStatus)"
        detail.stringValue = output?.path ?? ""
        if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
    }

    static func render(items: [MediaItem], output: URL, useOllama: Bool = false, useWhisper: Bool = false, whisperLanguage: String = "auto", includeDateStamp: Bool = true, includeSummaryStamp: Bool = true, update: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("vlogforge-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let enrichedItems = useWhisper ? transcribe(items, language: whisperLanguage, update: update) : items
        let selected = selectNarrative(enrichedItems, useOllama: useOllama, allowMultipleSegments: useWhisper || useOllama, update: update)
        var clipPaths: [URL] = []
        for (index, segment) in selected.enumerated() {
            let item = segment.item
            update("Normalizando plano \(index + 1) de \(selected.count)…")
            let clip = temp.appendingPathComponent(String(format: "clip-%03d.mp4", index))
            let start = segment.start
            let length = segment.length
            var args = ["-y"]
            if item.isImage { args += ["-loop", "1", "-framerate", "30"] } else { args += ["-ss", String(start)] }
            args += ["-i", item.url.path]
            if !item.hasAudio { args += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"] }
            let stamp = includeDateStamp ? Self.timestamp(for: item.date) : ""
            let stampImage = temp.appendingPathComponent(String(format: "stamp-%03d.png", index))
            let fallback = includeSummaryStamp ? fallbackTitle(for: segment.item, index: index) : nil
            try makeTimestampOverlay(stamp, summary: includeSummaryStamp ? (segment.summary ?? fallback) : nil, at: stampImage)
            let audioIndex = item.hasAudio ? "0:a:0" : "1:a:0"
            let stampIndex = item.hasAudio ? "1" : "2"
            args += ["-loop", "1", "-i", stampImage.path]
            let filter = "[0:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2[base];[base][\(stampIndex):v]overlay=0:0:shortest=1[v]"
            args += ["-t", String(length), "-filter_complex", filter, "-map", "[v]", "-map", audioIndex, "-r", "30", "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-c:a", "aac", "-ar", "48000", "-ac", "2", "-shortest"]
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

    static func transcribe(_ items: [MediaItem], language: String, update: @escaping (String) -> Void) -> [MediaItem] {
        guard let whisper = whisperBinary(), let model = whisperModel() else {
            update("Whisper no está configurado; se continúa sin transcripción…")
            return items
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vlogforge-whisper-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var succeeded = 0
        let result = items.enumerated().map { index, item in
            guard !item.isImage else { return item }
            update("Transcribiendo audio \(index + 1) de \(items.count)…")
            let wav = directory.appendingPathComponent("audio-\(index).wav")
            let outputBase = directory.appendingPathComponent("text-\(index)")
            do {
                try runFFmpeg(["-y", "-i", item.url.path, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav.path])
                try runWhisper(whisper: whisper, model: model, language: language, audio: wav, outputBase: outputBase)
                let textURL = outputBase.appendingPathExtension("txt")
                let text = try String(contentsOf: textURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                let segments = parseWhisperSegments(at: outputBase.appendingPathExtension("json"))
                if !text.isEmpty { succeeded += 1 }
                return MediaItem(url: item.url, date: item.date, duration: item.duration, hasAudio: item.hasAudio, isImage: false, transcript: text.isEmpty ? nil : text, speechSegments: segments)
            } catch {
                return item
            }
        }
        update("Whisper listo: \(succeeded) de \(items.filter { !$0.isImage }.count) vídeos transcritos.")
        return result
    }

    static func whisperBinary() -> String? {
        var paths: [String] = []
        if let custom = ProcessInfo.processInfo.environment["VLOGFORGE_WHISPER_BIN"] { paths.append(custom) }
        paths += [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/build/bin/whisper-cli").path,
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli"
        ]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    static func whisperModel() -> String? {
        var paths: [String] = []
        if let custom = ProcessInfo.processInfo.environment["VLOGFORGE_WHISPER_MODEL"] { paths.append(custom) }
        paths += [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-base.bin").path,
            "/opt/homebrew/share/whisper.cpp/ggml-base.bin"
        ]
        return paths.first(where: { FileManager.default.isReadableFile(atPath: $0) })
    }

    static func runWhisper(whisper: String, model: String, language: String, audio: URL, outputBase: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: whisper)
        task.arguments = ["-m", model, "-l", language, "-f", audio.path, "-otxt", "-oj", "-of", outputBase.path, "-nt", "-np"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw NSError(domain: "VlogForge", code: 3, userInfo: [NSLocalizedDescriptionKey: "Whisper no pudo transcribir el audio."]) }
    }

    static func parseWhisperSegments(at url: URL) -> [SpeechSegment] {
        guard let data = try? Data(contentsOf: url), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let entries = root["transcription"] as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let text = entry["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            if let offsets = entry["offsets"] as? [String: Any], let from = offsets["from"] as? NSNumber, let to = offsets["to"] as? NSNumber {
                return SpeechSegment(start: from.doubleValue / 1000, end: to.doubleValue / 1000, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let timestamps = entry["timestamps"] as? [String: Any], let from = timestamps["from"] as? String, let to = timestamps["to"] as? String, let start = parseWhisperTime(from), let end = parseWhisperTime(to) {
                return SpeechSegment(start: start, end: end, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }
    }

    static func parseWhisperTime(_ value: String) -> Double? {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    static func fallbackTitle(for item: MediaItem, index: Int) -> String {
        if let transcript = item.transcript {
            let firstSentence = transcript.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? transcript
            let clean = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { return String(clean.prefix(90)) }
        }
        return "Clip \(index + 1)"
    }

    static func selectNarrative(_ items: [MediaItem], useOllama: Bool = false, allowMultipleSegments: Bool = false, update: ((String) -> Void)? = nil) -> [EditSegment] {
        guard !items.isEmpty else { return [] }
        var candidates: [(index: Int, segment: EditSegment)] = []
        for (index, item) in items.enumerated() {
            update?("Analizando cambios de plano \(index + 1) de \(items.count)…")
            let sceneTimes = item.isImage ? [] : detectSceneTimes(item.url)
            var times = [0.0, item.duration * 0.28, item.duration * 0.58, item.duration * 0.82]
            times.append(contentsOf: sceneTimes)
            var uniqueTimes: [Double] = []
            for time in times.sorted() where time >= 0 && time < item.duration {
                if uniqueTimes.last.map({ abs($0 - time) > 1.2 }) ?? true { uniqueTimes.append(time) }
            }
            for time in uniqueTimes {
                let clipWindow = item.transcript == nil ? 8.0 : (item.duration <= 30 ? item.duration : 14.0)
                let length = min(clipWindow, item.duration - time)
                guard length >= 1 else { continue }
                let isSceneMoment = sceneTimes.contains { abs($0 - time) < 1.2 }
                let score = (item.hasAudio ? 1.5 : 0) + (isSceneMoment ? 2.0 : 0) + (length >= 4 ? 0.5 : 0)
                let start = item.duration > clipWindow ? min(time, item.duration - clipWindow) : 0
                candidates.append((index, EditSegment(item: item, start: start, length: min(clipWindow, item.duration - start), score: score, summary: nil)))
            }
            if !item.speechSegments.isEmpty {
                for speech in item.speechSegments {
                    let window = item.duration <= 30 ? item.duration : 14.0
                    let end = min(item.duration, speech.end + 1.0)
                    let start = max(0, end - window)
                    let length = min(window, item.duration - start)
                    guard length >= 1 else { continue }
                    let score = 5.0 + min(3.0, max(0, speech.end - speech.start))
                    candidates.append((index, EditSegment(item: item, start: start, length: length, score: score, summary: nil)))
                }
            }
        }
        guard !candidates.isEmpty else { return [] }
        if useOllama, let aiSelection = OllamaClient.select(candidates: candidates, update: update) {
            return completeAllSources(aiSelection, candidates: candidates, includeAllRelevant: allowMultipleSegments)
        }
        return completeAllSources([], candidates: candidates, includeAllRelevant: allowMultipleSegments)
    }

    static func completeAllSources(_ chosen: [EditSegment], candidates: [(index: Int, segment: EditSegment)], includeAllRelevant: Bool = false) -> [EditSegment] {
        let sourceCount = Set(candidates.map(\.index)).count
        var bySource: [Int: EditSegment] = [:]
        var selected = chosen
        if includeAllRelevant {
            selected.append(contentsOf: candidates.filter { $0.segment.score >= 5.0 }.map(\.segment))
        }
        for segment in selected {
            if let source = candidates.first(where: { $0.segment.item.url == segment.item.url })?.index,
               !includeAllRelevant, bySource[source] == nil { bySource[source] = segment }
        }
        if !includeAllRelevant {
            for source in 0..<sourceCount where bySource[source] == nil {
                if let best = candidates.filter({ $0.index == source }).max(by: { $0.segment.score < $1.segment.score }) { bySource[source] = best.segment }
            }
            return bySource.values.sorted { left, right in
                if left.item.date == right.item.date { return left.start < right.start }
                return left.item.date < right.item.date
            }
        }
        for source in 0..<sourceCount {
            let sourceURL = candidates.first(where: { $0.index == source })?.segment.item.url
            if let sourceURL, !selected.contains(where: { $0.item.url == sourceURL }),
               let best = candidates.filter({ $0.index == source }).max(by: { $0.segment.score < $1.segment.score }) {
                bySource[source] = best.segment
            }
        }
        let all = selected + Array(bySource.values)
        var deduplicated: [EditSegment] = []
        for segment in all.sorted(by: { $0.item.date == $1.item.date ? $0.start < $1.start : $0.item.date < $1.item.date }) {
            let overlaps = deduplicated.contains { existing in
                existing.item.url == segment.item.url && abs(existing.start - segment.start) < 4
            }
            if !overlaps { deduplicated.append(segment) }
        }
        return deduplicated
    }

    enum OllamaClient {
        static func select(candidates: [(index: Int, segment: EditSegment)], update: ((String) -> Void)?) -> [EditSegment]? {
            guard let modelInfo = availableModel() else {
                update?("Ollama no está disponible; se usará el análisis local.")
                return nil
            }
            let model = modelInfo.name
            // AI mode may choose several moments from the same source. There
            // is no editorial cap here: the transcript and model decide.
            let limited = candidates
            update?("Consultando Ollama local para elegir los momentos importantes…")
            var describedSources = Set<Int>()
            let promptCandidates = limited.enumerated().map { position, candidate in
                let segment = candidate.segment
                let firstForSource = describedSources.insert(candidate.index).inserted
                return [
                    "id": position,
                    "source": candidate.index,
                    "fecha": timestamp(for: segment.item.date),
                    "inicio_segundos": round(segment.start),
                    "duracion_segundos": round(segment.length),
                    "tiene_audio_original": segment.item.hasAudio,
                    "es_foto": segment.item.isImage,
                    "transcripcion_completa_del_video": firstForSource ? String((segment.item.transcript ?? "").prefix(6000)) : ""
                ] as [String : Any]
            }
            var payload: [String: Any] = [
                "model": model,
                "stream": false,
                "format": "json",
                "prompt": "Eres un editor de vlogs. Hay que incluir al menos un momento de cada source disponible: no descartes un source salvo que su imagen sea completamente negra o ilegible. No hay un límite fijo de clips. Puedes elegir varios ids del mismo source si muestran momentos distintos o si juntos cuentan mejor lo ocurrido; también puedes elegir todos los candidatos de un source corto si merece conservarse completo. Busca llegadas, contexto, acciones, reacciones y cierre; mantén el orden cronológico. Las imágenes adjuntas corresponden a los candidatos en el mismo orden. Devuelve únicamente JSON con esta forma: {\\\"selected\\\":[1,2],\\\"summaries\\\":[{\\\"id\\\":1,\\\"text\\\":\\\"breve resumen\\\"}]}. Candidatos: \(jsonString(promptCandidates))"
            ]
            if modelInfo.isVision, let images = frameImages(for: limited), !images.isEmpty { payload["images"] = images }
            guard let body = try? JSONSerialization.data(withJSONObject: payload),
                  let response = post(body: body) else {
                update?("Ollama no respondió; se usará el análisis local.")
                return nil
            }
            guard let outer = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                  let text = outer["response"] as? String,
                  let inner = parseJSONObject(text),
                  let selectedIds = inner["selected"] as? [NSNumber] else {
                update?("Ollama devolvió una respuesta no válida; se usará el análisis local.")
                return nil
            }
            var summaries: [Int: String] = [:]
            if let summaryItems = inner["summaries"] as? [[String: Any]] {
                for item in summaryItems {
                    if let id = item["id"] as? NSNumber, let text = item["text"] as? String { summaries[id.intValue] = text }
                }
            } else if let summaryMap = inner["summaries"] as? [String: String] {
                for (id, text) in summaryMap where Int(id) != nil { summaries[Int(id)!] = text }
            }
            let valid = selectedIds.compactMap { id -> EditSegment? in
                let position = id.intValue
                guard position >= 0 && position < limited.count else { return nil }
                let segment = limited[position].segment
                return EditSegment(item: segment.item, start: segment.start, length: segment.length, score: segment.score, summary: summaries[position])
            }
            if valid.isEmpty {
                update?("Ollama no seleccionó candidatos válidos; se usará el análisis local.")
                return nil
            }
            update?("Ollama listo: ha elegido momentos y generado resúmenes.")
            return valid
        }

        private static func availableModel() -> (name: String, isVision: Bool)? {
            let preferred = ProcessInfo.processInfo.environment["VLOGFORGE_OLLAMA_MODEL"]
            guard let data = get(path: "/api/tags"), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let models = object["models"] as? [[String: Any]] else { return nil }
            let names = models.compactMap { $0["name"] as? String }
            if let preferred, names.contains(preferred) { return (preferred, isVision(preferred)) }
            let vision = names.first { name in
                let lower = name.lowercased()
                return lower.contains("vision") || lower.contains("llava") || lower.contains("qwen2.5vl") || lower.contains("gemma3")
            }
            if let vision { return (vision, true) }
            return names.first.map { ($0, false) }
        }

        private static func isVision(_ name: String) -> Bool {
            let lower = name.lowercased()
            return lower.contains("vision") || lower.contains("llava") || lower.contains("qwen2.5vl") || lower.contains("gemma3")
        }

        private static func frameImages(for candidates: [(index: Int, segment: EditSegment)]) -> [String]? {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vlogforge-ollama-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            var images: [String] = []
            for (position, candidate) in candidates.enumerated() {
                let segment = candidate.segment
                let frame = directory.appendingPathComponent("frame-\(position).jpg")
                let middle = segment.item.isImage ? 0 : segment.start + (segment.length / 2)
                do {
                    try AppDelegate.runFFmpeg(["-y", "-ss", String(middle), "-i", segment.item.url.path, "-frames:v", "1", "-vf", "scale=320:-2", "-q:v", "6", frame.path])
                    guard let data = try? Data(contentsOf: frame) else { return nil }
                    images.append(data.base64EncodedString())
                } catch { return nil }
            }
            return images
        }

        private static func post(body: Data) -> Data? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/generate")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            request.timeoutInterval = 180
            let semaphore = DispatchSemaphore(value: 0)
            var result: Data?
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
            _ = semaphore.wait(timeout: .now() + 185)
            return result
        }

        private static func get(path: String) -> Data? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11434\(path)")!)
            request.timeoutInterval = 5
            let semaphore = DispatchSemaphore(value: 0)
            var result: Data?
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
            _ = semaphore.wait(timeout: .now() + 6)
            return result
        }

        private static func jsonString(_ value: Any) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: value), let string = String(data: data, encoding: .utf8) else { return "[]" }
            return string
        }

        private static func parseJSONObject(_ text: String) -> [String: Any]? {
            var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("```") {
                cleaned = cleaned.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start <= end else { return nil }
            let json = String(cleaned[start...end])
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }

    static func detectSceneTimes(_ url: URL) -> [Double] {
        do {
            let output = try runFFmpegCapture(["-hide_banner", "-i", url.path, "-vf", "select='gt(scene,0.18)',showinfo", "-an", "-f", "null", "-"])
            let regex = try NSRegularExpression(pattern: "pts_time:([0-9]+(?:\\.[0-9]+)?)")
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            return regex.matches(in: output, range: range).compactMap { match in
                guard let valueRange = Range(match.range(at: 1), in: output) else { return nil }
                return Double(output[valueRange])
            }
        } catch { return [] }
    }

    static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy  HH:mm"
        return formatter.string(from: date)
    }

    static func makeTimestampOverlay(_ text: String, summary: String?, at url: URL) throws {
        let image = NSImage(size: NSSize(width: 1280, height: 720))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 1280, height: 720).fill()
        let hasSummary = !(summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let boxHeight: CGFloat = hasSummary ? 96 : 70
        if !text.isEmpty || hasSummary {
            NSColor.black.withAlphaComponent(0.60).setFill()
            NSRect(x: 0, y: 0, width: 1280, height: boxHeight).fill()
        }
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: hasSummary ? 22 : 28, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        if !text.isEmpty { (text as NSString).draw(at: NSPoint(x: 28, y: hasSummary ? 56 : 21), withAttributes: dateAttributes) }
        if let summary, hasSummary {
            let summaryAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.white.withAlphaComponent(0.94)]
            let clipped = String(summary.prefix(100))
            (clipped as NSString).draw(at: NSPoint(x: 28, y: 21), withAttributes: summaryAttributes)
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "VlogForge", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear la fecha del plano."])
        }
        try png.write(to: url)
    }

    static func runFFmpeg(_ args: [String]) throws {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw NSError(domain: "VlogForge", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encontró FFmpeg. Instálalo con Homebrew: brew install ffmpeg"]) }
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
        let pipe = Pipe(); task.standardError = pipe; task.standardOutput = pipe
        try task.run(); task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw NSError(domain: "VlogForge", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "FFmpeg no pudo procesar uno de los clips."]) }
    }

    static func runFFmpegCapture(_ args: [String]) throws -> String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw NSError(domain: "VlogForge", code: 1, userInfo: nil) }
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
        let pipe = Pipe(); task.standardError = pipe; task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw NSError(domain: "VlogForge", code: Int(task.terminationStatus), userInfo: nil) }
        return String(data: data, encoding: .utf8) ?? ""
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
