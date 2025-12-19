import Foundation

/// Z180 I/O Dispatcher
/// Manages internal Z180 registers and external peripheral ports.
public class Z180IODispatcher: Z180IO {
    // Internal Z180 registers (usually 0x00-0x3F or relocated to 0xC0-0xFF)
    private var internalRegisters = [UInt8](repeating: 0, count: 64)
    private var internalBase: UInt16 = 0x00

    // Peripherals
    public var mmu: Z180MMU?
    public var asci0: Z180ASCI?
    public var asci1: Z180ASCI?
    public var prt: Z180PRT?

    // External peripherals mapped by port range (for non-internal I/O)
    private var devices: [UInt16: ExternalDevice] = [:]

    public init() {}

    public func setInternalBase(_ base: UInt8) {
        self.internalBase = UInt16(base) & 0xC0
    }

    public func registerDevice(port: UInt16, device: ExternalDevice) {
        devices[port] = device
    }

    public func read(port: UInt16) -> UInt8 {
        // Z180 spec: internal I/O decodes only A7-A0. A15-A8 are ignored.
        let iop = port & 0xFF

        // 0. High priority dummy response for SD card detection (Port 0xCA/0xCB)
        // These ports are within the relocated internal range (0xC0-0xFF) and must be forced.
        if iop == 0xCA || iop == 0xCB {
            return 0x00  // Return "Ready/Idle" status
        }

        // 1. Check if it's an internal Z180 register first
        if iop >= internalBase && iop < internalBase + 64 {
            let index = Int(iop - internalBase)
            return readInternal(index: index)
        }

        // 2. Check external devices (using full 16-bit address for external)
        if let device = devices[port] {
            return device.read(port: port)
        }

        // 3. Removed (moved to top level)

        return 0xFF
    }

    public func write(port: UInt16, value: UInt8) {
        let iop = port & 0xFF

        // 1. Check if it's an internal Z180 register
        if iop >= internalBase && iop < internalBase + 64 {
            let index = Int(iop - internalBase)
            internalRegisters[index] = value
            writeInternal(index: index, value: value)
        }

        // 2. Dispatch to external device if registered (non-internal)
        else if let device = devices[port] {
            device.write(port: port, value: value)
        }
    }

    private func readInternal(index: Int) -> UInt8 {
        let p = UInt16(index)
        switch p {
        case 0x00, 0x02, 0x04, 0x06, 0x08, 0x0E, 0x12:  // ASCI0 registers
            return asci0?.read(port: p) ?? 0xFF
        case 0x01, 0x03, 0x05, 0x07, 0x09, 0x0F, 0x13:  // ASCI1 registers
            return asci1?.read(port: p) ?? 0xFF
        case 0x10, 0x11, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19:  // PRT registers
            return prt?.read(port: p) ?? 0xFF
        case 0x38: return mmu?.CBR ?? 0
        case 0x39: return mmu?.BBR ?? 0
        case 0x3A: return mmu?.CBAR ?? 0
        case 0x3F: return UInt8(internalBase >> 6) << 6
        default: return internalRegisters[index]
        }
    }

    private func writeInternal(index: Int, value: UInt8) {
        let p = UInt16(index)
        switch p {
        case 0x00, 0x02, 0x04, 0x06, 0x08, 0x0E, 0x12:  // ASCI0 registers
            asci0?.write(port: p, value: value)
        case 0x01, 0x03, 0x05, 0x07, 0x09, 0x0F, 0x13:  // ASCI1 registers
            asci1?.write(port: p, value: value)
        case 0x10, 0x11, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19:  // PRT registers
            prt?.write(port: p, value: value)
        case 0x38: mmu?.CBR = value
        case 0x39: mmu?.BBR = value
        case 0x3A: mmu?.CBAR = value
        case 0x3F: setInternalBase(value)
        default: break
        }
    }
}

public protocol ExternalDevice {
    func read(port: UInt16) -> UInt8
    func write(port: UInt16, value: UInt8)
}
