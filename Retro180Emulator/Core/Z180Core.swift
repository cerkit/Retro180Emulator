import Foundation

/// Z180 CPU Registers and State
public class Z180CPU {
    // 8-bit Main Registers
    public var A: UInt8 = 0, F: UInt8 = 0
    public var B: UInt8 = 0, C: UInt8 = 0
    public var D: UInt8 = 0, E: UInt8 = 0
    public var H: UInt8 = 0, L: UInt8 = 0

    // 8-bit Alternate Registers
    public var A_prime: UInt8 = 0, F_prime: UInt8 = 0
    public var B_prime: UInt8 = 0, C_prime: UInt8 = 0
    public var D_prime: UInt8 = 0, E_prime: UInt8 = 0
    public var H_prime: UInt8 = 0, L_prime: UInt8 = 0

    // 16-bit Index/Special Registers
    public var IX: UInt16 = 0, IY: UInt16 = 0
    public var SP: UInt16 = 0, PC: UInt16 = 0
    public var I: UInt8 = 0, R: UInt8 = 0
    public var IL: UInt8 = 0  // Interrupt Lower Vector (Z180)

    // Interrupts and Control
    public var IFF1: Bool = false
    public var IFF2: Bool = false
    public var IM: UInt8 = 0  // Interrupt Mode
    public var halted: Bool = false
    public var cycles: UInt64 = 0

    // Flag Masks
    static let FlagS: UInt8 = 0x80
    static let FlagZ: UInt8 = 0x40
    static let FlagH: UInt8 = 0x10
    static let FlagPV: UInt8 = 0x04
    static let FlagN: UInt8 = 0x02
    static let FlagC: UInt8 = 0x01

    // Flag Helpers
    var flagS: Bool {
        get { (F & Z180CPU.FlagS) != 0 }
        set { if newValue { F |= Z180CPU.FlagS } else { F &= ~Z180CPU.FlagS } }
    }
    var flagZ: Bool {
        get { (F & Z180CPU.FlagZ) != 0 }
        set { if newValue { F |= Z180CPU.FlagZ } else { F &= ~Z180CPU.FlagZ } }
    }
    var flagH: Bool {
        get { (F & Z180CPU.FlagH) != 0 }
        set { if newValue { F |= Z180CPU.FlagH } else { F &= ~Z180CPU.FlagH } }
    }
    var flagPV: Bool {
        get { (F & Z180CPU.FlagPV) != 0 }
        set { if newValue { F |= Z180CPU.FlagPV } else { F &= ~Z180CPU.FlagPV } }
    }
    var flagN: Bool {
        get { (F & Z180CPU.FlagN) != 0 }
        set { if newValue { F |= Z180CPU.FlagN } else { F &= ~Z180CPU.FlagN } }
    }
    var flagC: Bool {
        get { (F & Z180CPU.FlagC) != 0 }
        set { if newValue { F |= Z180CPU.FlagC } else { F &= ~Z180CPU.FlagC } }
    }

    public var memory: Z180Memory?
    public var io: Z180IO?

    public init() {}

    // 16-bit Pair Getters/Setters
    var AF: UInt16 {
        get { (UInt16(A) << 8) | UInt16(F) }
        set {
            A = UInt8(newValue >> 8)
            F = UInt8(newValue & 0xFF)
        }
    }
    var BC: UInt16 {
        get { (UInt16(B) << 8) | UInt16(C) }
        set {
            B = UInt8(newValue >> 8)
            C = UInt8(newValue & 0xFF)
        }
    }
    var DE: UInt16 {
        get { (UInt16(D) << 8) | UInt16(E) }
        set {
            D = UInt8(newValue >> 8)
            E = UInt8(newValue & 0xFF)
        }
    }
    var HL: UInt16 {
        get { (UInt16(H) << 8) | UInt16(L) }
        set {
            H = UInt8(newValue >> 8)
            L = UInt8(newValue & 0xFF)
        }
    }

    public func step() {
        if halted {
            checkInterrupts()
            if !halted { cycles = cycles &+ 4 }
            return
        }
        checkInterrupts()
        if !halted {
            let opcode = fetchByte()
            execute(opcode: opcode)
        }
    }

    private func checkInterrupts() {
        if !IFF1 { return }
        if let vector = io?.checkInterrupts() {
            acknowledgeInterrupt(vector: vector)
        }
    }

