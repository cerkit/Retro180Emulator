import Foundation

/// Z180 ASCI (Async Serial Communication Interface)
/// This emulates the on-chip serial ports of the Z180.
public class Z180ASCI: ExternalDevice {
    private var control0: UInt8 = 0
    private var control1: UInt8 = 0
    private var status: UInt8 = 0x02  // TDRE (Transmitter Data Register Empty) starts set

    // Buffers for input and output
    public var inputBuffer = Data()
    public var outputBuffer = Data()

    public init() {}

    public func read(port: UInt16) -> UInt8 {
        // Ports depend on mapping, but typically internal address 0x00-0x09
        // This class will be wrapped by the IODispatcher
        let internalPort = port & 0x3F

        switch internalPort {
        case 0x00:  // CNTLA0
            return control0
        case 0x02:  // STAT0
            var s = status
            if !inputBuffer.isEmpty {
                s |= 0x80  // RDRF (Receive Data Register Full)
            } else {
                s &= ~0x80
            }
            return s
        case 0x04:  // TDR0 (Transmit Data Register) - Write only, but some impls return 0
            return 0
        case 0x06:  // RDR0 (Receive Data Register)
            return inputBuffer.popFirst() ?? 0
        default:
            return 0
        }
    }

    public func write(port: UInt16, value: UInt8) {
        let internalPort = port & 0x3F

        switch internalPort {
        case 0x00:  // CNTLA0
            control0 = value
        case 0x04:  // TDR0
            outputBuffer.append(value)
        // In a real emu, we might trigger a UI update or serial send here
        default:
            break
        }
    }

    // External interface for UI/Terminal
    public func receiveFromTerminal(_ byte: UInt8) {
        inputBuffer.append(byte)
    }

    public func getAvailableOutput() -> Data {
        let data = outputBuffer
        outputBuffer.removeAll()
        return data
    }
}
