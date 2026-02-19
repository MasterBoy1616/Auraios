import Foundation
import CommonCrypto

/**
 * BLE-only packet framing and chunking for manufacturer data
 * Max payload: 24 bytes after companyId (0xFFFF)
 *
 * Packet format:
 * Byte0: version (0x01)
 * Byte1: type (0x01=PRESENCE, 0x02=MATCH_REQ, 0x03=MATCH_ACC, 0x04=MATCH_REJ, 0x05=CHAT)
 * Byte2..5: senderHash (4 bytes)
 * Byte6..9: targetHash (4 bytes) (0x00000000 if broadcast/presence)
 * Byte10: msgId (0..255 rolling)
 * Byte11: chunkIndex
 * Byte12: chunkTotal
 * Byte13..(end): chunkData (UTF-8 bytes for chat OR reserved for match)
 */

enum BLEPacketType: UInt8 {
    case presence = 0x01
    case matchRequest = 0x02
    case matchAccept = 0x03
    case matchReject = 0x04
    case chatMessage = 0x05
    case unmatch = 0x06
    case block = 0x07
}

struct BLEPacket {
    // MARK: - DecodedFrame (for BLEManager compatibility)
    
    struct DecodedFrame {
        let type: UInt8
        let senderHash: Data
        let targetHash: Data
        let msgId: UInt8
        let chunkIndex: UInt8
        let chunkTotal: UInt8
        let chunkData: Data
        let isComplete: Bool
        let completeMessage: String?
    }
    
    // Company ID for manufacturer data
    static let companyId: UInt16 = 0xFFFF
    
    // Protocol version
    private static let version: UInt8 = 0x01
    
    // Packet type constants (for compatibility with BLEManager)
    static let TYPE_PRESENCE: UInt8 = 0x01
    static let TYPE_MATCH_REQ: UInt8 = 0x02
    static let TYPE_MATCH_ACC: UInt8 = 0x03
    static let TYPE_MATCH_REJ: UInt8 = 0x04
    static let TYPE_CHAT: UInt8 = 0x05
    static let TYPE_UNMATCH: UInt8 = 0x06
    static let TYPE_BLOCK: UInt8 = 0x07
    
    // Packet structure constants
    private static let headerSize = 13 // version + type + senderHash + targetHash + msgId + chunkIndex + chunkTotal
    private static let maxPayloadSize = 24 // Max manufacturer data payload after companyId
    private static let maxChunkData = maxPayloadSize - headerSize // 11 bytes per chunk
    
    let type: BLEPacketType
    let senderHash: Data
    let targetHash: Data
    let msgId: UInt8
    let chunkIndex: UInt8
    let chunkTotal: UInt8
    let chunkData: Data
    let isComplete: Bool
    let completeMessage: String?
    
    init(type: BLEPacketType, senderHash: Data, targetHash: Data, msgId: UInt8, chunkIndex: UInt8, chunkTotal: UInt8, chunkData: Data, isComplete: Bool = false, completeMessage: String? = nil) {
        self.type = type
        self.senderHash = senderHash
        self.targetHash = targetHash
        self.msgId = msgId
        self.chunkIndex = chunkIndex
        self.chunkTotal = chunkTotal
        self.chunkData = chunkData
        self.isComplete = isComplete
        self.completeMessage = completeMessage
    }
    
    // MARK: - Static Factory Methods
    
