import Foundation

/// Z180 ASCI (Async Serial Communication Interface)
/// This emulates a single channel of the on-chip serial ports of the Z180.
public class Z180ASCI: ExternalDevice {
    private var controlA: UInt8 = 0
    private var controlB: UInt8 = 0
    private var extensionControl: UInt8 = 0
    private var interruptEnable: UInt8 = 0
    private var status: UInt8 = 0x02  // TDRE (Transmitter Data Register Empty) set on reset

    // Buffers for input and output
    public var inputBuffer = Data()
    public var outputBuffer = Data()

    // Latch for data read-ahead (e.g. if STAT read clears interrupt but data not yet read)
    private var receiveLatch: UInt8?

    public init() {}

    public func read(port: UInt16) -> UInt8 {
        // We use a simplified internal offset for the channel based on port addr
        // 0=CNTLA, 1=CNTLB, 2=STAT, 3=TDR, 4=RDR, 5=ASEXT, 6=IER
        let reg = internalRegister(for: port)
        print("ASCI Read Port: 0x\(String(port, radix: 16)) Reg: \(reg)")

        switch reg {
        case 0: return controlA
        case 1:
            // CTS/PS (Bit 5). 0 = Low (Active).
            // But wait, Z180 manual: "CTS1/PS" is in CNTLB.
            // What about CTS0?
            // ASCI0 uses CNTLB0.
            // Bit 5 is CTS/PS. 0=Active.
            return controlB & ~0x20
        case 2:  // STAT (0x04)
            // Construct status dynamically to avoid stuck error bits.
            // We want RDRF (Bit 7), TDRE (Bit 1), DCD0 (Bit 2).
            // Error bits (OVR, PE, FE) should be 0 for now.
            var s: UInt8 = 0

            // RDRF (Bit 7) logic:
            // If we have a latch, data is ready.
            // If we don't, check buffer.
            if receiveLatch != nil {
                s |= 0x80
            } else if !inputBuffer.isEmpty {
                s |= 0x80
                // Move to latch immediately to clear "Level Triggered" interrupt in buffer check?
                receiveLatch = inputBuffer.popFirst()
                print("ASCI: Auto-Latched char '104'")  // 'h' debug
            }

            // TDRE (Bit 1) is always true (buffer empty/ready)
            s |= 0x02
            // DCD0 (Bit 2) - Set to 1 (Input Low = Active Carrier)
            s |= 0x04

            print("ASCI Read STAT (Port 4) -> 0x\(String(s, radix: 16))")
            return s
        case 3:  // TDR/RDR (0x06) - Shared!
            // RDR Read: Return latch if exists, else buffer
            if let l = receiveLatch {
                receiveLatch = nil
                print("ASCI: Read RDR (Latch) -> '\(l)'")
                return l
            }
            let char = inputBuffer.popFirst() ?? 0
            print("ASCI: Read RDR (Direct) -> '\(char)'")
            return char
        case 4:  // RDR (0x08) - Mapping just in case
            if let l = receiveLatch {
                receiveLatch = nil
                print("ASCI: Read RDR (Latch) -> '\(l)'")
                return l
            }
            let char = inputBuffer.popFirst() ?? 0
            print("ASCI: Read RDR (Direct) -> '\(char)'")
            return char
        case 5: return extensionControl
        case 6: return interruptEnable
        default:
            print("ASCI: Unhandled Read Port: 0x\(String(port, radix: 16))")
            return 0
        }
    }

    public func write(port: UInt16, value: UInt8) {
        let reg = internalRegister(for: port)

        switch reg {
        case 0:
            controlA = value
            // Sync RIE (Bit 3) to STAT
            if (value & 0x08) != 0 {
                status |= 0x08
            } else {
                status &= ~0x08
            }
        case 1:
            controlB = value
        case 2:  // STAT (bits 0 TIE and 3 RIE are R/W)
            // Preserve Read-Only bits (7,6,5,4,2,1) and update R/W bits (3,0)
            let readOnlyMask: UInt8 = 0xF6  // 1111 0110
            let writeMask: UInt8 = 0x09  // 0000 1001
            status = (status & readOnlyMask) | (value & writeMask)

            // Sync RIE (Bit 3) back to CNTLA
            if (status & 0x08) != 0 {
                controlA |= 0x08
            } else {
                controlA &= ~0x08
            }
        case 3:  // TDR
            outputBuffer.append(value)
        // Real-time console mirror for debugging
        // let scalar = UnicodeScalar(value)
        // print("\(Character(scalar))", terminator: "")
        // fflush(stdout)
        case 5: extensionControl = value
        case 6: interruptEnable = value
        default: break
        }
    }

    private func internalRegister(for port: UInt16) -> Int {
        // Standard Z180 and Stride-2 compatibility mapping
        // We permit both sets of offsets to be safe.

        let p = port & 0x1F  // Mask lower bits

        switch p {
        case 0x00: return 0  // CNTLA
        case 0x01: return 1  // CNTLB (Std)
        case 0x02: return 2  // STAT0 (Std)
        case 0x03: return 3  // TDR0/RDR0 (Std)

        // Stride-2 Aliases (If BIOS uses them)
        case 0x04: return 2  // STAT0 (Strided) - BIOS reads this!
        case 0x06: return 3  // TDR0/RDR0 (Strided)
        case 0x08: return 4  // RDR0 (Alternative Strided)

        // ASEXT and IER are not part of the standard 0-3 block, so they are less ambiguous.
        case 0x12: return 5  // ASEXT (Stride-2)
        case 0x0E: return 6  // IER (Stride-2)

        default: return -1
        }
    }

    public func receiveFromTerminal(_ byte: UInt8) {
        inputBuffer.append(byte)
    }

    public func getAvailableOutput() -> Data {
        let data = outputBuffer
        outputBuffer.removeAll()
        return data
    }

    public func checkInterrupt() -> Bool {
        // Z180 ASCI Interrupt Logic:
        // STAT bit 3: RIE (Receive Interrupt Enable)
        // If RIE && RDRF -> Interrupt

        let rie = (status & 0x08) != 0
        let rdrf = !inputBuffer.isEmpty  // Check actual buffer, not stale status bit

        if rie && rdrf {
            // print("ASCI: Interrupt Request! RIE=\(rie), RDRF=\(rdrf)")
            return true
        }
        return false
    }
}  // End Z180ASCI
