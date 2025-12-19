import Foundation

/// Z180 CPU Registers and State
public class Z180CPU {
    // 8-bit Main Registers
    var A: UInt8 = 0, F: UInt8 = 0
    var B: UInt8 = 0, C: UInt8 = 0
    var D: UInt8 = 0, E: UInt8 = 0
    var H: UInt8 = 0, L: UInt8 = 0

    // 8-bit Alternate Registers
    var A_prime: UInt8 = 0, F_prime: UInt8 = 0
    var B_prime: UInt8 = 0, C_prime: UInt8 = 0
    var D_prime: UInt8 = 0, E_prime: UInt8 = 0
    var H_prime: UInt8 = 0, L_prime: UInt8 = 0

    // 16-bit Index Registers
    var IX: UInt16 = 0
    var IY: UInt16 = 0

    // Special Registers
    var SP: UInt16 = 0
    var PC: UInt16 = 0
    var I: UInt8 = 0
    var R: UInt8 = 0

    // Control Flags
    var iff1: Bool = false
    var iff2: Bool = false
    var im: UInt8 = 0

    // Z180 Specific Registers (Default values for SC131)
    var BBR: UInt8 = 0x00  // Bank Base Register
    var CBR: UInt8 = 0x00  // Common Base Register
    var CBAR: UInt8 = 0xF0  // Common/Bank Area Register

    // Memory and IO Interfaces
    var memory: Z180Memory?
    var io: Z180IO?

    // Statistics
    var cycles: UInt64 = 0
    var halted: Bool = false

    public init() {}

    // Helper property to access 16-bit registers
    var AF: UInt16 {
        get { return (UInt16(A) << 8) | UInt16(F) }
        set {
            A = UInt8(newValue >> 8)
            F = UInt8(newValue & 0xFF)
        }
    }

    var BC: UInt16 {
        get { return (UInt16(B) << 8) | UInt16(C) }
        set {
            B = UInt8(newValue >> 8)
            C = UInt8(newValue & 0xFF)
        }
    }

    var DE: UInt16 {
        get { return (UInt16(D) << 8) | UInt16(E) }
        set {
            D = UInt8(newValue >> 8)
            E = UInt8(newValue & 0xFF)
        }
    }

    var HL: UInt16 {
        get { return (UInt16(H) << 8) | UInt16(L) }
        set {
            H = UInt8(newValue >> 8)
            L = UInt8(newValue & 0xFF)
        }
    }

    // Methods for instruction fetching, decoding, and execution
    public func step() {
        if halted { return }

        let opcode = fetchByte()
        execute(opcode: opcode)
    }

    private func fetchByte() -> UInt8 {
        let byte = memory?.read(address: PC) ?? 0
        PC = PC &+ 1
        cycles = cycles &+ 4  // Basic fetch takes 4 cycles
        return byte
    }

    private func execute(opcode: UInt8) {
        switch opcode {
        case 0x00:  // NOP
            break
        case 0x01:  // LD BC, nn
            BC = fetchWord()
        case 0x18:  // JR e
            let offset = Int8(bitPattern: fetchByte())
            PC = UInt16(bitPattern: Int16(PC) + Int16(offset))
            cycles = cycles &+ 8
        case 0x3E:  // LD A, n
            A = fetchByte()
            cycles = cycles &+ 3
        case 0xC3:  // JP nn
            PC = fetchWord()
            cycles = cycles &+ 6
        case 0xD3:  // OUT (n), A
            let port = fetchByte()
            io?.write(port: UInt16(port), value: A)
            cycles = cycles &+ 7
        case 0xED:  // Extended instructions
            executeExtended()
        default:
            // For now, treat unknown as NOP to allow flow
            print(
                "Unknown opcode: \(String(format: "0x%02X", opcode)) at \(String(format: "0x%04X", PC - 1))"
            )
        }
    }

    private func fetchWord() -> UInt16 {
        let low = fetchByte()
        let high = fetchByte()
        return (UInt16(high) << 8) | UInt16(low)
    }

    private func executeExtended() {
        let extOp = fetchByte()
        switch extOp {
        case 0x00...0x3F:  // Z180 Specific: IN0, OUT0, TST, etc.
            executeZ180(opcode: extOp)
        default:
            print("Unknown extended opcode: 0xED \(String(format: "0x%02X", extOp))")
        }
    }

    private func executeZ180(opcode: UInt8) {
        // Z180 specific instructions
        let regBit = (opcode >> 3) & 0x07
        let isOut = (opcode & 0x01) == 1

        if (opcode & 0xC7) == 0x00 {  // IN0 R, (n) / OUT0 (n), R
            let port = fetchByte()
            if isOut {
                io?.write(port: UInt16(port), value: getReg8(regBit))
            } else {
                setReg8(regBit, value: io?.read(port: UInt16(port)) ?? 0xFF)
            }
        }
    }

    private func getReg8(_ bit: UInt8) -> UInt8 {
        switch bit {
        case 0: return B
        case 1: return C
        case 2: return D
        case 3: return E
        case 4: return H
        case 5: return L
        case 6: return memory?.read(address: HL) ?? 0
        case 7: return A
        default: return 0
        }
    }

    private func setReg8(_ bit: UInt8, value: UInt8) {
        // Correct register mapping: 0=B, 1=C, 2=D, 3=E, 4=H, 5=L, 6=(HL), 7=A
        if bit == 0 {
            B = value
        } else if bit == 1 {
            C = value
        } else if bit == 2 {
            D = value
        } else if bit == 3 {
            E = value
        } else if bit == 4 {
            H = value
        } else if bit == 5 {
            L = value
        } else if bit == 6 {
            memory?.write(address: HL, value: value)
        } else if bit == 7 {
            A = value
        }
    }
}

/// Protocols for Memory and IO
public protocol Z180Memory {
    func read(address: UInt16) -> UInt8
    func write(address: UInt16, value: UInt8)
    func readPhysical(address: UInt32) -> UInt8  // For 20-bit addressing
    func writePhysical(address: UInt32, value: UInt8)
}

public protocol Z180IO {
    func read(port: UInt16) -> UInt8
    func write(port: UInt16, value: UInt8)
}
