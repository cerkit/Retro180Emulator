import Combine
import Foundation

@MainActor
public class Motherboard: ObservableObject {
    public let cpu = Z180CPU()
    public let mmu = Z180MMU()
    public let io = Z180IODispatcher()
    public let asci0 = Z180ASCI()
    public let asci1 = Z180ASCI()
    public let prt = Z180PRT()

    @Published public var inputQueue = [UInt8]()  // For pasting text
    @Published public var sessionLog = ""
    @Published public var ideStatusMessage = "IDE: Not Mounted"
    public let terminalStream = PassthroughSubject<Data, Never>()
    public let id = UUID()  // Unique Instance ID
    private var timer: Timer?
    private var traceCount = 0
    private let maxTrace = 100000
    private var tracing = false

    private var lastInputTick: UInt64 = 0

    private let inputInterval: UInt64 = 10000  // Cycles between characters
    private var ramSaveTimer: Timer?
    private let ramSaveInterval: TimeInterval = 30.0

    public init() {
        print(
            "Motherboard [\(id.uuidString.prefix(4))]: Init."
        )

        cpu.memory = mmu
        cpu.io = io

        // Connect I/O dispatcher to hardware
        io.mmu = mmu
        io.asci0 = asci0
        io.asci1 = asci1
        io.prt = prt

        // SC126/RomWBW expects internal I/O at 0xC0 (verified by 0xF9 BBR writes and IDE @ 0x10)
        io.setInternalBase(0xC0)

        initializeROM()
        print("Motherboard: RAM File URL: \(ramFileURL.path)")
        loadRAM()  // Restore RAM state

        // Start Periodic Auto-Save
        startRamAutoSave()
    }

