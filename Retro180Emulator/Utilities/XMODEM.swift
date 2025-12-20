import Foundation

/// XMODEM-CRC implementation for transferring files to the emulator.
public class XMODEM {
    private let SOH: UInt8 = 0x01
    private let EOT: UInt8 = 0x04
    private let ACK: UInt8 = 0x06
    private let NAK: UInt8 = 0x15
    private let CAN: UInt8 = 0x18
    private let CRC_MODE: UInt8 = 0x43  // 'C'

    public enum TransferEvent {
        case sendByte(UInt8)
        case complete
        case error(String)
    }

    private var fileData: Data
    private var blockNumber: UInt8 = 1
    private var callback: (TransferEvent) -> Void
    private var sentEOT = false  // Track if we have already sent the End of Transmission

    public init(data: Data, callback: @escaping (TransferEvent) -> Void) {
        self.fileData = data
        self.callback = callback
    }

    public func handleByte(_ byte: UInt8) {
        switch byte {
        case CRC_MODE, NAK:
            if !sentEOT {
                print("XMODEM: Receiver requested retransmit/start (NAK/C)")
                sendBlock()
            }
        case ACK:
            if sentEOT {
                // We received ACK for our EOT. Transmission complete.
                print("XMODEM: EOT Acknowledged. Transfer complete.")
                callback(.complete)
                return
            }

            print("XMODEM: Block \(blockNumber) ACKed")
            blockNumber = blockNumber &+ 1
            if fileData.isEmpty {
                print("XMODEM: EOF reached. Sending EOT.")
                callback(.sendByte(EOT))
                sentEOT = true
            } else {
                sendBlock()
            }
        case CAN:
            print("XMODEM: Receiver Cancelled Transfer")
            callback(.error("Receiver cancelled transfer"))
        default:
            // Ignore other bytes
            break
        }
    }

    private func sendBlock() {
        guard !fileData.isEmpty else { return }

        var block = Data([SOH, blockNumber, ~blockNumber])
        let payloadSize = 128
        let payload = fileData.prefix(payloadSize)
        block.append(payload)

        // Pad with CPMEOF (0x1A) if needed
        if payload.count < payloadSize {
            block.append(Data(repeating: 0x1A, count: payloadSize - payload.count))
        }

        fileData = fileData.dropFirst(payloadSize)

        // Calculate CRC
        let crc = calculateCRC(block.dropFirst(3))
        block.append(UInt8(crc >> 8))
        block.append(UInt8(crc & 0xFF))

        for b in block {
            callback(.sendByte(b))
        }
    }

    private func calculateCRC(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc = crc ^ (UInt16(byte) << 8)
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
}