    private func acknowledgeInterrupt(vector: UInt8) {
        // Read IL for debug context if possible (cast IO)
        if let dispatcher = io as? Z180IODispatcher {
            // Access IL at index 0x33 directly from internal registers provided we can expose them?
            // Or typically we trigger a read?
            // Let's just trust the vector passed in is (IL | Offset).
            // But we want to see 'I'.
        }

        if IM == 2 {
            let tableAddr = (UInt16(I) << 8) | UInt16(vector)
            let low = memory?.read(address: tableAddr) ?? 0
            let high = memory?.read(address: tableAddr + 1) ?? 0
            let target = (UInt16(high) << 8) | UInt16(low)
            print(
                "CPU: INT Ack Vector=0x\(String(vector, radix: 16)) (I=0x\(String(I, radix: 16)) Table=0x\(String(tableAddr, radix: 16))) -> Target 0x\(String(target, radix: 16))"
            )

            IFF1 = false
            IFF2 = false
            push(PC)
            PC = target
        } else {
            print("CPU: INT Ack Vector=0x\(String(vector, radix: 16)) (IM \(IM))")
            IFF1 = false
            IFF2 = false
            // Handle IM 0/1...
            if IM == 1 {
                push(PC)
                PC = 0x38
            }
        }
        halted = false
        cycles = cycles &+ 12
    }

    public func readByte(_ address: UInt16) -> UInt8 {
        cycles = cycles &+ 3
        return memory?.read(address: address) ?? 0xFF
    }

    public func writeByte(_ address: UInt16, _ value: UInt8) {
        cycles = cycles &+ 3
        memory?.write(address: address, value: value)
    }

    public func readWord(_ address: UInt16) -> UInt16 {
        let low = readByte(address)
        let high = readByte(address &+ 1)
        return (UInt16(high) << 8) | UInt16(low)
    }

    public func writeWord(_ address: UInt16, _ value: UInt16) {
        writeByte(address, UInt8(value & 0xFF))
        writeByte(address &+ 1, UInt8(value >> 8))
    }

    public func push(_ value: UInt16) {
        SP = SP &- 2
        writeWord(SP, value)
    }
    public func pop() -> UInt16 {
        let val = readWord(SP)
        SP = SP &+ 2
        return val
    }

    public func fetchByte() -> UInt8 {
        let byte = memory?.read(address: PC) ?? 0
        PC = PC &+ 1
        R = R &+ 1
        cycles = cycles &+ 4
        return byte
    }

    public func fetchWord() -> UInt16 {
        let low = fetchByte()
        let high = fetchByte()
        return (UInt16(high) << 8) | UInt16(low)
    }

    // Flag logic helpers
    func updateFlagsSZ(_ val: UInt8) {
        F &= ~(Z180CPU.FlagS | Z180CPU.FlagZ)
        if (val & 0x80) != 0 { F |= Z180CPU.FlagS }
        if val == 0 { F |= Z180CPU.FlagZ }
    }

    func updateFlagsSZP(_ val: UInt8) {
        updateFlagsSZ(val)
        F &= ~Z180CPU.FlagPV
        if parity(val) { F |= Z180CPU.FlagPV }
    }

    func parity(_ val: UInt8) -> Bool {
        var p = val ^ (val >> 4)
        p ^= (p >> 2)
        p ^= (p >> 1)
        return (p & 1) == 0
    }

    private func execute(opcode: UInt8) {
        switch opcode {
        case 0xCB: executeCB()
        case 0xED: executeED()
        case 0xDD: executeIndex(&IX, fetchByte())
        case 0xFD: executeIndex(&IY, fetchByte())
        default: executeBase(opcode: opcode)
        }
    }

    func getReg8(_ index: UInt8) -> UInt8 {
        switch index {
        case 0: return B
        case 1: return C
        case 2: return D
        case 3: return E
        case 4: return H
        case 5: return L
        case 6: return readByte(HL)
        case 7: return A
        default: return 0
        }
    }

    func setReg8(_ index: UInt8, _ value: UInt8) {
        switch index {
        case 0: B = value
        case 1: C = value
        case 2: D = value
        case 3: E = value
        case 4: H = value
        case 5: L = value
        case 6: writeByte(HL, value)
        case 7: A = value
        default: break
        }
    }
}

