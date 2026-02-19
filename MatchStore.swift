import Foundation
import Combine

// MARK: - Match Store (matching Android MatchStore.kt)
class MatchStore {
    static let shared = MatchStore()
    
    private let defaults = UserDefaults.standard
    private let KEY_PENDING_REQUESTS = "pending_requests"
    private let KEY_MATCHES = "matches"
    
    // MARK: - Data Models
    struct PendingRequest: Codable, Identifiable {
        let id: String
        let fromUserHash: String
        let fromGender: String
        let timestamp: TimeInterval
        var deviceAddress: String?
        
        init(id: String = UUID().uuidString, fromUserHash: String, fromGender: String, timestamp: TimeInterval = Date().timeIntervalSince1970, deviceAddress: String? = nil) {
            self.id = id
            self.fromUserHash = fromUserHash
            self.fromGender = fromGender
            self.timestamp = timestamp
            self.deviceAddress = deviceAddress
        }
    }
    
    struct Match: Codable, Identifiable {
        let id: String
        let userHash: String
        var userName: String
        let gender: String
        let matchedAt: TimeInterval
        var deviceAddress: String?
        var lastMessageAt: TimeInterval?
        var isActive: Bool
        
        init(id: String = UUID().uuidString, userHash: String, userName: String = "", gender: String, matchedAt: TimeInterval = Date().timeIntervalSince1970, deviceAddress: String? = nil, lastMessageAt: TimeInterval? = nil, isActive: Bool = true) {
            self.id = id
            self.userHash = userHash
            self.userName = userName.isEmpty ? "User\(userHash.prefix(4).uppercased())" : userName
            self.gender = gender
            self.matchedAt = matchedAt
            self.deviceAddress = deviceAddress
            self.lastMessageAt = lastMessageAt
            self.isActive = isActive
        }
        
        // Computed properties for compatibility
        var genderEmoji: String {
            return gender == "M" ? "👨" : "👩"
        }
        
        var displayName: String {
            return "\(genderEmoji) \(userName)"
        }
        
        var genderIcon: String {
            return gender == "M" ? "♂️" : "♀️"
        }
        
        var userGender: String {
            return gender
        }
        
        var timeAgo: String {
            let now = Date().timeIntervalSince1970
            let diff = now - matchedAt
            
            if diff < 60 {
                return "Just now"
            } else if diff < 3600 {
                let minutes = Int(diff / 60)
                return "\(minutes)m ago"
            } else if diff < 86400 {
                let hours = Int(diff / 3600)
                return "\(hours)h ago"
            } else {
                let days = Int(diff / 86400)
                return "\(days)d ago"
            }
        }
    }
    
    // REACTIVE PUBLISHERS for UI updates (like Android Flow)
    @Published var matches: [Match] = []
    @Published var pendingRequests: [PendingRequest] = []
    
    private init() {
        loadData()
        print("📝 MatchStore: Initialized with \(matches.count) matches and \(pendingRequests.count) pending requests")
    }
    
    // MARK: - Load Data
    private func loadData() {
        matches = loadMatches()
        pendingRequests = loadPendingRequests()
    }
    
    // MARK: - Pending Requests
    func storePendingRequest(fromUserHash: String, fromGender: String, deviceAddress: String? = nil) -> PendingRequest {
        var requests = pendingRequests
        
        // Check for duplicate
        if let existingIndex = requests.firstIndex(where: { $0.fromUserHash == fromUserHash }) {
            print("📝 MatchStore: Updating existing request from: \(fromUserHash)")
            let request = PendingRequest(id: requests[existingIndex].id, fromUserHash: fromUserHash, fromGender: fromGender, deviceAddress: deviceAddress)
            requests[existingIndex] = request
            savePendingRequests(requests)
            return request
        } else {
            print("📝 MatchStore: Storing new request from: \(fromUserHash)")
            let request = PendingRequest(fromUserHash: fromUserHash, fromGender: fromGender, deviceAddress: deviceAddress)
            requests.append(request)
            savePendingRequests(requests)
            return request
        }
    }
    
    func acceptRequest(requestId: String) -> Match? {
        var requests = pendingRequests
        
        guard let requestIndex = requests.firstIndex(where: { $0.id == requestId }) else {
            print("❌ MatchStore: Request not found for acceptance: \(requestId)")
            return nil
        }
        
        let request = requests[requestIndex]
        
        // Create match
        let match = Match(userHash: request.fromUserHash, gender: request.fromGender, deviceAddress: request.deviceAddress)
        
        // Store match
        storeMatch(match)
        
        // Remove from pending
        requests.remove(at: requestIndex)
        savePendingRequests(requests)
        
        print("✅ MatchStore: Accepted request \(requestId), created match: \(match.id)")
        return match
    }
    