    static func createPresence(from senderHash: String) -> BLEPacket {
        let senderData = Data(hex: senderHash)
        let targetData = Data(count: 4) // Broadcast
        
        return BLEPacket(
            type: .presence,
            senderHash: senderData,
            targetHash: targetData,
            msgId: UInt8(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 256)),
            chunkIndex: 0,
            chunkTotal: 1,
            chunkData: Data(),
            isComplete: true
        )
    }
    
    static func createPresenceWithNameAndGender(from senderHash: String, userName: String, gender: Gender) -> [BLEPacket] {
        let senderData = Data(hex: senderHash)
        let targetData = Data(count: 4) // Broadcast
        let msgId = UInt8(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 256))
        
        // Combine gender and name: [gender][userName]
        var genderAndNameData = Data()
        let genderByte: UInt8 = gender == .male ? 0x01 : 0x02
        genderAndNameData.append(genderByte)
        genderAndNameData.append(userName.data(using: .utf8) ?? Data())
        
        // If data fits in single packet
        if genderAndNameData.count <= maxChunkData {
            return [BLEPacket(
                type: .presence,
                senderHash: senderData,
                targetHash: targetData,
                msgId: msgId,
                chunkIndex: 0,
                chunkTotal: 1,
                chunkData: genderAndNameData,
                isComplete: true,
                completeMessage: String(data: genderAndNameData.dropFirst(), encoding: .utf8)
            )]
        } else {
            // Multi-chunk data (unlikely but handle it)
            let totalChunks = (genderAndNameData.count + maxChunkData - 1) / maxChunkData
            var packets: [BLEPacket] = []
            
            for chunkIndex in 0..<totalChunks {
                let startOffset = chunkIndex * maxChunkData
                let endOffset = min(startOffset + maxChunkData, genderAndNameData.count)
                let chunkData = genderAndNameData.subdata(in: startOffset..<endOffset)
                
                packets.append(BLEPacket(
                    type: .presence,
                    senderHash: senderData,
                    targetHash: targetData,
                    msgId: msgId,
                    chunkIndex: UInt8(chunkIndex),
                    chunkTotal: UInt8(totalChunks),
                    chunkData: chunkData
                ))
            }
            
            return packets
        }
    }
    
    static func createMatchRequest(from senderHash: String, to targetHash: String, senderGender: String) -> BLEPacket {
        let senderData = Data(hex: senderHash)
        let targetData = Data(hex: targetHash)
        let genderByte: UInt8 = senderGender == "M" ? 0x01 : (senderGender == "F" ? 0x02 : 0x00)
        
        return BLEPacket(
            type: .matchRequest,
            senderHash: senderData,
            targetHash: targetData,
            msgId: UInt8(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 256)),
            chunkIndex: 0,
            chunkTotal: 1,
            chunkData: Data([genderByte]),
            isComplete: true
        )
    }
    
    static func createMatchResponse(from responderHash: String, to targetHash: String, accepted: Bool, responderGender: String) -> BLEPacket {
        let responderData = Data(hex: responderHash)
        let targetData = Data(hex: targetHash)
        let genderByte: UInt8 = responderGender == "M" ? 0x01 : (responderGender == "F" ? 0x02 : 0x00)
        
        return BLEPacket(
            type: accepted ? .matchAccept : .matchReject,
            senderHash: responderData,
            targetHash: targetData,
            msgId: UInt8(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 256)),
            chunkIndex: 0,
            chunkTotal: 1,
            chunkData: Data([genderByte]),
            isComplete: true
        )
    }
    
    static func createChatMessage(from senderHash: String, to targetHash: String, message: String) -> [BLEPacket] {
        let senderData = Data(hex: senderHash)
        let targetData = Data(hex: targetHash)
        let messageData = message.data(using: .utf8) ?? Data()
        let msgId = UInt8(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 256))
        
        // Calculate number of chunks needed
        let totalChunks = (messageData.count + maxChunkData - 1) / maxChunkData
        var packets: [BLEPacket] = []
        
        for chunkIndex in 0..<totalChunks {
            let startOffset = chunkIndex * maxChunkData
            let endOffset = min(startOffset + maxChunkData, messageData.count)
            let chunkData = messageData.subdata(in: startOffset..<endOffset)
            
            let isLastChunk = chunkIndex == totalChunks - 1
            let completeMessage = isLastChunk ? message : nil
            
            packets.append(BLEPacket(
                type: .chatMessage,
                senderHash: senderData,
                targetHash: targetData,
                msgId: msgId,
                chunkIndex: UInt8(chunkIndex),
                chunkTotal: UInt8(totalChunks),
                chunkData: chunkData,
                isComplete: totalChunks == 1,
                completeMessage: completeMessage
            ))
        }
        
        return packets
    }
    
    static func createUnmatch(from senderHash: String, to targetHash: String) -> BLEPacket {
        let senderData = Data(hex: senderHash)
        let targetData = Data(hex: targetHash)
        
        return BLEPacket(
            type: .unmatch,
            senderHash: senderData,
            targetHash: targetData,
            msgId: UInt8(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 256)),
            chunkIndex: 0,
            chunkTotal: 1,
            chunkData: Data(),
            isComplete: true
        )
    }
    
    static func createBlock(from senderHash: String, to targetHash: String) -> BLEPacket {
        let senderData = Data(hex: senderHash)
        let targetData = Data(hex: targetHash)
        
        return BLEPacket(
            type: .block,
            senderHash: senderData,
            targetHash: targetData,
            msgId: UInt8(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 256)),
            chunkIndex: 0,
            chunkTotal: 1,
            chunkData: Data(),
            isComplete: true
        )
    }
    
    // MARK: - Encoding
    
    func encode() -> Data {
        var packet = Data()
        
        if type == .matchRequest || type == .matchAccept || type == .matchReject {
            // New format for match packets: [version][type][senderHash:4][senderGender:1][targetHash:4][msgId][chunkIndex][chunkTotal]
            packet.append(BLEPacket.version)
            packet.append(type.rawValue)
            packet.append(senderHash.prefix(4))
            packet.append(chunkData.isEmpty ? 0x00 : chunkData[0]) // Gender byte
            packet.append(targetHash.prefix(4))
            packet.append(msgId)
            packet.append(chunkIndex)
            packet.append(chunkTotal)
        } else {
            // Old format for other packet types
            packet.append(BLEPacket.version)
            packet.append(type.rawValue)
            packet.append(senderHash.prefix(4))
            packet.append(targetHash.prefix(4))
            packet.append(msgId)
            packet.append(chunkIndex)
            packet.append(chunkTotal)
            packet.append(chunkData)
        }
        
        return packet
    }
    
    // MARK: - Decoding
    
    static func decode(from data: Data) -> BLEPacket? {
        // Minimum size check
        let minSize = data.count >= 2 && (data[1] == BLEPacketType.matchRequest.rawValue ||
                                         data[1] == BLEPacketType.matchAccept.rawValue ||
                                         data[1] == BLEPacketType.matchReject.rawValue) ? 14 : 13
        
        guard data.count >= minSize else {
            print("BLEPacket: Packet too small: \(data.count) bytes, expected: \(minSize)")
            return nil
        }
        
        // Check version
        guard data[0] == version else {
            print("BLEPacket: Unknown version: \(data[0])")
            return nil
        }
        
        guard let packetType = BLEPacketType(rawValue: data[1]) else {
            print("BLEPacket: Unknown packet type: \(data[1])")
            return nil
        }
        
        let senderHash: Data
        let targetHash: Data
        let msgId: UInt8
        let chunkIndex: UInt8
        let chunkTotal: UInt8
        let chunkData: Data
        
        if packetType == .matchRequest || packetType == .matchAccept || packetType == .matchReject {
            // New format: [version][type][senderHash:4][senderGender:1][targetHash:4][msgId][chunkIndex][chunkTotal]
            senderHash = data.subdata(in: 2..<6)
            let senderGender = data[6] // Available for parsing if needed
            targetHash = data.subdata(in: 7..<11)
            msgId = data[11]
            chunkIndex = data[12]
            chunkTotal = data[13]
            chunkData = Data([senderGender]) // Store gender as chunk data for compatibility
        } else {
            // Old format for other packet types
            senderHash = data.subdata(in: 2..<6)
            targetHash = data.subdata(in: 6..<10)
            msgId = data[10]
            chunkIndex = data[11]
            chunkTotal = data[12]
            chunkData = data.count > 13 ? data.subdata(in: 13..<data.count) : Data()
        }
        
        print("BLEPacket: Decoded type=\(String(format: "%02x", packetType.rawValue)) sender=\(senderHash.hexString) target=\(targetHash.hexString) msgId=\(msgId) chunk \(chunkIndex)/\(chunkTotal) data=\(chunkData.count)bytes")
        
        // Handle single-chunk messages
        if chunkTotal == 1 {
            let completeMessage = packetType == .chatMessage ? String(data: chunkData, encoding: .utf8) : nil
            return BLEPacket(
                type: packetType,
                senderHash: senderHash,
                targetHash: targetHash,
                msgId: msgId,
                chunkIndex: chunkIndex,
                chunkTotal: chunkTotal,
                chunkData: chunkData,
                isComplete: true,
                completeMessage: completeMessage
            )
        }
        
        // For multi-chunk messages, return incomplete packet
        // (Reassembly should be handled by the caller)
        return BLEPacket(
            type: packetType,
            senderHash: senderHash,
            targetHash: targetHash,
            msgId: msgId,
            chunkIndex: chunkIndex,
            chunkTotal: chunkTotal,
            chunkData: chunkData,
            isComplete: false,
            completeMessage: nil
        )
    }
    
    // MARK: - Message Assembly
    
    func assembleMessage() -> String? {
        return completeMessage
    }
}