extension Z180CPU {
    func executeBase(opcode: UInt8) {
        switch opcode {
        case 0x00: break
        case 0x01: BC = fetchWord()
        case 0x02: writeByte(BC, A)
        case 0x03: BC = BC &+ 1
        case 0x04: B = inc8(B)
        case 0x05: B = dec8(B)
        case 0x06: B = fetchByte()
        case 0x07: rlca()
        case 0x08:
            let tmpA = A
            let tmpF = F
            A = A_prime
            F = F_prime
            A_prime = tmpA
            F_prime = tmpF
        case 0x09: HL = addHL(HL, val2: BC)
        case 0x0A: A = readByte(BC)
        case 0x0B: BC = BC &- 1
        case 0x0C: C = inc8(C)
        case 0x0D: C = dec8(C)
        case 0x0E: C = fetchByte()
        case 0x0F: rrca()
        case 0x10:
            let offset = Int8(bitPattern: fetchByte())
            B = B &- 1
            if B != 0 { PC = PC &+ UInt16(bitPattern: Int16(offset)) }
        case 0x11: DE = fetchWord()
        case 0x12: writeByte(DE, A)
        case 0x13: DE = DE &+ 1
        case 0x14: D = inc8(D)
        case 0x15: D = dec8(D)
        case 0x16: D = fetchByte()
        case 0x17: rla()
        case 0x18:
            let offset = Int8(bitPattern: fetchByte())
            PC = PC &+ UInt16(bitPattern: Int16(offset))
        case 0x19: HL = addHL(HL, val2: DE)
        case 0x1A: A = readByte(DE)
        case 0x1B: DE = DE &- 1
        case 0x1C: E = inc8(E)
        case 0x1D: E = dec8(E)
        case 0x1E: E = fetchByte()
        case 0x1F: rra()
        case 0x20:
            let o = Int8(bitPattern: fetchByte())
            if !flagZ { PC = PC &+ UInt16(bitPattern: Int16(o)) }
        case 0x21: HL = fetchWord()
        case 0x22:
            let a = fetchWord()
            writeWord(a, HL)
        case 0x23: HL = HL &+ 1
        case 0x24: H = inc8(H)
        case 0x25: H = dec8(H)
        case 0x26: H = fetchByte()
        case 0x27: daa()
        case 0x28:
            let o = Int8(bitPattern: fetchByte())
            if flagZ { PC = PC &+ UInt16(bitPattern: Int16(o)) }
        case 0x29: HL = addHL(HL, val2: HL)
        case 0x2A:
            let a = fetchWord()
            HL = readWord(a)
        case 0x2B: HL = HL &- 1
        case 0x2C: L = inc8(L)
        case 0x2D: L = dec8(L)
        case 0x2E: L = fetchByte()
        case 0x2F:
            A = ~A
            flagH = true
            flagN = true
        case 0x30:
            let o = Int8(bitPattern: fetchByte())
            if !flagC { PC = PC &+ UInt16(bitPattern: Int16(o)) }
        case 0x31: SP = fetchWord()
        case 0x32:
            let a = fetchWord()
            writeByte(a, A)
        case 0x33: SP = SP &+ 1
        case 0x34:
            let v = readByte(HL)
            writeByte(HL, inc8(v))
        case 0x35:
            let v = readByte(HL)
            writeByte(HL, dec8(v))
        case 0x36: writeByte(HL, fetchByte())
        case 0x37:
            flagC = true
            flagH = false
            flagN = false
        case 0x38:
            let o = Int8(bitPattern: fetchByte())
            if flagC { PC = PC &+ UInt16(bitPattern: Int16(o)) }
        case 0x39: HL = addHL(HL, val2: SP)
        case 0x3A:
            let a = fetchWord()
            A = readByte(a)
        case 0x3B: SP = SP &- 1
        case 0x3C: A = inc8(A)
        case 0x3D: A = dec8(A)
        case 0x3E: A = fetchByte()
        case 0x3F:
            flagH = flagC
            flagC = !flagC
            flagN = false
        case 0x40...0x75, 0x77...0x7F: setReg8((opcode >> 3) & 0x07, getReg8(opcode & 0x07))
        case 0x76: halted = true
        case 0x80...0x87: addA(getReg8(opcode & 0x07), cf: false)
        case 0x88...0x8F: addA(getReg8(opcode & 0x07), cf: true)
        case 0x90...0x97: subA(getReg8(opcode & 0x07), cf: false)
        case 0x98...0x9F: subA(getReg8(opcode & 0x07), cf: true)
        case 0xA0...0xA7: andA(getReg8(opcode & 0x07))
        case 0xA8...0xAF: xorA(getReg8(opcode & 0x07))
        case 0xB0...0xB7: orA(getReg8(opcode & 0x07))
        case 0xB8...0xBF: cpA(getReg8(opcode & 0x07))
        case 0xC0: if !flagZ { ret() }
        case 0xC1: BC = pop()
        case 0xC2:
            let a = fetchWord()
            if !flagZ { PC = a }
        case 0xC3: PC = fetchWord()
        case 0xC4:
            let a = fetchWord()
            if !flagZ { call(a) }
        case 0xC5: push(BC)
        case 0xC6: addA(fetchByte(), cf: false)
        case 0xC7: call(0x0000)
        case 0xC8: if flagZ { ret() }
        case 0xC9: ret()
        case 0xCA:
            let a = fetchWord()
            if flagZ { PC = a }
        case 0xCC:
            let a = fetchWord()
            if flagZ { call(a) }
        case 0xCD: call(fetchWord())
        case 0xCE: addA(fetchByte(), cf: true)
        case 0xCF: call(0x0008)
        case 0xD0: if !flagC { ret() }
        case 0xD1: DE = pop()
        case 0xD2:
            let a = fetchWord()
            if !flagC { PC = a }
        case 0xD3: io?.write(port: UInt16(fetchByte()), value: A)
        case 0xD4:
            let a = fetchWord()
            if !flagC { call(a) }
        case 0xD5: push(DE)
        case 0xD6: subA(fetchByte(), cf: false)
        case 0xD7: call(0x0010)
        case 0xD8: if flagC { ret() }
        case 0xD9: exx()
        case 0xDA:
            let a = fetchWord()
            if flagC { PC = a }
        case 0xDB: A = io?.read(port: UInt16(fetchByte())) ?? 0xFF
        case 0xDC:
            let a = fetchWord()
            if flagC { call(a) }
        case 0xDE: subA(fetchByte(), cf: true)
        case 0xDF: call(0x0018)
        case 0xE0: if !flagPV { ret() }
        case 0xE1: HL = pop()
        case 0xE2:
            let a = fetchWord()
            if !flagPV { PC = a }
        case 0xE3:
            let v = readWord(SP)
            writeWord(SP, HL)
            HL = v
        case 0xE4:
            let a = fetchWord()
            if !flagPV { call(a) }
        case 0xE5: push(HL)
        case 0xE6: andA(fetchByte())
        case 0xE7: call(0x0020)
        case 0xE8: if flagPV { ret() }
        case 0xE9: PC = HL
        case 0xEA:
            let a = fetchWord()
            if flagPV { PC = a }
        case 0xEB:
            let t = DE
            DE = HL
            HL = t
        case 0xEC:
            let a = fetchWord()
            if flagPV { call(a) }
        case 0xEE: xorA(fetchByte())
        case 0xEF: call(0x0028)
        case 0xF0: if !flagS { ret() }
        case 0xF1: AF = pop()
        case 0xF2:
            let a = fetchWord()
            if !flagS { PC = a }
        case 0xF3:
            IFF1 = false
            IFF2 = false
        case 0xF4:
            let a = fetchWord()
            if !flagS { call(a) }
        case 0xF5: push(AF)
        case 0xF6: orA(fetchByte())
        case 0xF7: call(0x0030)
        case 0xF8: if flagS { ret() }
        case 0xF9: SP = HL
        case 0xFA:
            let a = fetchWord()
            if flagS { PC = a }
        case 0xFB:
            IFF1 = true
            IFF2 = true
        case 0xFC:
            let a = fetchWord()
            if flagS { call(a) }
        case 0xFE: cpA(fetchByte())
        case 0xFF: call(0x0038)
        default: break
        }
    }