    private var ramFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("ram.bin")
    }

    public func saveRAM() {
        do {
            try mmu.ram.write(to: ramFileURL)
            print("Motherboard: Saved RAM to \(ramFileURL.lastPathComponent)")
        } catch {
            print("Motherboard: Failed to save RAM: \(error)")
        }
    }

    public func injectRAM(_ data: Data) {
        // Pad or Trim to 512KB
        var newData = data
        let targetSize = mmu.ram.count
        if newData.count < targetSize {
            newData.append(Data(repeating: 0, count: targetSize - newData.count))
        } else if newData.count > targetSize {
            newData = newData.prefix(targetSize)
        }

        mmu.ram = newData
        print("Motherboard: Injected RAM (\(data.count) bytes)")
        saveRAM()
    }

    private func loadRAM() {
        let url = ramFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            if data.count == mmu.ram.count {
                mmu.ram = data
                print("Motherboard: Loaded RAM from \(url.lastPathComponent)")
            } else {
                print("Motherboard: Ignored RAM file (Size Mismatch)")
            }
        } catch {
            print("Motherboard: Failed to load RAM: \(error)")
        }
    }

    public func reset() {
        // Stop the timer momentarily to prevent race conditions during reset
        timer?.invalidate()
        timer = nil

        cpu.reset()
        mmu.reset()  // Check if MMU has reset

        // SC126 Specific: Force Internal I/O to 0xC0 on Reset
        io.setInternalBase(0xC0)

        inputQueue.removeAll()
        lastInputTick = 0
        sessionLog = ""

        initializeROM()

        // Restart
        // Restart
        start()
        startRamAutoSave()
    }

    private func startRamAutoSave() {
        ramSaveTimer?.invalidate()
        ramSaveTimer = Timer.scheduledTimer(withTimeInterval: ramSaveInterval, repeats: true) {
            [weak self] _ in
            self?.saveRAM()
        }
    }

    private func initializeROM() {
        // Try to load RomWBW for SC126 first
        let romNames = [
            "RomWBW-SCZ180_sc126_std-v351-2025-05-21",  // Found file
            "RomWBW-SCZ180_sc126_std",  // SC126 Standard
            "RomWBW-SCZ180_sc126_std-v3.5.1",  // Possible versioned name
            "RomWBW-SCZ180_sc131_std-v351-2025-05-21",  // Fallback to SC131
        ]

        for name in romNames {
            if let bundleURL = Bundle.main.url(forResource: name, withExtension: "rom") {
                loadROM(fromURL: bundleURL)
                return
            }

            // Absolute path fallback for hacking/debug
            let romPath =
                "/Users/cerkit/Development/Z80/Retro180Emulator/Retro180Emulator/Retro180Emulator/ROMs/\(name).rom"
            if FileManager.default.fileExists(atPath: romPath) {
                loadROM(fromURL: URL(fileURLWithPath: romPath))
                return
            }
        }

        print("Motherboard: No valid ROM found. Loading default test ROM.")
        loadDefaultROM()
    }

    public func start() {
        print("Motherboard: Starting CPU execution loop...")
        timer = Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let cyclesBefore = self.cpu.cycles
            for _ in 0..<5000 {
                self.cpu.step()
            }
            let cyclesPassed = Int(self.cpu.cycles &- cyclesBefore)
            self.prt.step(cycles: cyclesPassed)

            // Feed input queue into ASCII with rate limiting
            if !self.inputQueue.isEmpty && self.cpu.cycles > self.lastInputTick + self.inputInterval
            {
                let char = self.inputQueue.removeFirst()
                self.asci0.receiveFromTerminal(char)
                self.lastInputTick = self.cpu.cycles
            }

            // Sample output to console for debugging (every 500,000 cycles)
            /*
            if self.cpu.cycles / 500000 > cyclesBefore / 500000 {
                let opcode = self.mmu.read(address: self.cpu.PC)
                print(
                    "CPU Status: PC=0x\(String(self.cpu.PC, radix: 16)), Op=0x\(String(opcode, radix: 16)), Cycles=\(self.cpu.cycles), Halted=\(self.cpu.halted)"
                )
            }
            */

            let data = self.asci0.getAvailableOutput()
            if !data.isEmpty {
                self.terminalStream.send(data)
                // Append to session log (Heavy? Maybe limit?)
                let str = String(decoding: data, as: UTF8.self)
                self.sessionLog += str
            }
            self.objectWillChange.send()  // Ensure UI updates for cycles/halted state
        }
    }

    public func sendToCPU(_ byte: UInt8) {
        inputQueue.append(byte)
    }

    public func pasteText(_ text: String) {
        // Normalize line endings to CR (0x0D) for CP/M / RomWBW
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
        let bytes = normalized.data(using: .ascii) ?? Data()
        for byte in bytes {
            inputQueue.append(byte)
        }
    }

    public func loadROM(fromURL url: URL) {
        do {
            let data = try Data(contentsOf: url)
            mmu.loadROM(data: data)
            print(
                "Motherboard: Successfully loaded ROM (\(data.count) bytes) from \(url.lastPathComponent)"
            )
        } catch {
            print("Motherboard: Failed to load ROM from \(url.lastPathComponent): \(error)")
        }
    }

    private func loadDefaultROM() {
        // Assembly routine to test MLT and print results
        // 00: 01 02 03  LD BC, 0x0302
        // 03: ED 4C     MLT BC (BC = 3 * 2 = 6)
        // 05: 21 10 00  LD HL, 0x0010
        // 08: 71        LD (HL), C (Store result 6)
        // 09: 21 20 00  LD HL, 0x0020 (Loop setup for box)
        var romData = Data([
            0x01, 0x02, 0x03,  // LD BC, 0x0302
            0xED, 0x4C,  // MLT BC
            0x21, 0x10, 0x00,  // LD HL, 0x0010
            0x71,  // LD (HL), C
            0x21, 0x20, 0x00,  // LD HL, 0x0020
            0x7E,  // LD A, (HL)
            0xFE, 0x00,  // CP 0
            0x28, 0xFE,  // JR Z, $
            0xD3, 0x04,  // OUT (04), A
            0x23,  // INC HL
            0x18, 0xF6,  // JR -10
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Padding up to 0x20
        ])

        let width = 60
        let height = 25
        let text = "Z180 MLT Test: Success"

        // Construct Box Data
        var boxData = Data()
        let top = Data([0xDA]) + Data(repeating: 0xC4, count: width - 2) + Data([0xBF, 0x0D, 0x0A])
        let side =
            Data([0xB3]) + Data(repeating: 0x20, count: width - 2) + Data([0xB3, 0x0D, 0x0A])

        let padding = (width - 2 - text.count) / 2
        let textLine =
            Data([0xB3]) + Data(repeating: 0x20, count: padding) + text.data(using: .ascii)!
            + Data(repeating: 0x20, count: padding) + Data([0xB3, 0x0D, 0x0A])

        let bottom =
            Data([0xC0]) + Data(repeating: 0xC4, count: width - 2) + Data([0xD9, 0x0D, 0x0A])

        boxData.append(top)
        for i in 0..<height - 2 {
            if i == 11 {  // Center line
                boxData.append(textLine)
            } else {
                boxData.append(side)
            }
        }
        boxData.append(bottom)
        boxData.append(0x00)  // Null terminator for our print routine

        romData.append(boxData)

        // Pad to ROM size
        romData.append(Data(count: 512 * 1024 - romData.count))
        mmu.loadROM(data: romData)
    }
}