// MARK: - Data Extensions

extension Data {
    init(hex: String) {
        let cleanHex = hex.replacingOccurrences(of: " ", with: "")
        var data = Data()
        var index = cleanHex.startIndex
        
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) ?? cleanHex.endIndex
            let byteString = String(cleanHex[index..<nextIndex])
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        
        self = data
    }
    
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Hash Utility

extension BLEPacket {
    static func hashUserIdTo4Bytes(_ userId: String) -> Data {
        let data = userId.data(using: .utf8) ?? Data()
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        
        data.withUnsafeBytes { bytes in
            CC_SHA256(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), &hash)
        }
        
        return Data(hash.prefix(4))
    }
    
    // MARK: - Compatibility Methods (for BLEManager)
    
    static func encodePresenceWithNameAndGender(senderHash: Data, userName: String, gender: UInt8) -> [Data] {
        let genderEnum: Gender = gender == 0x01 ? .male : .female
        let packets = createPresenceWithNameAndGender(from: senderHash.hexString, userName: userName, gender: genderEnum)
        return packets.map { $0.encode() }
    }
    
    static func encodeChat(senderHash: Data, targetHash: Data, message: String) -> [Data] {
        let packets = createChatMessage(from: senderHash.hexString, to: targetHash.hexString, message: message)
        return packets.map { $0.encode() }
    }
    
    static func encodeUnmatch(senderHash: Data, targetHash: Data) -> [Data] {
        let packet = createUnmatch(from: senderHash.hexString, to: targetHash.hexString)
        return [packet.encode()]
    }
    
    static func encodeBlock(senderHash: Data, targetHash: Data) -> [Data] {
        let packet = createBlock(from: senderHash.hexString, to: targetHash.hexString)
        return [packet.encode()]
    }
    
    // Decode wrapper for BLEManager compatibility
    static func decode(_ data: Data) -> DecodedFrame? {
        guard let packet = decode(from: data) else { return nil }
        
        return DecodedFrame(
            type: packet.type.rawValue,
            senderHash: packet.senderHash,
            targetHash: packet.targetHash,
            msgId: packet.msgId,
            chunkIndex: packet.chunkIndex,
            chunkTotal: packet.chunkTotal,
            chunkData: packet.chunkData,
            isComplete: packet.isComplete,
            completeMessage: packet.completeMessage
        )
    }
}
