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

    // External peripherals mapped by 8-bit port address (ignoring A8-A15 typical of Z80/RC2014)
    private var devices: [UInt8: ExternalDevice] = [:]

    public init() {}

    public func setInternalBase(_ base: UInt8) {
        // print("Z180IO: setInternalBase -> 0x\(String(base & 0xC0, radix: 16))")
        self.internalBase = UInt16(base) & 0xC0
    }

    public func registerDevice(port: UInt16, device: ExternalDevice) {
        // We only care about the lower 8 bits for registration
        devices[UInt8(port & 0xFF)] = device
    }

    public func read(port: UInt16) -> UInt8 {
        // Debug Log part 1
        let iop = UInt8(port & 0xFF)
        /*
        if iop != 0x06 && iop != 0x08 {  // Filter ASCI Data
             print("IO: Read Port 0x\(String(iop, radix: 16)) (Full: 0x\(String(port, radix: 16)))")
        }
        */

        // Z180 spec: internal I/O decodes only A7-A0. A15-A8 are ignored.

        // 0. SD Card (Port 0xCA/0xCB) -- REMOVED
        // 0. SD Card (Port 0xCA/0xCB)

        // 1. Check if it's an internal Z180 register first
        // Check using 16-bit internalBase logic (which just masks anyway)
        // internal registers are 64 bytes starting at internalBase (C0 or 00 or 40)
        let base8 = UInt8(internalBase & 0xFF)
        // Check if iop is in range [base, base+64)
        // Handle wrap-around? Z180 usually aligns to 0x40 boundary.
        // Simple check:
        // If internalBase is 0xC0, registers are C0-FF.
        // If internalBase is 0x00, registers are 00-3F.

        // Logic: if (iop & 0xC0) == (base8 & 0xC0)
        // But this assumes base is always 0, 40, 80, C0.
        // Z180 ICR allows moving to 0x00, 0x40, 0x80, 0xC0.
        if (iop & 0xC0) == (base8 & 0xC0) {
            let index = Int(iop & 0x3F)
            return readInternal(index: index)
        }

        // SP0256 Speech / SpeechDevice (Port 0x50)
        /*
        if iop == 0x50 {
            return speechDevice?.readStatus() ?? 0xFF
        }
        */

        // 2. Check external devices (using 8-bit address)
        if let device = devices[iop] {
            return device.read(port: port)
        }

        return 0xFF
    }

    public func write(port: UInt16, value: UInt8) {
        // Internal I/O Dispatch
        // A15-A8 are ignored for internal I/O
        let p = UInt8(port & 0xFF)

        if p != 0x06 && p != 0x08 {  // Filter ASCI
            // print("IO: Write Port 0x\(String(p, radix: 16)) Val 0x\(String(value, radix: 16))")
        }

        // 0. SD Card (Port 0xCA/0xCB) -- REMOVED
        // 0. SD Card (Port 0xCA/0xCB)

        // Internal I/O Base Register
        let base8 = UInt8(internalBase & 0xFF)
        if (p & 0xC0) == (base8 & 0xC0) {
            writeInternal(index: Int(p & 0x3F), value: value)
            return
        }

        // SP0256 Speech / SpeechDevice (Port 0x50)
        /*
        if p == 0x50 {
            speechDevice?.write(byte: value)
            return
        }
        */

        // External I/O Dispatch
        if let device = devices[p] {
            device.write(port: port, value: value)
            return
        }
    }

    public func checkInterrupts() -> UInt8? {
        // IL Register (Offset 0x33) determines the base of internal vectors (Bits 7-5)
        let il = internalRegisters[0x33] & 0xE0

        if let prt = prt {
            if prt.checkInterrupt(channel: 0) { return il | 0x04 }  // PRT0 (Standard 0x04)
            if prt.checkInterrupt(channel: 1) { return il | 0x06 }  // PRT1 (Standard 0x06)
        }
        if let asci0 = asci0 {
            if asci0.checkInterrupt() { return il | 0x0E }  // ASCI0 (Standard 0x0E)
        }
        return nil
    }

    private func readInternal(index: Int) -> UInt8 {
        let p = UInt16(index)
        switch p {
        case 0x00...0x09, 0x12:  // ASCI0 registers (Standard Z180 range)
            return asci0?.read(port: p) ?? 0xFF
        case 0x01, 0x03, 0x05, 0x07, 0x09, 0x0F, 0x13:  // ASCI1 registers (TODO: Fix mapping if needed)
            return asci1?.read(port: p) ?? 0xFF
        case 0x10, 0x11, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19:  // PRT registers
            return prt?.read(port: p) ?? 0xFF
        case 0x38: return mmu?.CBR ?? 0
        case 0x39: return mmu?.BBR ?? 0
        case 0x3A: return mmu?.CBAR ?? 0
        case 0x3F: return UInt8(internalBase >> 6) << 6

        // CSIO Read Handler
        case 0x0A:
            // Return 0x00 (Not Enabled, Not Ready).
            // This prevents RomWBW from verifying the hardware presence (Write Enable -> Read Back Check fails).
            // Result: "DEVICES=0" (Skipped).
            return 0x00
        case 0x0B:
            // Reading TRDR clears EF (End Flag) - but we will force it high on next 0x0A read anyway.
            // internalRegisters[0x0A] &= 0x7F
            // Return 0xFF (Floating) because no SD card connected
            return 0xFF

        default: return internalRegisters[index]
        }
    }

    private func writeInternal(index: Int, value: UInt8) {
        let p = UInt16(index)
        switch p {
        case 0x00...0x09, 0x12:  // ASCI0 registers
            asci0?.write(port: p, value: value)
        case 0x01, 0x03, 0x05, 0x07, 0x09, 0x0F, 0x13:  // ASCI1 registers
            asci1?.write(port: p, value: value)
        case 0x10, 0x11, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19:  // PRT registers
            prt?.write(port: p, value: value)
        case 0x38: mmu?.CBR = value
        case 0x39: mmu?.BBR = value
        case 0x3A: mmu?.CBAR = value
        case 0x3F: setInternalBase(value)

        // CSIO Handler (Minimal Emulation for RomWBW SD)
        // CNTR (0x0A) and TRDR (0x0B)
        case 0x0A:
            // Ignore writes. Effectively Read-Only 0x00.
            return
        case 0x0B:
            // Ignore Data writes.
            return

        default:
            if p == 0x33 {
                // print("Z180IO: Write IL (Interrupt Vector Low) -> 0x\(String(value, radix: 16))")
            }
            internalRegisters[index] = value
        }
    }
}

public protocol ExternalDevice {
    func read(port: UInt16) -> UInt8
    func write(port: UInt16, value: UInt8)
}
