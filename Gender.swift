import Foundation

// MARK: - Gender Enum (matching Android Gender.kt)
enum Gender: String, Codable, CaseIterable {
    case male = "M"
    case female = "F"
    case unknown = "U"
    
    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .unknown: return "Unspecified"
        }
    }
    
    var icon: String {
        switch self {
        case .male: return "♂️"
        case .female: return "♀️"
        case .unknown: return "👤"
        }
    }
    
    var byteValue: UInt8 {
        switch self {
        case .male: return 0x4D // 'M'
        case .female: return 0x46 // 'F'
        case .unknown: return 0x55 // 'U'
        }
    }
    
    static func from(byte: UInt8) -> Gender {
        switch byte {
        case 0x4D: return .male
        case 0x46: return .female
        default: return .unknown
        }
    }
    
    // Compatibility
    static var unspecified: Gender {
        return .unknown
    }
}
