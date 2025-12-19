import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var motherboard = Motherboard()
    @StateObject var terminalVM = TerminalViewModel()
    @State private var showingFileImporter = false
    @State private var xmodem: XMODEM?

    var body: some View {
        VStack {
            HStack {
                Text("Retro180 Emulator")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button("Upload via XMODEM") {
                    showingFileImporter = true
                }
            }
            .padding()
            .background(Color.darkGray)

            TerminalView(viewModel: terminalVM)
                .frame(width: 800, height: 480)

            HStack {
                Text("Status: \(motherboard.cpu.halted ? "Halted" : "Running")")
                Spacer()
                Text("Cycles: \(motherboard.cpu.cycles)")
            }
            .padding()
            .font(.caption)
        }
        .onReceive(motherboard.$terminalOutput) { data in
            for byte in data {
                // Pass the byte to the XMODEM handler if a transfer is active
                xmodem?.handleByte(byte)
                
                terminalVM.putChar(Character(UnicodeScalar(byte)))
            }
            
            if !data.isEmpty {
                motherboard.terminalOutput.removeAll()
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
