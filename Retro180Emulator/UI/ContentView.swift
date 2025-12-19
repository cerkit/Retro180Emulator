import AppKit
import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var motherboard = Motherboard()
    @StateObject var terminalVM = TerminalViewModel()
    @State private var showingFileImporter = false
    @State private var xmodem: XMODEM?

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
}

extension Color {
    static let darkGray = Color(white: 0.15)
}
