import Foundation

/// Z180 MMU Implementation
/// Handles translation from 16-bit logical addresses to 20-bit physical addresses.
public class Z180MMU: Z180Memory {
    private var ram: Data
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

    /// Translates a 16-bit logical address to a 20-bit physical address.
    /// Z180 logic:
    /// Area 0: 0x0000 to (BA << 12) - 1
    /// Bank Area: (BA << 12) to (CA << 12) - 1
    /// Area 1: (CA << 12) to 0xFFFF
    public func translate(logical: UInt16) -> UInt32 {
        let baThreshold = UInt16(CBAR & 0x0F) << 12
        let caThreshold = UInt16(CBAR >> 4) << 12

        if logical < baThreshold {
            // Area 0: Always Base 0
            return UInt32(logical)
        } else if logical < caThreshold {
            // Bank Area
            let base = UInt32(BBR) << 12
            let offset = UInt32(logical - baThreshold)
            return (base + offset) & 0xFFFFF
        } else {
            // Area 1
            let base = UInt32(CBR) << 12
            let offset = UInt32(logical - caThreshold)
            return (base + offset) & 0xFFFFF
        }
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
        // SC131 Mapping:
        // Physical 0x00000 - 0x7FFFF is often Flash ROM
        // Physical 0x80000 - 0xFFFFF is RAM
        // However, RomWBW often swaps this or uses different mapping.
        // For SC131: FLASH is bottom 512K, RAM is top 512K.
        if address < 0x80000 {
            return rom[Int(address)]
        } else {
            return ram[Int(address - 0x80000)]
        }
    }

    public func writePhysical(address: UInt32, value: UInt8) {
        if address >= 0x80000 {
            ram[Int(address - 0x80000)] = value
        }
        // Flash ROM is typically write-protected or requires special sequences
    }

    // Helper to load ROM data
    public func loadROM(data: Data) {
        let size = Swift.min(data.count, rom.count)
        rom.replaceSubrange(0..<size, with: data.prefix(size))
    }
}
