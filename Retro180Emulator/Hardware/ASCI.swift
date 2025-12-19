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

    public init() {}

    public func read(port: UInt16) -> UInt8 {
        // We use a simplified internal offset for the channel based on port addr
        // 0=CNTLA, 1=CNTLB, 2=STAT, 3=TDR, 4=RDR, 5=ASEXT, 6=IER
        let reg = internalRegister(for: port)

        switch reg {
        case 0: return controlA
        case 1: return controlB
        case 2:
            var s = status
            if !inputBuffer.isEmpty {
                s |= 0x80  // RDRF (Receive Data Register Full)
            } else {
                s &= ~0x80
            }
            return s
        case 4: return inputBuffer.popFirst() ?? 0
        case 5: return extensionControl
        case 6: return interruptEnable
        default: return 0
        }
    }

    public func write(port: UInt16, value: UInt8) {
        let reg = internalRegister(for: port)

        switch reg {
        case 0: controlA = value
        case 1: controlB = value
        case 3:  // TDR
            outputBuffer.append(value)
            // Real-time console mirror for debugging
            let scalar = UnicodeScalar(value)
            print("\(Character(scalar))", terminator: "")
            fflush(stdout)
        case 5: extensionControl = value
        case 6: interruptEnable = value
        default: break
        }
    }

    private func internalRegister(for port: UInt16) -> Int {
        let p = port & 0x3F
        switch p {
        case 0x00, 0x01: return 0  // CNTLA
        case 0x02, 0x03: return 1  // CNTLB
        case 0x04, 0x05: return 2  // STAT
        case 0x06, 0x07: return 3  // TDR
        case 0x08, 0x09: return 4  // RDR
        case 0x12, 0x13: return 5  // ASEXT
        case 0x0E, 0x0F: return 6  // IER
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
}
