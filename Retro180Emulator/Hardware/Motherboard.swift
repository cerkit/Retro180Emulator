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

    @Published var terminalOutput = Data()
    private var timer: Timer?
    private var traceCount = 0
    private let maxTrace = 100000
    private var tracing = true

    public init() {
        cpu.memory = mmu
        cpu.io = io

        // Connect I/O dispatcher to hardware
        io.mmu = mmu
        io.asci0 = asci0
        io.asci1 = asci1
        io.prt = prt

        io.setInternalBase(0x00)

        // Try to load RomWBW from the app bundle first (fixes permission issues in Sandboxed apps)
        if let bundleURL = Bundle.main.url(
            forResource: "RomWBW-SCZ180_sc131_std-v351-2025-05-21", withExtension: "rom")
        {
            loadROM(fromURL: bundleURL)
        } else {
            // Fallback to absolute path (may fail if Sandbox is enabled)
            let romPath =
                "/Users/cerkit/Development/Z80/Retro180Emulator/Retro180Emulator/Retro180Emulator/ROMs/RomWBW-SCZ180_sc131_std-v351-2025-05-21.rom"
            let url = URL(fileURLWithPath: romPath)
            if FileManager.default.fileExists(atPath: romPath) {
                loadROM(fromURL: url)
            } else {
                loadDefaultROM()
            }
        }
    }

    public func start() {
        print("Motherboard: Starting CPU execution loop...")
        timer = Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let cyclesBefore = self.cpu.cycles
            for _ in 0..<5000 {
                if self.tracing {
                    let pc = self.cpu.PC
                    let opcode = self.mmu.read(address: pc)
                    print(
                        "TRACE: PC=0x\(String(pc, radix: 16)), Op=0x\(String(opcode, radix: 16)), A=0x\(String(self.cpu.A, radix: 16)), F=0x\(String(self.cpu.F, radix: 16)), BC=0x\(String(self.cpu.BC, radix: 16)), HL=0x\(String(self.cpu.HL, radix: 16))"
                    )
                    self.traceCount += 1
                    if self.traceCount >= self.maxTrace { self.tracing = false }
                }
                self.cpu.step()
            }
            let cyclesPassed = Int(self.cpu.cycles &- cyclesBefore)
            self.prt.step(cycles: cyclesPassed)

            // Sample output to console for debugging (every ~500,000 cycles)
            if self.cpu.cycles % 500000 < 5000 {
                let opcode = self.mmu.read(address: self.cpu.PC)
                print(
                    "CPU Status: PC=0x\(String(self.cpu.PC, radix: 16)), Op=0x\(String(opcode, radix: 16)), Cycles=\(self.cpu.cycles), Halted=\(self.cpu.halted)"
                )
            }

            let data = self.asci0.getAvailableOutput()
            if !data.isEmpty {
                self.terminalOutput.append(data)
            }
            self.objectWillChange.send()  // Ensure UI updates for cycles/halted state
        }
    }

    public func sendToCPU(_ byte: UInt8) {
        asci0.receiveFromTerminal(byte)
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
