import Combine
import Foundation

/// Motherboard integrates all components and runs the execution loop.
@MainActor
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
        for port in UInt16(0)...9 {
            io.registerDevice(port: port, device: asci0)
        }

        loadDefaultROM()
    }

    public func start() {
        // Run at 100Hz (10ms)
        timer = Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Run a burst of instructions
            for _ in 0..<100 {
                self.cpu.step()
            }

            // Check for serial output
            let data = self.asci0.getAvailableOutput()
            if !data.isEmpty {
                self.terminalOutput.append(data)
            }
        }
    }

    public func sendToCPU(_ byte: UInt8) {
        asci0.receiveFromTerminal(byte)
    }

    private func loadDefaultROM() {
        // Simple Z80 program:
        // Prints "Hello!" in a loop
        var romData = Data([
            0x3E, 0x48,  // 00: LD A, 'H'
            0xD3, 0x04,  // 02: OUT (04), A
            0x3E, 0x65,  // 04: LD A, 'e'
            0xD3, 0x04,  // 06: OUT (04), A
            0x3E, 0x6C,  // 08: LD A, 'l'
            0xD3, 0x04,  // 0A: OUT (04), A
            0x3E, 0x6C,  // 0C: LD A, 'l'
            0xD3, 0x04,  // 0E: OUT (04), A
            0x3E, 0x6F,  // 10: LD A, 'o'
            0xD3, 0x04,  // 12: OUT (04), A
            0x3E, 0x21,  // 14: LD A, '!'
            0xD3, 0x04,  // 16: OUT (04), A
            0x18, 0xE6,  // 18: JR -26 (Jump back to index 00)
        ])
        // Pad to ROM size
        romData.append(Data(count: 512 * 1024 - romData.count))
        mmu.loadROM(data: romData)
    }
}
