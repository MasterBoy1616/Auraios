import Foundation

// MARK: - UserPreferences (matching Android UserPreferences.kt)
class UserPreferences {
    static let shared = UserPreferences()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let KEY_USER_ID = "user_id"
    private let KEY_USER_NAME = "user_name"
    private let KEY_GENDER = "gender"
    private let KEY_FIRST_LAUNCH = "first_launch"
    private let KEY_VISIBILITY_ENABLED = "visibility_enabled"
    private let KEY_HAS_COMPLETED_GENDER_SELECTION = "hasCompletedGenderSelection"
    
    private init() {
        // Generate user ID if not exists
        if getUserId().isEmpty {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: KEY_USER_ID)
            print("📝 UserPreferences: Generated new userId: \(newId)")
        }
    }
    
    // MARK: - User ID
    func getUserId() -> String {
        return defaults.string(forKey: KEY_USER_ID) ?? ""
    }
    
    var userId: String {
        get { return getUserId() }
        set { defaults.set(newValue, forKey: KEY_USER_ID) }
    }
    
    // MARK: - User Name
    func getUserName() -> String {
        let name = defaults.string(forKey: KEY_USER_NAME)
        if let name = name, !name.isEmpty {
            return name
        }
        // Generate default name
        let userId = getUserId()
        let shortId = String(userId.suffix(4)).uppercased()
        return "User\(shortId)"
    }
    
    func setUserName(_ name: String) {
        defaults.set(name, forKey: KEY_USER_NAME)
        print("📝 UserPreferences: Set userName: \(name)")
    }
    
    var userName: String {
        get { return getUserName() }
        set { setUserName(newValue) }
    }
    
    // MARK: - Gender
    func getGender() -> Gender? {
        guard let genderString = defaults.string(forKey: KEY_GENDER) else {
            return nil
        }
        return Gender(rawValue: genderString)
    }
    
    func setGender(_ gender: Gender) {
        defaults.set(gender.rawValue, forKey: KEY_GENDER)
        print("📝 UserPreferences: Set gender: \(gender.rawValue)")
    }
    
    var gender: Gender? {
        get { return getGender() }
        set {
            if let newValue = newValue {
                setGender(newValue)
            }
        }
    }
    
    // MARK: - First Launch
    func isFirstLaunch() -> Bool {
        return defaults.bool(forKey: KEY_FIRST_LAUNCH)
    }
    
    func setFirstLaunchComplete() {
        defaults.set(false, forKey: KEY_FIRST_LAUNCH)
        print("📝 UserPreferences: First launch complete")
    }
    
    // MARK: - Visibility
    func getVisibilityEnabled() -> Bool {
        // Default to true if not set
        if defaults.object(forKey: KEY_VISIBILITY_ENABLED) == nil {
            return true
        }
        return defaults.bool(forKey: KEY_VISIBILITY_ENABLED)
    }
    
    func setVisibilityEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: KEY_VISIBILITY_ENABLED)
        print("📝 UserPreferences: Set visibility: \(enabled)")
    }
    
    var isVisibilityEnabled: Bool {
        get { return getVisibilityEnabled() }
        set { setVisibilityEnabled(newValue) }
    }
    
    // MARK: - Gender Selection Completion
    var hasCompletedGenderSelection: Bool {
        get {
            return defaults.bool(forKey: KEY_HAS_COMPLETED_GENDER_SELECTION)
        }
        set {
            defaults.set(newValue, forKey: KEY_HAS_COMPLETED_GENDER_SELECTION)
            print("📝 UserPreferences: Set hasCompletedGenderSelection: \(newValue)")
        }
    }
    
    // MARK: - User Hash
    func getUserHash() -> Data {
        let userId = getUserId()
        return BLEPacket.hashUserIdTo4Bytes(userId)
    }
    
    var userHash: String {
        return getUserHash().hexString
    }
    
    // MARK: - Save
    func save() {
        defaults.synchronize()
    }
}
