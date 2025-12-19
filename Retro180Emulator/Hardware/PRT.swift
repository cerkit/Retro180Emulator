import Foundation

/// Z180 PRT (Programmable Reload Timer)
/// This emulates the two-channel down-counter timer of the Z180.
public class Z180PRT: ExternalDevice {
    private var tmdr0: UInt16 = 0xFFFF
    private var trld0: UInt16 = 0xFFFF
    private var tmdr1: UInt16 = 0xFFFF
    private var trld1: UInt16 = 0xFFFF
    private var tcr: UInt8 = 0

    public init() {}

    public func read(port: UInt16) -> UInt8 {
        let index = port & 0x3F
        switch index {
        case 0x10: return UInt8(tmdr0 & 0xFF)
        case 0x11: return UInt8(tmdr0 >> 8)
        case 0x12: return UInt8(trld0 & 0xFF)
        case 0x13: return UInt8(trld0 >> 8)
        case 0x14: return tcr
        case 0x16: return UInt8(tmdr1 & 0xFF)
        case 0x17: return UInt8(tmdr1 >> 8)
        case 0x18: return UInt8(trld1 & 0xFF)
        case 0x19: return UInt8(trld1 >> 8)
        default: return 0xFF
        }
    }

    public func write(port: UInt16, value: UInt8) {
        let index = port & 0x3F
        switch index {
        case 0x10: tmdr0 = (tmdr0 & 0xFF00) | UInt16(value)
        case 0x11: tmdr0 = (tmdr0 & 0x00FF) | (UInt16(value) << 8)
        case 0x12: trld0 = (trld0 & 0xFF00) | UInt16(value)
        case 0x13: trld0 = (trld0 & 0x00FF) | (UInt16(value) << 8)
        case 0x14:
            // TCR: bits 0-1 are TDE (Timer Down-count Enable)
            // bit 4-5 are TIE (Timer Interrupt Enable)
            // bit 6-7 are TIF (Timer Interrupt Flag) - Write 0 to clear
            let mask: UInt8 = 0x3F  // Don't allow writing to TIF bits directly via simple write?
            // Z180 spec: TIF is cleared by writing 0 to it when it is 1.
            var newTcr = (tcr & ~mask) | (value & mask)
            if (value & 0x40) == 0 { newTcr &= ~0x40 }
            if (value & 0x80) == 0 { newTcr &= ~0x80 }
            tcr = newTcr
        case 0x16: tmdr1 = (tmdr1 & 0xFF00) | UInt16(value)
        case 0x17: tmdr1 = (tmdr1 & 0x00FF) | (UInt16(value) << 8)
        case 0x18: trld1 = (trld1 & 0xFF00) | UInt16(value)
        case 0x19: trld1 = (trld1 & 0x00FF) | (UInt16(value) << 8)
        default: break
        }
    }

    public func step(cycles: Int) {
        let ticks = cycles / 20
        if ticks == 0 { return }

        // TDE0 is bit 0
        if (tcr & 0x01) != 0 {
            if Int(tmdr0) <= ticks {
                tmdr0 = trld0
                tcr |= 0x40  // Set TIF0
            } else {
                tmdr0 &-= UInt16(ticks)
            }
        }
        // TDE1 is bit 1
        if (tcr & 0x02) != 0 {
            if Int(tmdr1) <= ticks {
                tmdr1 = trld1
                tcr |= 0x80  // Set TIF1
            } else {
                tmdr1 &-= UInt16(ticks)
            }
        }
    }

    public func checkInterrupt(channel: Int) -> Bool {
        if channel == 0 {
            // TIE0 is bit 4, TIF0 is bit 6
            return (tcr & 0x10) != 0 && (tcr & 0x40) != 0
        } else {
            // TIE1 is bit 5, TIF1 is bit 7
            return (tcr & 0x20) != 0 && (tcr & 0x80) != 0
        }
    }
}