    func rejectRequest(requestId: String) -> Bool {
        var requests = pendingRequests
        
        guard let requestIndex = requests.firstIndex(where: { $0.id == requestId }) else {
            print("❌ MatchStore: Request not found for rejection: \(requestId)")
            return false
        }
        
        let request = requests[requestIndex]
        requests.remove(at: requestIndex)
        savePendingRequests(requests)
        
        print("❌ MatchStore: Rejected request \(requestId) from: \(request.fromUserHash)")
        return true
    }
    
    func getPendingRequestCount() -> Int {
        return pendingRequests.count
    }
    
    // MARK: - Matches
    func storeMatch(_ match: Match) {
        var currentMatches = matches
        
        // Check for duplicates by userHash
        if let existingIndex = currentMatches.firstIndex(where: { $0.userHash == match.userHash }) {
            print("📝 MatchStore: Updating existing match with: \(match.userHash) (ID: \(match.id))")
            currentMatches[existingIndex] = match
        } else {
            print("📝 MatchStore: Storing new match with: \(match.userHash) (ID: \(match.id))")
            currentMatches.append(match)
        }
        
        saveMatches(currentMatches)
        print("✅ MatchStore: Match saved to storage, total matches: \(currentMatches.count)")
    }
    
    func storeMatch(userHash: String, gender: String, deviceAddress: String? = nil) {
        let match = Match(userHash: userHash, gender: gender, deviceAddress: deviceAddress)
        storeMatch(match)
    }
    
    func removeMatch(userHash: String) -> Bool {
        var currentMatches = matches
        let initialCount = currentMatches.count
        
        currentMatches.removeAll { $0.userHash == userHash }
        
        if currentMatches.count < initialCount {
            saveMatches(currentMatches)
            print("💔 MatchStore: Removed match with: \(userHash)")
            return true
        }
        
        return false
    }
    
    func getMatch(byUserHash userHash: String) -> Match? {
        return matches.first { $0.userHash == userHash }
    }
    
    // MARK: - Compatibility Methods
    func getActiveMatches() -> [Match] {
        return matches.filter { $0.isActive }
    }
    
    func getAllMatches() -> [Match] {
        return matches
    }
    
    func getActiveMatchCount() -> Int {
        return getActiveMatches().count
    }
    
    func addMatch(_ match: Match) {
        storeMatch(match)
    }
    
    func removeMatch(withId id: String) {
        if let match = matches.first(where: { $0.id == id }) {
            _ = removeMatch(userHash: match.userHash)
        }
    }
    
    func updateMatch(_ match: Match) {
        storeMatch(match)
    }
    
    func getMatch(withId id: String) -> Match? {
        return matches.first { $0.id == id }
    }
    
    func getMatchCount() -> Int {
        return matches.count
    }
    
    // MARK: - Clear All
    func clearAll() {
        saveMatches([])
        savePendingRequests([])
        print("🧹 MatchStore: Cleared all match data")
    }
    
    // MARK: - Private Storage Methods
    private func loadPendingRequests() -> [PendingRequest] {
        guard let data = defaults.data(forKey: KEY_PENDING_REQUESTS) else {
            return []
        }
        
        do {
            let requests = try JSONDecoder().decode([PendingRequest].self, from: data)
            return requests
        } catch {
            print("❌ MatchStore: Error loading pending requests: \(error)")
            return []
        }
    }
    
    private func savePendingRequests(_ requests: [PendingRequest]) {
        do {
            let data = try JSONEncoder().encode(requests)
            defaults.set(data, forKey: KEY_PENDING_REQUESTS)
            pendingRequests = requests
            print("💾 MatchStore: Saved \(requests.count) pending requests")
        } catch {
            print("❌ MatchStore: Error saving pending requests: \(error)")
        }
    }
    
    private func loadMatches() -> [Match] {
        guard let data = defaults.data(forKey: KEY_MATCHES) else {
            return []
        }
        
        do {
            let matches = try JSONDecoder().decode([Match].self, from: data)
            return matches
        } catch {
            print("❌ MatchStore: Error loading matches: \(error)")
            return []
        }
    }
    
    private func saveMatches(_ matches: [Match]) {
        do {
            let data = try JSONEncoder().encode(matches)
            defaults.set(data, forKey: KEY_MATCHES)
            self.matches = matches
            print("💾 MatchStore: Saved \(matches.count) matches")
        } catch {
            print("❌ MatchStore: Error saving matches: \(error)")
        }
    }
}