    func executeCB() {
        let opcode = fetchByte()
        let reg = opcode & 0x07
        var val = getReg8(reg)
        switch opcode & 0xF8 {
        case 0x00: val = rlc(val)
        case 0x08: val = rrc(val)
        case 0x10: val = rl(val)
        case 0x18: val = rr(val)
        case 0x20: val = sla(val)
        case 0x28: val = sra(val)
        case 0x30: val = sll(val)
        case 0x38: val = srl(val)
        case 0x40...0x78:
            bitCheck(val, (opcode >> 3) & 0x07)
            return
        case 0x80...0xB8: val &= ~(1 << ((opcode >> 3) & 0x07))
        case 0xC0...0xF8: val |= (1 << ((opcode >> 3) & 0x07))
        default: break
        }
        setReg8(reg, val)
    }

    func executeED() {
        let opcode = fetchByte()
        switch opcode {
        case 0x40, 0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78:
            let r = (opcode >> 3) & 7
            let res = io?.read(port: BC) ?? 0xFF
            if r != 6 { setReg8(r, res) }
            updateFlagsSZP(res)
            flagN = false
            flagH = false
        case 0x41, 0x49, 0x51, 0x59, 0x61, 0x69, 0x71, 0x79:
            io?.write(port: BC, value: getReg8((opcode >> 3) & 7))
        case 0x42, 0x52, 0x62, 0x72: sbc16(getReg16(opcode))
        case 0x4A, 0x5A, 0x6A, 0x7A: adc16(getReg16(opcode))
        case 0x43, 0x53, 0x63, 0x73: writeWord(fetchWord(), getReg16(opcode))
        case 0x4B, 0x5B, 0x6B, 0x7B: setReg16(opcode, value: readWord(fetchWord()))
        case 0x44: neg()
        case 0x45, 0x4D:
            ret()
            IFF1 = IFF2  // RETN/RETI
        case 0x46, 0x4E, 0x66, 0x6E: IM = 0
        case 0x56, 0x76: IM = 1
        case 0x5E, 0x7E: IM = 2
        case 0x47: I = A
        case 0x4F: R = A
        case 0x57:
            A = I
            updateFlagsSZP(A)
        case 0x5F:
            A = R
            updateFlagsSZP(A)
        case 0xA0: ldi()
        case 0xA1: cpi()
        case 0xA2: ini()
        case 0xA3: outi()
        case 0xA8: ldd()
        case 0xA9: cpd()
        case 0xAA: ind()
        case 0xAB: outd()
        case 0xB0:
            ldi()
            if BC != 0 { PC = PC &- 2 }  // LDIR
        case 0xB1:
            cpi()
            if BC != 0 && !flagZ { PC = PC &- 2 }  // CPIR
        case 0xB2:
            ini()
            if B != 0 { PC = PC &- 2 }  // INIR
        case 0xB3:
            outi()
            if B != 0 { PC = PC &- 2 }  // OTIR
        case 0xB8:
            ldd()
            if BC != 0 { PC = PC &- 2 }  // LDDR
        case 0xB9:
            cpd()
            if BC != 0 && !flagZ { PC = PC &- 2 }  // CPDR
        case 0xBA:
            ind()
            if B != 0 { PC = PC &- 2 }  // INDR
        case 0xBB:
            outd()
            if B != 0 { PC = PC &- 2 }  // OTDR
        case 0x4C, 0x5C, 0x6C, 0x7C: mlt(opcode)
        case 0x64, 0x74: tst(getReg8((opcode >> 3) & 7))
        case 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C: tst(fetchByte())
        case 0x00, 0x10, 0x20, 0x30, 0x08, 0x18, 0x28, 0x38:
            let p = fetchByte()
            let res = io?.read(port: UInt16(p)) ?? 0xFF
            setReg8((opcode >> 3) & 7, res)
            updateFlagsSZP(res)
            flagN = false
            flagH = false
        case 0x01, 0x11, 0x21, 0x31, 0x09, 0x19, 0x29, 0x39:
            let p = fetchByte()
            io?.write(port: UInt16(p), value: getReg8((opcode >> 3) & 7))
        case 0x83:
            let p = fetchByte()
            otim(port: p)  // OTIM
        case 0x93:
            let p = fetchByte()
            otim(port: p)
            if B != 0 { PC = PC &- 2 }  // OTIMR
        case 0x8B:
            let p = fetchByte()
            otdm(port: p)  // OTDM
        case 0x9B:
            let p = fetchByte()
            otdm(port: p)
            if B != 0 { PC = PC &- 2 }  // OTDMR
        case 0x67: rrd()
        case 0x6F: rld()
        default: break
        }
    }

