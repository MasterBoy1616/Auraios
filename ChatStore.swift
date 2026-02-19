import Foundation
import Combine

// MARK: - Chat Store (matching Android ChatStore.kt)
class ChatStore {
    static let shared = ChatStore()
    
    private let defaults = UserDefaults.standard
    private let KEY_MESSAGES = "messages"
    
    // MARK: - Data Model
    struct ChatMessage: Codable, Identifiable {
        let id: String
        let matchId: String
        let senderId: String
        let receiverId: String
        let content: String
        let timestamp: TimeInterval
        let isFromMe: Bool
        var status: MessageStatus
        
        enum MessageStatus: String, Codable {
            case pending = "PENDING"
            case delivered = "DELIVERED"
            case failed = "FAILED"
            case read = "READ"
        }
        
        init(id: String = UUID().uuidString, matchId: String, senderId: String, receiverId: String, content: String, timestamp: TimeInterval = Date().timeIntervalSince1970, isFromMe: Bool, status: MessageStatus = .pending) {
            self.id = id
            self.matchId = matchId
            self.senderId = senderId
            self.receiverId = receiverId
            self.content = content
            self.timestamp = timestamp
            self.isFromMe = isFromMe
            self.status = status
        }
    }
    
    // REACTIVE PUBLISHER for UI updates
    @Published var messages: [ChatMessage] = []
    
    private init() {
        loadMessages()
        print("📝 ChatStore: Initialized with \(messages.count) messages")
    }
    
    // MARK: - Store Message
    func storeMessage(_ message: ChatMessage) {
        var currentMessages = messages
        currentMessages.append(message)
        saveMessages(currentMessages)
        print("💬 ChatStore: Stored message: \(message.content.prefix(20))...")
    }
    
    // MARK: - Get Messages
    func getMessages(forMatchId matchId: String) -> [ChatMessage] {
        return messages.filter { $0.matchId == matchId }
    }
    
    func getMessages(forUserHash userHash: String) -> [ChatMessage] {
        return messages.filter { $0.senderId == userHash || $0.receiverId == userHash }
    }
    
    // MARK: - Update Message Status
    func updateMessageStatus(messageId: String, status: ChatMessage.MessageStatus) {
        var currentMessages = messages
        
        if let messageIndex = currentMessages.firstIndex(where: { $0.id == messageId }) {
            var message = currentMessages[messageIndex]
            message.status = status
            currentMessages[messageIndex] = message
            saveMessages(currentMessages)
            print("📝 ChatStore: Updated message status: \(messageId) -> \(status)")
        }
    }
    
    // MARK: - Clear Chat History
    func clearChatHistory(forUserHash userHash: String) {
        var currentMessages = messages
        let initialCount = currentMessages.count
        
        currentMessages.removeAll { $0.senderId == userHash || $0.receiverId == userHash }
        
        if currentMessages.count < initialCount {
            saveMessages(currentMessages)
            print("🧹 ChatStore: Cleared chat history for: \(userHash)")
        }
    }
    
    func clearChatHistory(forMatchId matchId: String) {
        var currentMessages = messages
        let initialCount = currentMessages.count
        
        currentMessages.removeAll { $0.matchId == matchId }
        
        if currentMessages.count < initialCount {
            saveMessages(currentMessages)
            print("🧹 ChatStore: Cleared chat history for match: \(matchId)")
        }
    }
    
    // MARK: - Private Storage Methods
    private func loadMessages() {
        guard let data = defaults.data(forKey: KEY_MESSAGES) else {
            messages = []
            return
        }
        
        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            print("❌ ChatStore: Error loading messages: \(error)")
            messages = []
        }
    }
    
    private func saveMessages(_ messages: [ChatMessage]) {
        do {
            let data = try JSONEncoder().encode(messages)
            defaults.set(data, forKey: KEY_MESSAGES)
            self.messages = messages
            print("💾 ChatStore: Saved \(messages.count) messages")
        } catch {
            print("❌ ChatStore: Error saving messages: \(error)")
        }
    }
}
