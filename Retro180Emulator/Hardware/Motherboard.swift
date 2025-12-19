import Combine
import Foundation

/// Motherboard integrates all components and runs the execution loop.
public class Motherboard: ObservableObject {
    public let cpu = Z180CPU()
    public let mmu = Z180MMU()
    public let io = Z180IODispatcher()
    public let asci0 = Z180ASCI()

    @Published var terminalOutput = Data()
    private var timer: Timer?

    public init() {
        cpu.memory = mmu
        cpu.io = io

        // Map internal registers to 0x00 by default
        io.setInternalBase(0x00)

        // Register ASCI0 at its default internal location (0x00-0x09)
        // Note: The dispatcher handles internal port range checks

        loadDefaultROM()
    }

    public func start() {
        // Run at 100Hz (10ms)
        timer = Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { _ in
            // Run a burst of instructions
            for _ in 0..<100 {
                self.cpu.step()
            }

            // Check for serial output
            let data = self.asci0.getAvailableOutput()
            if !data.isEmpty {
                DispatchQueue.main.async {
                    self.terminalOutput.append(data)
                }
            }
        }
    }

    public func sendToCPU(_ byte: UInt8) {
        asci0.receiveFromTerminal(byte)
    }

    private func loadDefaultROM() {
        // Simple Z80 program:
        // LD A, 'H'
        // OUT (0x06), A ; In Z180 ASCI RDR0 is 0x06 (if internal base is 0x00)
        // ... (This is just a placeholder, real RomWBW would be loaded)
        var romData = Data([
            0x3E, 0x48,  // LD A, 'H'
            0xD3, 0x06,  // OUT (06), A
            0x3E, 0x31,  // LD A, '1'
            0xD3, 0x06,  // OUT (06), A
            0x18, 0xFE,  // JR -2 (Loop)
        ])
        // Pad to ROM size
        romData.append(Data(count: 512 * 1024 - romData.count))
        mmu.loadROM(data: romData)
    }
}
