import Foundation

/// Z180 I/O Dispatcher
/// Manages internal Z180 registers and external peripheral ports.
public class Z180IODispatcher: Z180IO {
    // Internal Z180 registers (usually 0x00-0x3F or relocated to 0xC0-0xFF)
    private var internalRegisters = [UInt8](repeating: 0, count: 64)
    private var internalBase: UInt16 = 0x00  // Default internal register base

    // External peripherals mapped by port range
    private var devices: [UInt16: ExternalDevice] = [:]

    public init() {}

    public func setInternalBase(_ base: UInt8) {
        self.internalBase = UInt16(base) & 0xC0
    }

    public func registerDevice(port: UInt16, device: ExternalDevice) {
        devices[port] = device
    }

    public func read(port: UInt16) -> UInt8 {
        // Check if an explicit device is registered for this port first
        if let device = devices[port] {
            return device.read(port: port)
        }

        // Check if it's an internal Z180 register
        if port >= internalBase && port < internalBase + 64 {
            let index = Int(port - internalBase)
            return internalRegisters[index]
        }

        return 0xFF  // Floating bus
    }

    public func write(port: UInt16, value: UInt8) {
        // Dispatch to device if registered
        if let device = devices[port] {
            device.write(port: port, value: value)
            // We don't return here if it's also an internal register, 
            // as we may need to handle internal logic (like ICR relocation)
        }

        // Check if it's an internal Z180 register
        if port >= internalBase && port < internalBase + 64 {
            let index = Int(port - internalBase)
            internalRegisters[index] = value
            handleInternalWrite(index: index, value: value)
        }
    }

    private func handleInternalWrite(index: Int, value: UInt8) {
        if index == 0x3F {
            // ICR - I/O Control Register
            setInternalBase(value & 0xC0)
        }
    }
}

public protocol ExternalDevice {
    func read(port: UInt16) -> UInt8
    func write(port: UInt16, value: UInt8)
}
