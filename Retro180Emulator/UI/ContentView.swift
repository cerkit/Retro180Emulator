internal import AVFAudio
import AppKit
import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var motherboard = Motherboard()
    @StateObject var terminalVM = TerminalViewModel()
    @State private var showingFileImporter = false
    @State private var xmodem: XMODEM?
    @State private var showingSpeechDialog = false
    @State private var speechInput = "Hello World"

    // Recording State
    @State private var isRecording = false
    @State private var recordedAudioURL: URL?
    @State private var showingSavePanel = false

    var body: some View {
        VStack {
            TerminalView(
                viewModel: terminalVM,
                onKey: { key in
                    motherboard.sendToCPU(key)
                }
            )
            .frame(width: 800, height: 480)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button(action: {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            motherboard.pasteText(clipboardString)
                        }
                    }) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .help("Paste text from system clipboard")

                    Button(action: {
                        showingFileImporter = true
                    }) {
                        Label("Upload", systemImage: "arrow.up.doc")
                    }
                    .help("Upload binary file using XMODEM")

                    Button(action: {
                        showingSpeechDialog = true
                    }) {
                        Label("Speech Tool", systemImage: "waveform")
                    }
                    .help("Open Speech Synthesis BASIC Generator")

                    Button(action: {
                        motherboard.reset()
                        terminalVM.grid = Array(
                            repeating: Array(repeating: " ", count: 80), count: 25)
                        terminalVM.cursorRow = 0
                        terminalVM.cursorCol = 0
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .help("Reset emulator and reload ROM")

                    Button(action: toggleRecording) {
                        Label(
                            "Record",
                            systemImage: isRecording ? "record.circle.fill" : "record.circle")
                    }
                    .help("Record speech output to WAV file")
                    .tint(isRecording ? .red : .primary)
                }
            }

            HStack {
                Text("Status: \(motherboard.cpu.halted ? "Halted" : "Running")")
                Spacer()
                Text("Cycles: \(motherboard.cpu.cycles)")
            }
            .padding()
            .font(.caption)
        }
        .onReceive(motherboard.$terminalOutput) { data in
            if !data.isEmpty {
                print("ContentView: Received \(data.count) bytes of terminal data")
                for byte in data {
                    // Pass the byte to the XMODEM handler if a transfer is active
                    xmodem?.handleByte(byte)

                    terminalVM.putChar(Character(UnicodeScalar(byte)))
                }
                motherboard.clearTerminalOutput()
            }
        }
        .onAppear {
            motherboard.start()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            do {
                if let fileUrl = try result.get().first {
                    if fileUrl.startAccessingSecurityScopedResource() {
                        let data = try Data(contentsOf: fileUrl)
                        startUpload(data: data)
                        fileUrl.stopAccessingSecurityScopedResource()
                    }
                }
            } catch {
                print("File import failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showingSpeechDialog) {
            VStack(spacing: 20) {
                Text("Speech Tool: SPEAK")
                    .font(.headline)

                Text("Enter text to speak (e.g. 'Hello World'):")
                    .font(.caption)

                TextEditor(text: $speechInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.5)))

                Picker(
                    "Voice",
                    selection: Binding(
                        get: { motherboard.speechDevice.currentVoiceIdentifier },
                        set: { motherboard.speechDevice.currentVoiceIdentifier = $0 }
                    )
                ) {
                    ForEach(motherboard.speechDevice.availableVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Cancel") { showingSpeechDialog = false }
                    Button("Generate & Run") {
                        let program = generateBasicSpeech(from: speechInput)
                        motherboard.pasteText(program)
                        showingSpeechDialog = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 400, height: 400)
        }
        .fileExporter(
            isPresented: $showingSavePanel,
            document: recordedAudioURL.map { SoundFileDocument(url: $0) },
            contentType: .wav,
            defaultFilename: "speech_recording"
        ) { result in
            if case .success = result {
                print("File saved successfully")
            }
        }
    }

    func startUpload(data: Data) {
        // Keep a reference to the XMODEM object so it can process events
        self.xmodem = XMODEM(data: data) { [weak motherboard] event in
            switch event {
            case .sendByte(let byte):
                motherboard?.sendToCPU(byte)
            case .complete:
                print("Upload complete")
                self.xmodem = nil
            case .error(let msg):
                print("Upload error: \(msg)")
                self.xmodem = nil
            }
        }
    }

    func generateBasicSpeech(from input: String) -> String {
        let cleanInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "'")

        if cleanInput.isEmpty { return "" }

        // Chunking output to avoid BASIC line length limits
        let chunkSize = 60
        var chunks: [String] = []
        var startIndex = cleanInput.startIndex

        while startIndex < cleanInput.endIndex {
            let endIndex =
                cleanInput.index(startIndex, offsetBy: chunkSize, limitedBy: cleanInput.endIndex)
                ?? cleanInput.endIndex
            chunks.append(String(cleanInput[startIndex..<endIndex]))
            startIndex = endIndex
        }

        // Generate BASIC program using GOSUB for efficiency
        var program = "10 REM SPEECH\r"
        var lineNum = 20

        for chunk in chunks {
            program += "\(lineNum) S$=\"\(chunk)\"\r"
            lineNum += 10
            program += "\(lineNum) GOSUB 1000\r"
            lineNum += 10
        }

        program += "\(lineNum) OUT 80,13\r"  // Trigger speech
        program += "\(lineNum + 10) END\r"

        // Output Subroutine
        program += "1000 FOR I=1 TO LEN(S$):OUT 80,ASC(MID$(S$,I,1)):NEXT:RETURN\r"

        // Auto-run
        program += "RUN\r"

        return program
    }

    func toggleRecording() {
        if isRecording {
            if let url = motherboard.speechDevice.stopRecording() {
                self.recordedAudioURL = url
                self.showingSavePanel = true
            }
            isRecording = false
        } else {
            motherboard.speechDevice.startRecording()
            isRecording = true
        }
    }
}

extension Color {
    static let darkGray = Color(white: 0.15)
}

struct SoundFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }

    var url: URL

    init(url: URL) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        self.url = URL(fileURLWithPath: "")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: url, options: .immediate)
    }
}