    func executeIndex(_ reg: inout UInt16, _ opcode: UInt8) {
        switch opcode {
        case 0x21: reg = fetchWord()
        case 0x22: writeWord(fetchWord(), reg)
        case 0x2A: reg = readWord(fetchWord())
        case 0x23: reg = reg &+ 1
        case 0x2B: reg = reg &- 1
        case 0x09: reg = addHL(reg, val2: BC)
        case 0x19: reg = addHL(reg, val2: DE)
        case 0x29: reg = addHL(reg, val2: reg)
        case 0x39: reg = addHL(reg, val2: SP)
        case 0xE1: reg = pop()
        case 0xE5: push(reg)
        case 0xF9: SP = reg
        case 0xE9: PC = reg
        case 0xE3:
            let v = readWord(SP)
            writeWord(SP, reg)
            reg = v
        case 0x34...0xBE:
            let d = Int8(bitPattern: fetchByte())
            let addr = reg &+ UInt16(bitPattern: Int16(d))
            switch opcode {
            case 0x34: writeByte(addr, inc8(readByte(addr)))
            case 0x35: writeByte(addr, dec8(readByte(addr)))
            case 0x36: writeByte(addr, fetchByte())
            case 0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E, 0x7E:
                setReg8((opcode >> 3) & 0x07, readByte(addr))
            case 0x70...0x75, 0x77: writeByte(addr, getReg8(opcode & 0x07))
            case 0x86: addA(readByte(addr), cf: false)
            case 0x8E: addA(readByte(addr), cf: true)
            case 0x96: subA(readByte(addr), cf: false)
            case 0x9E: subA(readByte(addr), cf: true)
            case 0xA6: andA(readByte(addr))
            case 0xAE: xorA(readByte(addr))
            case 0xB6: orA(readByte(addr))
            case 0xBE: cpA(readByte(addr))
            default: break
            }
        default: executeBase(opcode: opcode)
        }
    }

