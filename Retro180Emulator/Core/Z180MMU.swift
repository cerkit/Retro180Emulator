import Foundation

/// Z180 MMU Implementation
/// Handles translation from 16-bit logical addresses to 20-bit physical addresses.
public class Z180MMU: Z180Memory {
    public var ram: Data
    private var rom: Data

    // Z180 MMU Registers
    var CBR: UInt8 = 0  // Common Base Register (for Area 1)
    var BBR: UInt8 = 0  // Bank Base Register (for Bank Area)
    var CBAR: UInt8 = 0xF0  // Common/Bank Area Register (CA: high nibble, BA: low nibble)

    // Configuration
    private let ramSize = 512 * 1024  // 512KB RAM
    private let romSize = 512 * 1024  // 512KB ROM

    public init(romData: Data? = nil) {
        self.ram = Data(count: ramSize)
        if let data = romData, data.count <= romSize {
            self.rom = data
        } else {
            self.rom = Data(count: romSize)
            // Load a small "Hello World" or NOP sled if needed
        }
    }

    public func reset() {
        CBR = 0
        BBR = 0
        CBAR = 0xF0
    }

    /// Translates a 16-bit logical address to a 20-bit physical address.
    /// Z180 logic:
    /// Area 0: 0x0000 to (BA << 12) - 1
    /// Bank Area: (BA << 12) to (CA << 12) - 1
    /// Area 1: (CA << 12) to 0xFFFF
    public func translate(logical: UInt16) -> UInt32 {
        let baThreshold = UInt16(CBAR & 0x0F) << 12
        let caThreshold = UInt16(CBAR >> 4) << 12

        var base: UInt8 = 0
        if logical < baThreshold {
            base = 0  // Area 0 always uses 0 as base
        } else if logical < caThreshold {
            base = BBR
        } else {
            base = CBR
        }

        // Z180 Spec: Physical = (Logical + (Base << 12)) & 0xFFFFF
        // Note: The addition of the base to the high 4 bits of the logical address
        // can carry into the higher physical address bits (up to 20 bits).
        return (UInt32(logical) + (UInt32(base) << 12)) & 0xFFFFF
    }

    public func read(address: UInt16) -> UInt8 {
        let physical = translate(logical: address)
        return readPhysical(address: physical)
    }

    public func write(address: UInt16, value: UInt8) {
        let physical = translate(logical: address)
        writePhysical(address: physical, value: value)
    }

    public func readPhysical(address: UInt32) -> UInt8 {
        let addr = Int(address & 0xFFFFF)
        // SC131 Mapping:
        // 0x00000 - 0x7FFFF: ROM (512K)
        // 0x80000 - 0xFFFFF: RAM (512K)
        if addr < 0x80000 {
            if addr < rom.count {
                return rom[addr]
            }
            return 0xFF
        } else {
            let ramAddr = addr - 0x80000
            if ramAddr < ram.count {
                return ram[ramAddr]
            }
            return 0xFF
        }
    }

    public func writePhysical(address: UInt32, value: UInt8) {
        let addr = Int(address & 0xFFFFF)
        if addr >= 0x80000 {
            let ramAddr = addr - 0x80000
            if ramAddr < ram.count {
                ram[ramAddr] = value
            }
        }
        // ROM is typically read-only
    }

    // Helper to load ROM data
    public func loadROM(data: Data) {
        let size = Swift.min(data.count, rom.count)
        rom.replaceSubrange(0..<size, with: data.prefix(size))
    }
}
