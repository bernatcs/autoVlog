import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct MediaItem {
    let url: URL
    let date: Date
    let duration: Double
    let hasAudio: Bool
    let isImage: Bool
    let width: Int
    let height: Int
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
    var onClick: (() -> Void)?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private var isTargeted = false { didSet { updateColors() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1.5
        icon.symbolConfiguration = .init(pointSize: 32, weight: .regular)
        icon.contentTintColor = .controlAccentColor
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        let texts = NSStackView(views: [title, subtitle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 4
        let row = NSStackView(views: [icon, texts])
        row.spacing = 16
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 112)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Elegir carpeta de material")
        updateColors()
        show(symbol: "folder.badge.plus", title: "Arrastra aquí una carpeta o haz clic para elegirla", subtitle: "Vídeos y fotos · si están en Google Drive, descárgalos antes para usarlos sin conexión")
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(symbol: String, title: String, subtitle: String) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.title.stringValue = title
        self.subtitle.stringValue = subtitle
    }

    // Layer colors are static CGColors, so re-resolve them on light/dark switches.
    override func viewDidChangeEffectiveAppearance() { updateColors() }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(isTargeted ? 0.9 : 0.35).cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isTargeted ? 0.18 : 0.06).cgColor
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { isTargeted = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { isTargeted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let first = urls.first else { return false }
        let folder = first.hasDirectoryPath ? first : first.deletingLastPathComponent()
        onFolder?(folder)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var status = NSTextField(labelWithString: "Elige una carpeta para empezar.")
    private var detail = NSTextField(wrappingLabelWithString: "")
    private var progress = NSProgressIndicator()
    private var spinner = NSProgressIndicator()
    private var ticker: Timer?
    private var dropView: DropView!
    private var photosButton: NSButton!
    private var ollamaButton: NSButton!
    private var ollamaStatus = NSTextField(labelWithString: "Comprobando…")
    private var whisperButton: NSButton!
    private var whisperStatus = NSTextField(labelWithString: "Comprobando…")
    private var whisperLanguagePopup: NSPopUpButton!
    private var durationPopup: NSPopUpButton!
    private var dateStampButton: NSButton!
    private var summaryStampButton: NSButton!
    private var exportButton: NSButton!
    private var openButton: NSButton!
    private var revealButton: NSButton!
    private var selectedFolder: URL?
    private var mediaCount = 0
    private var lastOutput: URL?
    private var isBusy = false
    private var toolsChecked = false
    private var lastAnalysisStatus = "Análisis local"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VlogForge"
        window.delegate = self

        let heading = label("VlogForge", size: 28, weight: .bold)
        let intro = label("Convierte una carpeta de vídeos y fotos en un vlog cronológico con su audio original.", size: 13, color: .secondaryLabelColor)

        dropView = DropView(frame: .zero)
        dropView.onFolder = { [weak self] url in self?.selectFolder(url) }
        dropView.onClick = { [weak self] in self?.chooseFolder() }

        ollamaButton = NSButton(checkboxWithTitle: "Elegir los mejores momentos y titularlos con Ollama", target: nil, action: nil)
        whisperButton = NSButton(checkboxWithTitle: "Entender lo que se dice con Whisper", target: self, action: #selector(whisperToggled))
        whisperLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        whisperLanguagePopup.addItems(withTitles: ["Català + castellano", "Detectar idioma", "Castellano", "Català", "English", "中文", "Français", "Italiano", "Português"])
        whisperLanguagePopup.controlSize = .small
        whisperLanguagePopup.font = .systemFont(ofSize: 11)
        for statusLabel in [ollamaStatus, whisperStatus] {
            statusLabel.font = .systemFont(ofSize: 11)
            statusLabel.textColor = .secondaryLabelColor
        }
        let aiBox = group("Inteligencia artificial local", [
            row([ollamaButton], trailing: [ollamaStatus]),
            row([whisperButton, whisperLanguagePopup], trailing: [whisperStatus])
        ])

        dateStampButton = NSButton(checkboxWithTitle: "Fecha y hora", target: nil, action: nil)
        dateStampButton.state = .on
        summaryStampButton = NSButton(checkboxWithTitle: "Título de cada clip (Ollama)", target: nil, action: nil)
        summaryStampButton.state = .on
        photosButton = NSButton(checkboxWithTitle: "Incluir fotos (3 s cada una)", target: self, action: #selector(photosPreferenceChanged))
        photosButton.state = .on
        durationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        durationPopup.addItems(withTitles: Self.durations.map { "Vlog de \($0 / 60) min" })
        durationPopup.selectItem(at: 1)
        let optionsBox = group("Montaje", [
            row([NSTextField(labelWithString: "Duración aproximada:"), durationPopup], trailing: []),
            row([dateStampButton, summaryStampButton, photosButton], trailing: [])
        ])

        status.font = .systemFont(ofSize: 13, weight: .semibold)
        status.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.preferredMaxLayoutWidth = 420
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true // hidden views leave the stack, so the status text stays aligned
        let statusLine = NSStackView(views: [spinner, status])
        statusLine.spacing = 6
        let texts = NSStackView(views: [statusLine, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        revealButton = NSButton(title: "Mostrar en Finder", target: self, action: #selector(revealOutput))
        openButton = NSButton(title: "Abrir vídeo", target: self, action: #selector(openOutput))
        exportButton = NSButton(title: "Generar vlog", target: self, action: #selector(generate))
        exportButton.keyEquivalent = "\r"
        for button in [revealButton!, openButton!, exportButton!] { button.bezelStyle = .rounded; button.controlSize = .large }
        revealButton.isHidden = true
        openButton.isHidden = true
        exportButton.isEnabled = false
        let footer = row([texts], trailing: [revealButton, openButton, exportButton])
        footer.alignment = .centerY

        progress.isIndeterminate = false
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        progress.alphaValue = 0 // hidden via alpha so the window layout never jumps

        let main = NSStackView(views: [heading, intro, dropView, aiBox, optionsBox, footer, progress])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 14
        main.setCustomSpacing(4, after: heading)
        main.setCustomSpacing(20, after: intro)
        main.setCustomSpacing(20, after: optionsBox)
        main.setCustomSpacing(10, after: footer)
        main.edgeInsets = NSEdgeInsets(top: 22, left: 28, bottom: 22, right: 28)
        main.widthAnchor.constraint(equalToConstant: 720).isActive = true
        for view in [dropView!, aiBox, optionsBox, footer, progress] {
            view.widthAnchor.constraint(equalTo: main.widthAnchor, constant: -56).isActive = true
        }
        window.contentView = main
        window.setContentSize(main.fittingSize)
        window.center()
        refreshToolStatus()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Dev aid: `--snapshot out.png [folder]` renders the window to a PNG
        // (no Screen Recording permission needed) and quits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            if i + 2 < args.count { selectFolder(URL(fileURLWithPath: args[i + 2])) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [self] in
                let view = window.contentView!.superview!
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
                }
                NSApp.terminate(nil)
            }
        }
    }

    // Picks up Ollama/Whisper installed or started while the app was open.
    func applicationDidBecomeActive(_ notification: Notification) {
        if window != nil { refreshToolStatus() }
    }

    private func refreshToolStatus() {
        DispatchQueue.global(qos: .utility).async {
            let ollamaModel = OllamaClient.availableModel()?.name
            let whisperModel = Self.whisperBinary() == nil ? nil : Self.whisperModel().map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.replacingOccurrences(of: "ggml-", with: "")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setToolStatus(self.ollamaStatus, ready: ollamaModel.map { "Listo · \($0)" }, missing: "No detectado · abre la app Ollama")
                self.setToolStatus(self.whisperStatus, ready: whisperModel.map { "Listo · \($0)" }, missing: "No instalado · ver README")
                // Turn available tools on once; afterwards respect the user's choice.
                if !self.toolsChecked {
                    self.toolsChecked = true
                    self.ollamaButton.state = ollamaModel == nil ? .off : .on
                    self.whisperButton.state = whisperModel == nil ? .off : .on
                    self.whisperToggled()
                }
            }
        }
    }

    private func setToolStatus(_ field: NSTextField, ready: String?, missing: String) {
        field.stringValue = "● " + (ready ?? missing)
        field.textColor = ready == nil ? .systemOrange : .systemGreen
    }

    @objc private func whisperToggled() {
        whisperLanguagePopup.isEnabled = whisperButton.state == .on
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private func row(_ leading: [NSView], trailing: [NSView]) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        leading.forEach { stack.addView($0, in: .leading) }
        trailing.forEach { stack.addView($0, in: .trailing) }
        return stack
    }

    private func group(_ title: String, _ rows: [NSView]) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = .systemFont(ofSize: 12, weight: .semibold)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = box.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return box
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
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analizar"
        if panel.runModal() == .OK, let url = panel.url { selectFolder(url) }
    }

    // Only counts files by extension so the button is usable right away;
    // the slow per-video scan runs as the first step of "Generar vlog".
    private func selectFolder(_ url: URL) {
        guard !isBusy else { return }
        selectedFolder = url
        exportButton.isEnabled = false
        openButton.isHidden = true
        revealButton.isHidden = true
        dropView.show(symbol: "folder.fill", title: url.lastPathComponent, subtitle: "Contando archivos…")
        let includePhotos = photosButton.state == .on
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = Self.mediaFiles(in: url, includePhotos: includePhotos)
            let photos = files.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }.count
            let videos = files.count - photos
            DispatchQueue.main.async {
                guard let self, self.selectedFolder == url else { return }
                self.mediaCount = files.count
                self.exportButton.isEnabled = !files.isEmpty
                if files.isEmpty {
                    self.dropView.show(symbol: "exclamationmark.triangle", title: "No hay vídeos ni fotos compatibles", subtitle: url.path)
                    self.status.stringValue = "Prueba con otra carpeta."
                    self.detail.stringValue = "Si el material está en Google Drive, márcalo como disponible sin conexión."
                    return
                }
                var parts = ["\(videos) vídeo\(videos == 1 ? "" : "s")"]
                if photos > 0 { parts.append("\(photos) foto\(photos == 1 ? "" : "s")") }
                self.dropView.show(symbol: "folder.fill", title: url.lastPathComponent, subtitle: parts.joined(separator: " · ") + " · haz clic para cambiar")
                self.status.stringValue = "Carpeta lista."
                self.detail.stringValue = "Elige las opciones y pulsa «Generar vlog»: el análisis empieza entonces."
            }
        }
    }

    static let durations = [60, 120, 180, 300, 600] // seconds, for the duration popup

    static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60) min \(total % 60) s" : "\(total) s"
    }

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "mts", "m2ts"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]
    static let scanKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .isReadableKey, .fileSizeKey]

    static func mediaFiles(in folder: URL, includePhotos: Bool) -> [URL] {
        let urls = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(scanKeys), options: [.skipsHiddenFiles])?.compactMap { $0 as? URL } ?? []
        return urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return videoExtensions.contains(ext) || (includePhotos && imageExtensions.contains(ext))
        }
    }

    static func scan(_ folder: URL, includePhotos: Bool = true, update: ((String) -> Void)? = nil) -> [MediaItem] {
        let keys = scanKeys
        let urls = mediaFiles(in: folder, includePhotos: includePhotos)
        return urls.enumerated().compactMap { index, url in
            update?("Revisando archivo \(index + 1) de \(urls.count)…")
            let ext = url.pathExtension.lowercased()
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isReadable != false, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            if let fileSize = values.fileSize, fileSize == 0 { return nil }
            let isImage = imageExtensions.contains(ext)
            if isImage {
                let size = NSImage(contentsOf: url)?.size ?? NSSize(width: 1280, height: 720)
                return MediaItem(url: url, date: photoCaptureDate(url) ?? values.contentModificationDate ?? Date.distantPast, duration: 3, hasAudio: false, isImage: true, width: max(1, Int(size.width)), height: max(1, Int(size.height)), transcript: nil, speechSegments: [])
            }
            let asset = AVURLAsset(url: url)
            let duration = asset.duration.seconds
            guard duration.isFinite, duration > 0 else { return nil }
            if isMostlyBlank(url, duration: duration) { return nil }
            // Copying from a phone or Google Drive resets the modification
            // date, so prefer the capture date stored in the file.
            let date = asset.creationDate?.dateValue ?? values.contentModificationDate ?? Date.distantPast
            let track = asset.tracks(withMediaType: .video).first
            let rawRect = track.map { CGRect(origin: .zero, size: $0.naturalSize).applying($0.preferredTransform) }
            let width = max(1, Int(abs(rawRect?.width ?? 1280)))
            let height = max(1, Int(abs(rawRect?.height ?? 720)))
            return MediaItem(url: url, date: date, duration: duration, hasAudio: !asset.tracks(withMediaType: .audio).isEmpty, isImage: false, width: width, height: height, transcript: nil, speechSegments: [])
        }.sorted { $0.date < $1.date }
    }

    static func photoCaptureDate(_ url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: original)
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
        guard let folder = selectedFolder, mediaCount > 0, !isBusy else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vlog-\(folder.lastPathComponent).mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        guard panel.runModal() == .OK, let output = panel.url else { return }
        setBusy(true)
        openButton.isHidden = true
        revealButton.isHidden = true
        status.stringValue = "Generando vlog…"
        lastAnalysisStatus = "Análisis local"
        let started = Date()
        let tick = { [weak self] in
            self?.detail.stringValue = "Tiempo transcurrido: \(Self.formatDuration(Date().timeIntervalSince(started))) · con Whisper y Ollama puede tardar varios minutos. No cierres la ventana."
        }
        tick()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
        let useOllama = ollamaButton.state == .on
        let useWhisper = whisperButton.state == .on
        let whisperLanguage = selectedWhisperLanguage()
        let includeDateStamp = dateStampButton.state == .on
        let includeSummaryStamp = summaryStampButton.state == .on
        let targetDuration = Double(Self.durations[durationPopup.indexOfSelectedItem])
        let includePhotos = photosButton.state == .on
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report: (String) -> Void = { message in
                DispatchQueue.main.async {
                    if message.hasPrefix("Whisper") || message.hasPrefix("Ollama listo") || message.hasPrefix("Ollama no") {
                        self?.lastAnalysisStatus = message
                    }
                    self?.status.stringValue = message
                    if let self, let fraction = Self.progressFraction(for: message) {
                        self.progress.doubleValue = max(self.progress.doubleValue, fraction)
                    }
                }
            }
            do {
                let items = Self.scan(folder, includePhotos: includePhotos, update: report)
                guard !items.isEmpty else {
                    throw NSError(domain: "VlogForge", code: 4, userInfo: [NSLocalizedDescriptionKey: "Ningún vídeo ni foto se pudo leer (vídeos negros, vacíos o no descargados de Google Drive)."])
                }
                try Self.render(items: items, output: output, useOllama: useOllama, useWhisper: useWhisper, whisperLanguage: whisperLanguage, includeDateStamp: includeDateStamp, includeSummaryStamp: includeSummaryStamp, targetDuration: targetDuration, update: report)
                DispatchQueue.main.async { self?.finished(output: output, error: nil, elapsed: Date().timeIntervalSince(started)) }
            } catch { DispatchQueue.main.async { self?.finished(output: nil, error: error, elapsed: 0) } }
        }
    }

    private func selectedWhisperLanguage() -> String {
        switch whisperLanguagePopup.indexOfSelectedItem {
        case 1: return "auto"
        case 2: return "es"
        case 3: return "ca"
        case 4: return "en"
        case 5: return "zh"
        case 6: return "fr"
        case 7: return "it"
        case 8: return "pt"
        default: return "auto" // Català + castellano: detectar cambios de lengua.
        }
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        for control in [ollamaButton, whisperButton, dateStampButton, summaryStampButton, photosButton, durationPopup] as [NSControl] { control.isEnabled = !busy }
        whisperLanguagePopup.isEnabled = !busy && whisperButton.state == .on
        exportButton.isEnabled = !busy && mediaCount > 0
        exportButton.title = busy ? "Generando…" : "Generar vlog"
        dropView.alphaValue = busy ? 0.5 : 1
        progress.doubleValue = 0
        progress.alphaValue = busy ? 1 : 0
        spinner.isHidden = !busy
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    // ponytail: progress is parsed from render's "N de M" status messages;
    // thread a real progress callback through render if the phases change.
    static func progressFraction(for message: String) -> Double? {
        let phases: [(prefix: String, start: Double, end: Double)] = [
            ("Revisando archivo", 0.0, 0.10),
            ("Transcribiendo audio", 0.10, 0.30),
            ("Whisper", 0.30, 0.30),
            ("Analizando imagen y sonido", 0.30, 0.45),
            ("Ollama puntuando lote", 0.45, 0.75),
            ("Ollama", 0.75, 0.75),
            ("Eligiendo", 0.75, 0.75),
            ("Ollama buscando", 0.75, 0.75),
            ("Trama", 0.75, 0.75),
            ("Ollama escribiendo", 0.75, 0.75),
            ("Preparando salida", 0.75, 0.75),
            ("Normalizando plano", 0.75, 0.97),
            ("Uniendo planos", 0.97, 0.97)
        ]
        guard let phase = phases.first(where: { message.hasPrefix($0.prefix) }) else { return nil }
        let numbers = message.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        guard numbers.count >= 2, numbers[1] > 0 else { return phase.start }
        return phase.start + (phase.end - phase.start) * (numbers[0] - 1) / numbers[1]
    }

    private func finished(output: URL?, error: Error?, elapsed: Double) {
        ticker?.invalidate()
        ticker = nil
        setBusy(false)
        if let error {
            status.stringValue = "No se pudo generar el vlog."
            detail.stringValue = error.localizedDescription
            return
        }
        lastOutput = output
        status.stringValue = "Vlog listo en \(Self.formatDuration(elapsed)) · \(output?.lastPathComponent ?? "")"
        detail.stringValue = lastAnalysisStatus
        openButton.isHidden = false
        revealButton.isHidden = false
    }

    @objc private func openOutput() {
        if let lastOutput { NSWorkspace.shared.open(lastOutput) }
    }

    @objc private func revealOutput() {
        if let lastOutput { NSWorkspace.shared.activateFileViewerSelecting([lastOutput]) }
    }

    static func render(items: [MediaItem], output: URL, useOllama: Bool = false, useWhisper: Bool = false, whisperLanguage: String = "auto", includeDateStamp: Bool = true, includeSummaryStamp: Bool = true, targetDuration: Double = 120, update: @escaping (String) -> Void) throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("vlogforge-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let enrichedItems = useWhisper ? transcribe(items, language: whisperLanguage, update: update) : items
        let selected = selectMoments(enrichedItems, useOllama: useOllama, targetDuration: targetDuration, update: update)
        let canvas = outputCanvas(for: items)
        update("Preparando salida \(canvas.width)×\(canvas.height)…")
        var clipPaths: [URL] = []
        for (index, segment) in selected.enumerated() {
            let item = segment.item
            update("Normalizando plano \(index + 1) de \(selected.count)" + (includeSummaryStamp ? segment.summary.map { " · «\($0)»" } ?? "" : "") + "…")
            let clip = temp.appendingPathComponent(String(format: "clip-%03d.mp4", index))
            let start = segment.start
            let length = segment.length
            var args = ["-y"]
            if item.isImage {
                args += ["-loop", "1", "-framerate", "30", "-i", item.url.path]
            } else {
                // -ss must precede its -i: placed after it, FFmpeg applied it
                // to the next input and every clip started at 0. Input
                // seeking is frame-accurate when re-encoding.
                args += ["-ss", String(start), "-i", item.url.path]
            }
            if !item.hasAudio { args += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"] }
            let stamp = includeDateStamp ? Self.timestamp(for: item.date) : ""
            let stampImage = temp.appendingPathComponent(String(format: "stamp-%03d.png", index))
            // AppKit drawing must happen on the main thread. Rendering runs
            // in the background, so doing this directly could create a fully
            // transparent PNG even though the render reported success.
            if Thread.isMainThread {
                try makeTimestampOverlay(stamp, summary: includeSummaryStamp ? segment.summary : nil, at: stampImage, width: canvas.width, height: canvas.height)
            } else {
                var overlayError: Error?
                DispatchQueue.main.sync {
                    do {
                        try makeTimestampOverlay(stamp, summary: includeSummaryStamp ? segment.summary : nil, at: stampImage, width: canvas.width, height: canvas.height)
                    } catch {
                        overlayError = error
                    }
                }
                if let overlayError { throw overlayError }
            }
            let audioIndex = item.hasAudio ? "0:a:0" : "1:a:0"
            let stampIndex = item.hasAudio ? "1" : "2"
            args += ["-loop", "1", "-i", stampImage.path]
            let filter = "[0:v]scale=\(canvas.width):\(canvas.height):force_original_aspect_ratio=decrease,pad=\(canvas.width):\(canvas.height):(ow-iw)/2:(oh-ih)/2,setsar=1[base];[base][\(stampIndex):v]overlay=0:0:shortest=1,format=yuv420p[v]"
            args += ["-t", String(length), "-filter_complex", filter, "-map", "[v]", "-map", audioIndex, "-r", "30", "-c:v", "libx264", "-preset", "medium", "-crf", "24", "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2", "-shortest"]
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
                return MediaItem(url: item.url, date: item.date, duration: item.duration, hasAudio: item.hasAudio, isImage: false, width: item.width, height: item.height, transcript: text.isEmpty ? nil : text, speechSegments: segments)
            } catch {
                return item
            }
        }
        update("Whisper listo (modelo \(URL(fileURLWithPath: model).lastPathComponent)): \(succeeded) de \(items.filter { !$0.isImage }.count) vídeos transcritos.")
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
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-large-v3-turbo.bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-large-v3-q5_0.bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-large-v3.bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-medium-q5_0.bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-medium.bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-small.bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("whisper.cpp/models/ggml-base.bin").path,
            "/opt/homebrew/share/whisper.cpp/ggml-large-v3-turbo-q5_0.bin",
            "/opt/homebrew/share/whisper.cpp/ggml-large-v3.bin",
            "/opt/homebrew/share/whisper.cpp/ggml-medium.bin",
            "/opt/homebrew/share/whisper.cpp/ggml-small.bin",
            "/opt/homebrew/share/whisper.cpp/ggml-base.bin"
        ]
        return paths.first(where: { FileManager.default.isReadableFile(atPath: $0) })
    }

    static func runWhisper(whisper: String, model: String, language: String, audio: URL, outputBase: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: whisper)
        // Keep timestamps in every output format; the edit depends on them
        // to preserve complete spoken phrases.
        var arguments = ["-m", model, "-l", language, "-f", audio.path, "-otxt", "-oj", "-of", outputBase.path, "-np", "-bs", "5", "-bo", "5", "-tp", "0"]
        // The prompt primes Whisper to write laughs/crying as marks, which
        // the moment selection uses to find the emotional moments.
        switch language {
        case "auto": arguments += ["--prompt", "Transcripción natural en catalán y castellano. Conserva nombres propios y frases completas. (risas)"]
        case "es", "ca": arguments += ["--prompt", "Conserva nombres propios y frases completas. (risas)"]
        default: break
        }
        task.arguments = arguments
        // Output goes to files (-otxt/-oj); an unread pipe would deadlock.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
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

    struct Candidate {
        let source: Int
        var segment: EditSegment
        let said: String
        let loudness: Double // peak loudness above the file's median, in dB
        let localScore: Double
    }

    /// Picks the most interesting moments up to `targetDuration` seconds.
    /// Ollama (when available) rates every candidate 1–10 from a contact
    /// sheet plus transcripts; otherwise speech, loudness and brightness decide.
    static func selectMoments(_ items: [MediaItem], useOllama: Bool, targetDuration: Double, update: ((String) -> Void)?) -> [EditSegment] {
        var candidates = buildCandidates(items, update: update)
        guard !candidates.isEmpty else { return [] }
        let ratings = useOllama ? OllamaClient.rate(candidates, update: update) : nil
        // With every moment described, the big model works out the day's
        // main plot and classifies each moment (laugh, emotion, milestone,
        // technical chatter…), so the edit keeps what matters to remember.
        var story: OllamaClient.Story?
        if let ratings {
            update?("Ollama buscando la trama principal…")
            let moments = candidates.indices.compactMap { index -> [String: Any]? in
                guard let description = ratings[index]?.description else { return nil }
                var entry: [String: Any] = ["id": index, "archivo": candidates[index].source + 1, "hora": timestamp(for: candidates[index].segment.item.date), "que_pasa": description]
                if !candidates[index].said.isEmpty { entry["se_dice"] = String(candidates[index].said.prefix(200)) }
                if candidates[index].loudness > 8 { entry["sonido"] = "más alto de lo normal" }
                return entry
            }
            story = OllamaClient.story(moments)
            if let story { update?("Trama del vlog: \(story.plot)") }
        }
        var excluded = Set<Int>()
        for index in candidates.indices {
            let local = candidates[index].localScore
            let segment = candidates[index].segment
            let rating = ratings?[index]
            var score = rating.map { $0.interest / 10 * 0.75 + local * 0.25 } ?? local
            if let interest = rating?.interest, let story, let relevance = story.relevance[index] {
                let kind = story.kind[index] ?? "contexto"
                if ["tecnico", "relleno"].contains(kind) { excluded.insert(index) }
                score = interest / 10 * 0.3 + relevance / 10 * 0.3 + local * 0.1 + (OllamaClient.kindBonus[kind] ?? 0)
            }
            candidates[index].segment = EditSegment(item: segment.item, start: segment.start, length: segment.length, score: score, summary: rating?.description)
        }
        update?(excluded.isEmpty ? "Eligiendo los mejores momentos…" : "Eligiendo los mejores momentos (descartados \(excluded.count) técnicos o de relleno)…")
        var chosen: [EditSegment] = []
        var total = 0.0
        var perSource: [URL: Int] = [:]
        for index in candidates.indices.sorted(by: { candidates[$0].segment.score > candidates[$1].segment.score }) {
            guard total < targetDuration else { break }
            let segment = candidates[index].segment
            if excluded.contains(index) { continue } // technical talk or filler: not worth remembering
            if let interest = ratings?[index]?.interest, interest <= 3 { continue } // unwatchable or empty shot
            guard perSource[segment.item.url, default: 0] < 3, total + segment.length <= targetDuration + 4 else { continue }
            chosen.append(segment)
            total += segment.length
            perSource[segment.item.url, default: 0] += 1
        }
        if chosen.isEmpty, let best = candidates.max(by: { $0.segment.score < $1.segment.score }) { chosen = [best.segment] }
        chosen.sort { ($0.item.date, $0.start) < ($1.item.date, $1.start) }
        // One caption per source video, summarising the whole file in the
        // context of the plot; every clip cut from that file shows it.
        var captions: [URL: String] = [:]
        if ratings != nil {
            update?("Ollama escribiendo un texto por vídeo…")
            var files: [[String: Any]] = []
            for url in chosen.map(\.item.url) where !files.contains(where: { ($0["url"] as? URL) == url }) {
                guard let first = candidates.first(where: { $0.segment.item.url == url }) else { continue }
                let moments = candidates.indices.filter { candidates[$0].segment.item.url == url }.compactMap { index -> String? in
                    guard let description = ratings?[index]?.description else { return nil }
                    return story?.kind[index].map { "[\($0)] \(description)" } ?? description
                }
                var entry: [String: Any] = ["url": url, "archivo": first.source + 1, "hora": timestamp(for: first.segment.item.date), "momentos": moments]
                if first.segment.item.isImage { entry["es_foto"] = true }
                if let transcript = first.segment.item.transcript, !transcript.isEmpty { entry["todo_lo_que_se_dice"] = String(transcript.prefix(1200)) }
                files.append(entry)
            }
            captions = OllamaClient.fileCaptions(files, plot: story?.plot) ?? [:]
            // Models occasionally skip a file; ask again just for those.
            let missing = files.filter { ($0["url"] as? URL).map { captions[$0] == nil } ?? false }
            if !missing.isEmpty { captions.merge(OllamaClient.fileCaptions(missing, plot: story?.plot) ?? [:]) { old, _ in old } }
        }
        return chosen.map { EditSegment(item: $0.item, start: $0.start, length: $0.length, score: $0.score, summary: captions[$0.item.url]) }
    }

    static func buildCandidates(_ items: [MediaItem], update: ((String) -> Void)?) -> [Candidate] {
        var all: [Candidate] = []
        for (index, item) in items.enumerated() {
            if item.isImage {
                all.append(Candidate(source: index, segment: EditSegment(item: item, start: 0, length: 3, score: 0, summary: nil), said: "", loudness: 0, localScore: 0.35))
                continue
            }
            update?("Analizando imagen y sonido \(index + 1) de \(items.count)…")
            let signals = analyzeSignals(item.url)
            let audible = signals.loudness.values.filter { $0 > -70 }.sorted()
            let medianLoudness = audible.isEmpty ? -30 : audible[audible.count / 2]
            // Every spoken phrase whole (neighbours merged, max 12 s), then
            // fixed 5 s windows over whatever is left.
            var windows: [(start: Double, end: Double)] = []
            for speech in item.speechSegments {
                let start = max(0, speech.start - 0.4), end = min(item.duration, speech.end + 0.4)
                if let last = windows.last, start - last.end < 0.8, end - last.start <= 12 {
                    windows[windows.count - 1].end = end
                } else {
                    windows.append((start, min(end, start + 12)))
                }
            }
            var cursor = 0.0
            while cursor < item.duration - 1.2 {
                let end = min(item.duration, cursor + 5)
                if !windows.contains(where: { $0.start < end && cursor < $0.end }) { windows.append((cursor, end)) }
                cursor += 5
            }
            var local: [Candidate] = []
            for window in windows where window.end - window.start >= 1.2 {
                let seconds = Int(window.start)...max(Int(window.start), Int(window.end) - 1)
                let said = item.speechSegments.filter { $0.end > window.start && $0.start < window.end }.map(\.text).joined(separator: " ")
                let relative = (seconds.compactMap { signals.loudness[$0] }.max() ?? -120) - medianLoudness
                let brightness = seconds.compactMap { signals.brightness[$0] }
                var score = said.isEmpty ? 0.2 : 0.55 + min(0.15, Double(said.count) / 400)
                score += max(-0.1, min(0.25, relative / 24)) // laughs, shouts, cheering
                if ["risa", "riure", "rialles", "jaja", "jeje", "haha", "llor", "plor"].contains(where: said.lowercased().contains) { score += 0.3 } // Whisper laugh/cry marks
                if !brightness.isEmpty, brightness.reduce(0, +) / Double(brightness.count) < 35 { score -= 0.4 } // too dark
                let segment = EditSegment(item: item, start: window.start, length: window.end - window.start, score: score, summary: nil)
                local.append(Candidate(source: index, segment: segment, said: said, loudness: relative, localScore: score))
            }
            // Shortlist per file so Ollama's work stays bounded: about one
            // candidate per 15 s of footage, between 2 and 6.
            let keep = max(2, min(6, Int(item.duration / 15) + 1))
            all += local.sorted { $0.localScore > $1.localScore }.prefix(keep)
        }
        return all
    }

    /// Per-second brightness (YAVG) and peak momentary loudness (LUFS) in one FFmpeg pass.
    static func analyzeSignals(_ url: URL) -> (brightness: [Int: Double], loudness: [Int: Double]) {
        guard let output = try? runFFmpegCapture(["-hide_banner", "-nostdin", "-i", url.path, "-vf", "fps=1,scale=160:-2,signalstats,metadata=mode=print", "-af", "ebur128", "-f", "null", "-"]) else { return ([:], [:]) }
        func number(after marker: String, in line: Substring) -> Double? {
            guard let range = line.range(of: marker) else { return nil }
            return Double(line[range.upperBound...].drop(while: { $0 == " " }).prefix(while: { !$0.isWhitespace }))
        }
        var brightness: [Int: Double] = [:], loudness: [Int: Double] = [:]
        var second = 0
        for line in output.split(separator: "\n") {
            if let time = number(after: "pts_time:", in: line) {
                second = Int(time)
            } else if let value = number(after: "signalstats.YAVG=", in: line) {
                brightness[second] = value
            } else if let time = number(after: "] t:", in: line), let value = number(after: " M:", in: line) {
                loudness[Int(time)] = max(loudness[Int(time)] ?? -120, value)
            }
        }
        return (brightness, loudness)
    }

    enum OllamaClient {
        /// Rates candidates (indexes into `candidates`) with interest 1–10 and
        /// a short title. Batches of 12 keep each request well under a minute.
        static func rate(_ candidates: [Candidate], update: ((String) -> Void)?) -> [Int: (interest: Double, description: String?)]? {
            guard let modelInfo = availableModel() else {
                update?("Ollama no está disponible; se usará el análisis local.")
                return nil
            }
            let batches = stride(from: 0, to: candidates.count, by: 12).map { Array($0..<min($0 + 12, candidates.count)) }
            var ratings: [Int: (interest: Double, description: String?)] = [:]
            for (number, ids) in batches.enumerated() {
                update?("Ollama puntuando lote \(number + 1) de \(batches.count)…")
                let batch = ids.map { candidates[$0] }
                for (local, rating) in rateBatch(batch, model: modelInfo) ?? [:] where local < ids.count {
                    ratings[ids[local]] = rating
                }
            }
            guard !ratings.isEmpty else {
                update?("Ollama no respondió; se usará el análisis local.")
                return nil
            }
            update?("Ollama listo: ha puntuado \(ratings.count) de \(candidates.count) momentos.")
            return ratings
        }

        private static func rateBatch(_ batch: [Candidate], model: (name: String, isVision: Bool)) -> [Int: (interest: Double, description: String?)]? {
            var describedSources = Set<Int>()
            let described = batch.enumerated().map { id, candidate -> [String: Any] in
                let segment = candidate.segment
                var entry: [String: Any] = [
                    "id": id,
                    "archivo": candidate.source + 1,
                    "hora": timestamp(for: segment.item.date),
                    "inicio_s": Int(segment.start),
                    "duracion_s": Int(segment.length.rounded())
                ]
                if segment.item.isImage { entry["es_foto"] = true }
                if !candidate.said.isEmpty { entry["se_dice"] = String(candidate.said.prefix(400)) }
                if candidate.loudness > 8 { entry["sonido"] = "más alto de lo normal: posible risa, grito o reacción" }
                if describedSources.insert(candidate.source).inserted, let transcript = segment.item.transcript, !transcript.isEmpty {
                    entry["todo_lo_que_se_dice_en_el_archivo"] = String(transcript.prefix(1500))
                }
                return entry
            }
            let sheetNote = model.isVision ? "La imagen adjunta es una hoja de contactos: cada celda muestra el inicio, el medio y el final de un candidato y lleva su id en la esquina. " : ""
            let prompt = """
            Eres un editor de vlogs. Estos son momentos candidatos de los vídeos de un mismo día, en orden cronológico. \(sheetNote)Puntúa CADA candidato con "interes" de 1 a 10 según lo que aporta a un vlog corto:
            9-10: momentos clave: llegar a un sitio, una sorpresa o regalo, risas o reacciones fuertes, alguien contando algo con sentido a cámara, un momento emotivo o una celebración, un paisaje espectacular.
            5-8: contexto útil y agradable de ver.
            1-4: relleno: imagen borrosa o muy movida, cámara apuntando al suelo, a la ropa o a un bolsillo, oscuridad, esperas, caminar o conducir sin que pase nada, planos repetidos, frases sueltas sin sentido, hablar de la cámara o de detalles técnicos.
            Usa se_dice y todo_lo_que_se_dice_en_el_archivo para entender lo que ocurre (pueden incluir marcas como (risas)). Añade "que_pasa": una descripción objetiva en castellano de 8 a 20 palabras de lo que se ve y se dice: quién, qué hace, dónde y, sobre todo, la emoción que se ve u oye (se ríen, lloran, se abrazan, gritan de alegría, bromean, están nerviosos). No inventes nombres que no aparezcan en lo que se dice.
            Devuelve solo JSON: {"momentos":[{"id":0,"interes":7,"que_pasa":"..."}]} con todos los ids.
            Candidatos: \(jsonString(described))
            """
            var payload: [String: Any] = [
                "model": model.name,
                "stream": false,
                "format": "json",
                // think=false: reasoning only adds minutes here. num_ctx: the
                // model default (128k) needs ~25 GB; a batch fits in 32k.
                "think": false,
                "options": ["temperature": 0, "top_p": 0.2, "num_ctx": 32768],
                "prompt": prompt
            ]
            if model.isVision, let sheet = contactSheet(for: batch.map(\.segment)) { payload["images"] = [sheet] }
            guard let body = try? JSONSerialization.data(withJSONObject: payload),
                  let response = post(body: body),
                  let outer = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                  // Thinking models (qwen3-vl) with format=json return the
                  // answer in "thinking" and leave "response" empty.
                  let text = [outer["response"], outer["thinking"]].compactMap({ $0 as? String }).first(where: { !$0.isEmpty }),
                  let moments = parseJSONObject(text)?["momentos"] as? [[String: Any]] else { return nil }
            var ratings: [Int: (interest: Double, description: String?)] = [:]
            for moment in moments {
                guard let id = (moment["id"] as? NSNumber)?.intValue, let interest = (moment["interes"] as? NSNumber)?.doubleValue else { continue }
                let description = (moment["que_pasa"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ratings[id] = (min(10, max(1, interest)), description.flatMap { $0.isEmpty ? nil : String($0.prefix(200)) })
            }
            return ratings
        }

        struct Story {
            let plot: String
            let relevance: [Int: Double]
            let kind: [Int: String]
        }

        /// Score bonus per moment type: feelings, silliness and plot
        /// milestones are what people want to remember.
        static let kindBonus: [String: Double] = ["risa": 0.3, "emocion": 0.3, "tonteria": 0.25, "hito": 0.25, "recapitulacion": 0.2]

        /// Text-only pass with the biggest model: states the day's main plot
        /// from every described moment, classifies each one and rates (1–10)
        /// how much it helps tell the story.
        static func story(_ moments: [[String: Any]]) -> Story? {
            guard let model = captionModel(), !moments.isEmpty else { return nil }
            let prompt = """
            Eres el editor de un vlog de recuerdos de un grupo de amigos. Estos son todos los momentos grabados en un día, en orden, con lo que se ve y lo que se dice. Las transcripciones pueden incluir marcas como (risas).
            1. Escribe en "trama" la historia principal del día en una o dos frases: cuál es el plan u objetivo, qué pasa por el camino y cómo acaba. Céntrate en el hilo que conecta más momentos.
            2. Para CADA momento indica "tipo", uno de:
               "risa": alguien se ríe de verdad o hay un momento muy gracioso.
               "emocion": llanto, abrazos, sorpresa, nervios, alegría intensa.
               "tonteria": bromas, payasadas, frases absurdas, el grupo haciendo el tonto.
               "hito": momento clave de la historia: alguien llega o viene por primera vez, llegamos al destino o a la misión, empieza o termina el plan.
               "recapitulacion": contamos qué tal ha ido, conclusiones, valoración del día.
               "contexto": situa dónde estamos o qué hacemos, sin más.
               "tecnico": se habla de la cámara, de grabar, de ajustes, de batería o de pruebas técnicas; no importa para la historia ni para recordarlo.
               "relleno": esperas, trayectos o planos donde no pasa nada.
            3. Para CADA momento da "relevancia" de 1 a 10: cuánto ayuda a contar la trama o a recordar el día (las risas, emociones y tonterías también cuentan como recuerdos valiosos).
            Devuelve solo JSON: {"trama":"...","momentos":[{"id":0,"tipo":"risa","relevancia":7}]} con todos los ids.
            Momentos: \(jsonString(Array(moments.prefix(250))))
            """
            guard let answer = ask(model: model, prompt: prompt, temperature: 0.2),
                  let plot = answer["trama"] as? String, !plot.isEmpty else { return nil }
            var relevance: [Int: Double] = [:], kind: [Int: String] = [:]
            for moment in answer["momentos"] as? [[String: Any]] ?? [] {
                guard let id = (moment["id"] as? NSNumber)?.intValue else { continue }
                if let value = (moment["relevancia"] as? NSNumber)?.doubleValue { relevance[id] = min(10, max(1, value)) }
                // Normalise accents/case: models write "Técnico", "emoción"…
                if let type = moment["tipo"] as? String { kind[id] = type.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }
            }
            return Story(plot: plot, relevance: relevance, kind: kind)
        }

        private static func ask(model: String, prompt: String, temperature: Double) -> [String: Any]? {
            let payload: [String: Any] = [
                "model": model, "stream": false, "format": "json", "think": false,
                "options": ["temperature": temperature, "top_p": 0.9, "num_ctx": 32768],
                "prompt": prompt
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: payload),
                  let response = post(body: body),
                  let outer = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
                  let text = [outer["response"], outer["thinking"]].compactMap({ $0 as? String }).first(where: { !$0.isEmpty }) else { return nil }
            return parseJSONObject(text)
        }

        /// One on-screen text per source video: what happens in that whole
        /// file, told as a step of the day's plot.
        static func fileCaptions(_ files: [[String: Any]], plot: String?) -> [URL: String]? {
            guard let model = captionModel(), !files.isEmpty else { return nil }
            let described = files.map { $0.filter { $0.key != "url" } }
            let prompt = """
            Eres el guionista de un vlog de recuerdos de un grupo de amigos. La trama principal del día es: \(plot ?? "dedúcela de los vídeos").
            Cada archivo es un vídeo del día; del vlog se muestran trozos de él y sobre ellos aparece un texto. Escribe para cada archivo un "texto" de 3 a 9 palabras que resuma lo que pasa en ESE vídeo entero (usa todo_lo_que_se_dice y la lista de momentos), para que quien lo vea entienda el contexto completo del clip dentro de la historia del día.
            Tono de vlog desenfadado: puede tener gracia o ironía cuando el momento lo pida (risas, tonterías, algo que sale mal), pero lo primero es que se entienda qué está pasando. Los textos seguidos deben leerse como la historia del día.
            Reglas: no copies frases dichas; no inventes hechos ni nombres que no aparezcan en lo que se dice; no menciones la cámara ni detalles técnicos; cada texto distinto; como mucho un emoji y solo en algunos; en castellano, o en catalán si en ese vídeo se habla catalán.
            Devuelve solo JSON: {"textos":[{"archivo":1,"texto":"..."}]} con todos los archivos.
            Archivos: \(jsonString(described))
            """
            guard let texts = ask(model: model, prompt: prompt, temperature: 0.6)?["textos"] as? [[String: Any]] else { return nil }
            var result: [URL: String] = [:]
            for entry in texts {
                // Models sometimes return the number as a string ("3").
                guard let number = (entry["archivo"] as? NSNumber)?.intValue ?? (entry["archivo"] as? String).flatMap({ Int($0.filter(\.isNumber)) }),
                      let file = files.first(where: { ($0["archivo"] as? Int) == number }), let url = file["url"] as? URL,
                      let text = (entry["texto"] as? String)?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'«»."))),
                      !text.isEmpty, text.count <= 90 else { continue }
                result[url] = text
            }
            return result
        }

        /// Writing and story need a bigger model than rating does, and no vision: use
        /// the largest installed model (or VLOGFORGE_CAPTION_MODEL).
        static func captionModel() -> String? {
            guard let data = get(path: "/api/tags"), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let models = object["models"] as? [[String: Any]] else { return nil }
            let names = models.compactMap { $0["name"] as? String }
            if let preferred = ProcessInfo.processInfo.environment["VLOGFORGE_CAPTION_MODEL"], names.contains(preferred) { return preferred }
            return models.max { ($0["size"] as? NSNumber)?.int64Value ?? 0 < ($1["size"] as? NSNumber)?.int64Value ?? 0 }?["name"] as? String
        }

        static func availableModel() -> (name: String, isVision: Bool)? {
            let preferred = ProcessInfo.processInfo.environment["VLOGFORGE_OLLAMA_MODEL"]
            guard let data = get(path: "/api/tags"), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let models = object["models"] as? [[String: Any]] else { return nil }
            let names = models.compactMap { $0["name"] as? String }
            if let preferred, names.contains(preferred) { return (preferred, isVision(preferred)) }
            let vision = names.first { name in
                let lower = name.lowercased()
                return lower.contains("vision") || lower.contains("llava") || lower.contains("qwen2.5vl") || lower.contains("qwen3-vl") || lower.contains("gemma3")
            }
            if let vision { return (vision, true) }
            return names.first.map { ($0, false) }
        }

        private static func isVision(_ name: String) -> Bool {
            let lower = name.lowercased()
            return lower.contains("vision") || lower.contains("llava") || lower.contains("qwen2.5vl") || lower.contains("qwen3-vl") || lower.contains("gemma3")
        }

        // One labelled contact sheet per batch: qwen3-vl spends ~1000 tokens
        // (~13 s) per image regardless of size, so separate frames per
        // candidate blew the request timeout. Each cell shows start, middle
        // and end so the model can spot shaky, blurry or empty shots.
        private static func contactSheet(for segments: [EditSegment]) -> String? {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vlogforge-ollama-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let frameWidth = 240, frameHeight = 135, cellWidth = frameWidth * 3 + 8
            let columns = min(2, segments.count), rows = (segments.count + columns - 1) / columns
            guard columns > 0, let context = CGContext(data: nil, width: columns * cellWidth, height: rows * frameHeight, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.setFillColor(CGColor(gray: 0.15, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 26, nil)
            for (position, segment) in segments.enumerated() {
                // CoreGraphics' origin is bottom-left; fill cells top-left first.
                let x = (position % columns) * cellWidth, y = (rows - 1 - position / columns) * frameHeight
                for (slot, fraction) in [0.15, 0.5, 0.85].enumerated() {
                    let frame = directory.appendingPathComponent("frame-\(position)-\(slot).jpg")
                    // No -ss for photos: FFmpeg 9 outputs nothing when seeking a still image.
                    let seek = segment.item.isImage ? [] : ["-ss", String(segment.start + segment.length * fraction)]
                    guard (try? AppDelegate.runFFmpeg(["-y"] + seek + ["-i", segment.item.url.path, "-frames:v", "1", "-vf", "scale=\(frameWidth):\(frameHeight):force_original_aspect_ratio=decrease,pad=\(frameWidth):\(frameHeight):(ow-iw)/2:(oh-ih)/2", "-q:v", "6", frame.path])) != nil,
                          let source = CGImageSourceCreateWithURL(frame as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                    context.draw(image, in: CGRect(x: x + slot * frameWidth, y: y, width: frameWidth, height: frameHeight))
                }
                let text = NSAttributedString(string: "\(position)", attributes: [.font: font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)])
                let line = CTLineCreateWithAttributedString(text)
                let labelWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
                context.setFillColor(CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 0.9))
                context.fill(CGRect(x: CGFloat(x), y: CGFloat(y + frameHeight - 34), width: labelWidth + 14, height: 34))
                context.textPosition = CGPoint(x: CGFloat(x + 7), y: CGFloat(y + frameHeight - 26))
                CTLineDraw(line, context)
            }
            guard let sheet = context.makeImage() else { return nil }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, sheet, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return (data as Data).base64EncodedString()
        }

        private static func post(body: Data) -> Data? {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/generate")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            request.timeoutInterval = 300 // first request also loads the model
            let semaphore = DispatchSemaphore(value: 0)
            var result: Data?
            URLSession.shared.dataTask(with: request) { data, _, _ in result = data; semaphore.signal() }.resume()
            _ = semaphore.wait(timeout: .now() + 305)
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

    static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy  HH:mm"
        return formatter.string(from: date)
    }

    static func outputCanvas(for items: [MediaItem]) -> (width: Int, height: Int) {
        // Photos (often 12+ MP) must not dictate the video size.
        let videos = items.filter { !$0.isImage }
        let best = (videos.isEmpty ? items : videos).max { ($0.width * $0.height) < ($1.width * $1.height) }
        let width = max(2, best?.width ?? 1280)
        let height = max(2, best?.height ?? 720)
        return (width % 2 == 0 ? width : width - 1, height % 2 == 0 ? height : height - 1)
    }

    static func makeTimestampOverlay(_ text: String, summary: String?, at url: URL, width: Int, height: Int) throws {
        // Build the bitmap explicitly instead of relying on NSImage.lockFocus.
        // The latter can produce an apparently valid but transparent image
        // when the render is launched from a background worker.
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "VlogForge", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear la capa de texto."])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let hasSummary = !(summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let textScale = min(2.0, max(0.75, CGFloat(width) / 1280.0))
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.82)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 1.5, height: -1.5)
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: (hasSummary ? 17 : 22) * textScale, weight: .medium),
            .foregroundColor: NSColor.white,
            .shadow: shadow
        ]
        if !text.isEmpty { (text as NSString).draw(at: NSPoint(x: 28 * textScale, y: (hasSummary ? 55 : 25) * textScale), withAttributes: dateAttributes) }
        if let summary, hasSummary {
            let summaryAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 24 * textScale, weight: .semibold),
                .foregroundColor: NSColor.white,
                .shadow: shadow
            ]
            (summary as NSString).draw(at: NSPoint(x: 28 * textScale, y: 19 * textScale), withAttributes: summaryAttributes)
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw NSError(domain: "VlogForge", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear la fecha del plano."])
        }
        try png.write(to: url)
    }

    static func runFFmpeg(_ args: [String]) throws {
        _ = try runFFmpegCapture(["-nostdin"] + args)
    }

    static func runFFmpegCapture(_ args: [String]) throws -> String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw NSError(domain: "VlogForge", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se encontró FFmpeg. Instálalo con Homebrew: brew install ffmpeg"]) }
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args
        let pipe = Pipe(); task.standardError = pipe; task.standardOutput = pipe
        try task.run()
        // Drain before waiting: an unread pipe fills up and FFmpeg blocks forever.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard task.terminationStatus == 0 else {
            let tail = output.split(separator: "\n").suffix(3).joined(separator: " · ")
            throw NSError(domain: "VlogForge", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "FFmpeg no pudo procesar uno de los clips: \(tail)"])
        }
        return output
    }
}

if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--self-test" {
    let folder = URL(fileURLWithPath: CommandLine.arguments[2])
    let useAI = CommandLine.arguments.dropFirst(3).contains("--ai")
    let items = AppDelegate.scan(folder)
    guard !items.isEmpty else { print("SELF-TEST: no compatible videos"); exit(2) }
    let output = folder.appendingPathComponent("vlogforge-self-test.mp4")
    do {
        try AppDelegate.render(items: items, output: output, useOllama: useAI, useWhisper: useAI) { print($0) }
        print("SELF-TEST: created \(output.path)")
    } catch { print("SELF-TEST: failed: \(error.localizedDescription)"); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