    func getReg16(_ opcode: UInt8) -> UInt16 {
        switch (opcode >> 4) & 0x03 {
        case 0: return BC
        case 1: return DE
        case 2: return HL
        case 3: return SP
        default: return 0
        }
    }
    func setReg16(_ opcode: UInt8, value: UInt16) {
        switch (opcode >> 4) & 0x03 {
        case 0: BC = value
        case 1: DE = value
        case 2: HL = value
        case 3: SP = value
        default: break
        }
    }

    func inc8(_ val: UInt8) -> UInt8 {
        let res = val &+ 1
        flagN = false
        flagH = (val & 0x0F) == 0x0F
        flagPV = val == 0x7F
        flagZ = res == 0
        flagS = (res & 0x80) != 0
        return res
    }
    func dec8(_ val: UInt8) -> UInt8 {
        let res = val &- 1
        flagN = true
        flagH = (val & 0x0F) == 0x00
        flagPV = val == 0x80
        flagZ = res == 0
        flagS = (res & 0x80) != 0
        return res
    }
    func addA(_ v: UInt8, cf: Bool) {
        let c: UInt16 = cf && flagC ? 1 : 0
        let res = UInt16(A) + UInt16(v) + c
        flagH = (A & 0xF) + (v & 0xF) + UInt8(c) > 0xF
        flagPV = ((A ^ v ^ 0x80) & (v ^ UInt8(res & 0xFF)) & 0x80) != 0
        flagC = res > 0xFF
        flagN = false
        A = UInt8(res & 0xFF)
        updateFlagsSZ(A)
    }
    func subA(_ v: UInt8, cf: Bool) {
        let c: UInt16 = (cf && flagC) ? 1 : 0
        let res = Int16(A) - Int16(v) - Int16(c)
        flagH = Int16(A & 0xF) - Int16(v & 0xF) - Int16(c) < 0
        flagPV = ((A ^ v) & (A ^ UInt8(res & 0xFF)) & 0x80) != 0
        flagC = res < 0
        flagN = true
        A = UInt8(bitPattern: Int8(truncatingIfNeeded: res))
        updateFlagsSZ(A)
    }
    func andA(_ v: UInt8) {
        A &= v
        F = 0
        updateFlagsSZP(A)
        flagH = true
    }
    func orA(_ v: UInt8) {
        A |= v
        F = 0
        updateFlagsSZP(A)
    }
    func xorA(_ v: UInt8) {
        A ^= v
        F = 0
        updateFlagsSZP(A)
    }
    func cpA(_ v: UInt8) {
        let t = A
        subA(v, cf: false)
        A = t
    }
    func addHL(_ v1: UInt16, val2: UInt16) -> UInt16 {
        let res = UInt32(v1) + UInt32(val2)
        flagC = res > 0xFFFF
        flagH = (v1 & 0x0FFF) + (val2 & 0x0FFF) > 0x0FFF
        flagN = false
        return UInt16(res & 0xFFFF)
    }
    func sbc16(_ v: UInt16) {
        let c: UInt32 = flagC ? 1 : 0
        let res = Int32(HL) - Int32(v) - Int32(c)
        flagN = true
        flagC = res < 0
        flagZ = (res & 0xFFFF) == 0
        flagS = (res & 0x8000) != 0
        flagH = Int32(HL & 0xFFF) - Int32(v & 0xFFF) - Int32(c) < 0
        flagPV =
            ((HL ^ v) & (HL ^ UInt16(bitPattern: Int16(truncatingIfNeeded: res))) & 0x8000) != 0
        HL = UInt16(bitPattern: Int16(truncatingIfNeeded: res))
    }
    func adc16(_ v: UInt16) {
        let c: UInt32 = flagC ? 1 : 0
        let res = UInt32(HL) + UInt32(v) + c
        flagN = false
        flagC = res > 0xFFFF
        flagZ = (res & 0xFFFF) == 0
        flagS = (res & 0x8000) != 0
        flagH = (HL & 0xFFF) + (v & 0xFFF) + UInt16(c) > 0xFFF
        flagPV = ((HL ^ v ^ 0x8000) & (v ^ UInt16(res & 0xFFFF)) & 0x8000) != 0
        HL = UInt16(res & 0xFFFF)
    }
    func tst(_ v: UInt8) {
        let r = A & v
        updateFlagsSZP(r)
        flagH = true
        flagN = false
        flagC = false
    }
    func rlc(_ v: UInt8) -> UInt8 {
        let c = (v & 0x80) != 0
        let r = (v << 1) | (c ? 1 : 0)
        flagC = c
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func rrc(_ v: UInt8) -> UInt8 {
        let c = (v & 0x01) != 0
        let r = (v >> 1) | (c ? 0x80 : 0)
        flagC = c
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func rl(_ v: UInt8) -> UInt8 {
        let c = flagC
        let r = (v << 1) | (c ? 1 : 0)
        flagC = (v & 0x80) != 0
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func rr(_ v: UInt8) -> UInt8 {
        let c = flagC
        let r = (v >> 1) | (c ? 0x80 : 0)
        flagC = (v & 0x01) != 0
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func sla(_ v: UInt8) -> UInt8 {
        flagC = (v & 0x80) != 0
        let r = v << 1
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func sra(_ v: UInt8) -> UInt8 {
        flagC = (v & 0x01) != 0
        let r = (v & 0x80) | (v >> 1)
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func sll(_ v: UInt8) -> UInt8 {
        flagC = (v & 0x80) != 0
        let r = (v << 1) | 1
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func srl(_ v: UInt8) -> UInt8 {
        flagC = (v & 0x01) != 0
        let r = v >> 1
        flagH = false
        flagN = false
        updateFlagsSZP(r)
        return r
    }
    func bitCheck(_ v: UInt8, _ b: UInt8) {
        let r = v & (1 << b)
        flagZ = r == 0
        flagH = true
        flagN = false
        flagS = (b == 7) && (r != 0)
    }
    func rlca() {
        let c = (A & 0x80) != 0
        A = (A << 1) | (c ? 1 : 0)
        flagC = c
        flagH = false
        flagN = false
    }
    func rrca() {
        let c = (A & 0x01) != 0
        A = (A >> 1) | (c ? 0x80 : 0)
        flagC = c
        flagH = false
        flagN = false
    }
    func rla() {
        let c = flagC
        flagC = (A & 0x80) != 0
        A = (A << 1) | (c ? 1 : 0)
        flagH = false
        flagN = false
    }
    func rra() {
        let c = flagC
        flagC = (A & 0x01) != 0
        A = (A >> 1) | (c ? 0x80 : 0)
        flagH = false
        flagN = false
    }
    func daa() {
        var f: UInt8 = 0
        if flagH || (A & 0xF) > 9 { f |= 0x06 }
        if flagC || A > 0x99 {
            f |= 0x60
            flagC = true
        }
        if flagN { subA(f, cf: false) } else { addA(f, cf: false) }
    }
    func call(_ a: UInt16) {
        push(PC)
        PC = a
    }
    func ret() { PC = pop() }
    func exx() {
        let tBC = BC
        let tDE = DE
        let tHL = HL
        BC = (UInt16(B_prime) << 8) | UInt16(C_prime)
        DE = (UInt16(D_prime) << 8) | UInt16(E_prime)
        HL = (UInt16(H_prime) << 8) | UInt16(L_prime)
        B_prime = UInt8(tBC >> 8)
        C_prime = UInt8(tBC & 0xFF)
        D_prime = UInt8(tDE >> 8)
        E_prime = UInt8(tDE & 0xFF)
        H_prime = UInt8(tHL >> 8)
        L_prime = UInt8(tHL & 0xFF)
    }
    func neg() {
        let oA = A
        A = 0 &- oA
        flagS = (A & 0x80) != 0
        flagZ = A == 0
        flagH = (0 & 0xF) &- (oA & 0xF) < 0
        flagPV = oA == 0x80
        flagN = true
        flagC = oA != 0
    }
    func rrd() {
        let v = readByte(HL)
        let lA = A & 0xF
        let lM = v & 0xF
        let hM = v >> 4
        A = (A & 0xF0) | lM
        writeByte(HL, (lA << 4) | hM)
        updateFlagsSZP(A)
        flagH = false
        flagN = false
    }
    func rld() {
        let v = readByte(HL)
        let lA = A & 0xF
        let hM = v >> 4
        let lM = v & 0xF
        A = (A & 0xF0) | hM
        writeByte(HL, (lM << 4) | lA)
        updateFlagsSZP(A)
        flagH = false
        flagN = false
    }
    func ldi() {
        let v = readByte(HL)
        writeByte(DE, v)
        HL = HL &+ 1
        DE = DE &+ 1
        BC = BC &- 1
        flagN = false
        flagH = false
        flagPV = BC != 0
    }
    func ldd() {
        let v = readByte(HL)
        writeByte(DE, v)
        HL = HL &- 1
        DE = DE &- 1
        BC = BC &- 1
        flagN = false
        flagH = false
        flagPV = BC != 0
    }
    func cpi() {
        let v = readByte(HL)
        let oC = flagC
        cpA(v)
        flagC = oC
        HL = HL &+ 1
        BC = BC &- 1
        flagPV = BC != 0
    }
    func cpd() {
        let v = readByte(HL)
        let oC = flagC
        cpA(v)
        flagC = oC
        HL = HL &- 1
        BC = BC &- 1
        flagPV = BC != 0
    }
    func ini() {
        let v = io?.read(port: BC) ?? 0xFF
        writeByte(HL, v)
        HL = HL &+ 1
        B = B &- 1
        flagZ = B == 0
        flagN = true
    }
    func ind() {
        let v = io?.read(port: BC) ?? 0xFF
        writeByte(HL, v)
        HL = HL &- 1
        B = B &- 1
        flagZ = B == 0
        flagN = true
    }
    func outi() {
        let v = readByte(HL)
        io?.write(port: BC, value: v)
        HL = HL &+ 1
        B = B &- 1
        flagZ = B == 0
        flagN = true
    }
    func outd() {
        let v = readByte(HL)
        io?.write(port: BC, value: v)
        HL = HL &- 1
        B = B &- 1
        flagZ = B == 0
        flagN = true
    }
    func otim(port: UInt8) {
        let v = readByte(HL)
        io?.write(port: UInt16(port), value: v)
        HL = HL &+ 1
        B = B &- 1
        flagN = true
        flagZ = B == 0
    }
    func otdm(port: UInt8) {
        let v = readByte(HL)
        io?.write(port: UInt16(port), value: v)
        HL = HL &- 1
        B = B &- 1
        flagN = true
        flagZ = B == 0
    }
    func mlt(_ oc: UInt8) {
        let r = (oc >> 4) & 3
        switch r {
        case 0: BC = UInt16(B) * UInt16(C)
        case 1: DE = UInt16(D) * UInt16(E)
        case 2: HL = UInt16(H) * UInt16(L)
        case 3: SP = UInt16(SP >> 8) * UInt16(SP & 0xFF)
        default: break
        }
    }
}

public protocol Z180Memory {
    func read(address: UInt16) -> UInt8
    func write(address: UInt16, value: UInt8)
}

public protocol Z180IO {
    func read(port: UInt16) -> UInt8
    func write(port: UInt16, value: UInt8)
    func checkInterrupts() -> UInt8?
}
