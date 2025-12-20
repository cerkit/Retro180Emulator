import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase

    enum FileImporterType {
        case none
        case upload
        case injectFile
        case restoreSnapshot
    }

    @StateObject var motherboard = Motherboard()
    @StateObject var terminalVM = TerminalViewModel()
    @State private var showingFileImporter = false
    @State private var activeImporter: FileImporterType = .none
    @State private var xmodem: XMODEM?
    @State private var showingHistory = false

    // Smart Injection State
    @State private var showingInjectionSheet = false
    @State private var pendingInjectionData: Data?
    @State private var injectionFilename = ""

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
                        activeImporter = .injectFile
                        showingFileImporter = true
                    }) {
                        Label("Inject File", systemImage: "square.and.arrow.down")
                    }
                    .help("Inject a file into CP/M (Current Drive)")

                    Button(action: {
                        activeImporter = .restoreSnapshot
                        showingFileImporter = true
                    }) {
                        Label("Restore Snapshot", systemImage: "memorychip")
                    }
                    .help("Restore a dull 512KB RAM Snapshot (Destructive!)")

                    Button(action: {
                        showingHistory = true
                    }) {
                        Label("History", systemImage: "clock")
                    }
                    .help("View Session History Log")

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

                }
            }

            HStack {
                Text("Status: \(motherboard.cpu.halted ? "Halted" : "Running")")
                Text("[\(motherboard.id.uuidString.prefix(4))]")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(motherboard.ideStatusMessage)
                    .foregroundStyle(
                        motherboard.ideStatusMessage.contains("Success") ? .green : .red)
                Spacer()
                Text("Cycles: \(motherboard.cpu.cycles)")
            }
            .padding()
            .font(.caption)
        }
        .onReceive(motherboard.terminalStream) { data in
            // Pass data to XMODEM if active
            for byte in data {
                xmodem?.handleByte(byte)
            }

            // Update Terminal VM (UI) - Batch Update
            terminalVM.putData(data)
        }
        .onAppear {
            motherboard.start()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: activeImporter == .upload ? [.item] : [.data],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let fileUrl = try result.get().first else { return }
                guard fileUrl.startAccessingSecurityScopedResource() else { return }

                switch activeImporter {
                case .upload:
                    // Raw Upload (Manual XMODEM)
                    let data = try Data(contentsOf: fileUrl)
                    startUpload(data: data)

                case .injectFile:
                    // Smart Injection Request
                    let data = try Data(contentsOf: fileUrl)
                    pendingInjectionData = data
                    injectionFilename = fileUrl.lastPathComponent.uppercased()
                    showingInjectionSheet = true

                case .restoreSnapshot:
                    let data = try Data(contentsOf: fileUrl)
                    motherboard.injectRAM(data)

                case .none:
                    break
                }

                fileUrl.stopAccessingSecurityScopedResource()
            } catch {
                print("File import failed: \(error.localizedDescription)")
            }
        }

        .sheet(isPresented: $showingHistory) {
            VStack {
                HStack {
                    Text("Session History")
                        .font(.headline)
                    Spacer()
                    Button("Copy All") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(motherboard.sessionLog, forType: .string)
                    }
                    Button("Close") {
                        showingHistory = false
                    }
                }
                .padding()

                TextEditor(text: .constant(motherboard.sessionLog))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 600, height: 400)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.5)))
            }
            .padding()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                saveOnExit()
            }
        }
        .sheet(isPresented: $showingInjectionSheet) {
            VStack(spacing: 20) {
                Text("Inject File to CP/M")
                    .font(.headline)

                TextField("Filename (e.g. GAME.COM)", text: $injectionFilename)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)

                Text("This will type 'XM R <FILENAME>' and start the transfer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Cancel") {
                        showingInjectionSheet = false
                        pendingInjectionData = nil
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Inject") {
                        if let data = pendingInjectionData {
                            startSmartInjection(filename: injectionFilename, data: data)
                        }
                        showingInjectionSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 300, height: 200)
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

    func startSmartInjection(filename: String, data: Data) {
        // 1. Send Command (Clear buffer first?)
        // Assumes XM.COM is on Drive B: (User Request)
        motherboard.pasteText("\rB:XM R \(filename)\r")

        // 2. Wait for CP/M to launch XM (Delay 1.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // 3. Start Transfer
            print("ContentView: Starting Smart Upload of \(filename)")
            self.startUpload(data: data)
        }
    }

}

// Ensure saving on exit/background
extension ContentView {
    func saveOnExit() {
        motherboard.saveRAM()
    }
}
