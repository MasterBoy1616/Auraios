import Foundation
import CoreBluetooth
import Combine

/// BLE-only engine for Aura proximity-based discovery
/// iOS uses GATT Server with characteristics (iOS cannot use manufacturer data like Android)
/// Android scans for iOS GATT characteristics
/// EXACTLY matching Android BleEngine.kt protocol
class BLEManager: NSObject {
    
    static let shared = BLEManager()
    
    // MARK: - Constants
    // CRITICAL FIX: Changed from 0000180F (Battery Service) to custom UUID
    // 0000180F conflicts with iOS system Battery Service!
    private let AURA_SERVICE_UUID = CBUUID(string: "0000FFF0-0000-1000-8000-00805F9B34FB")
    private let PRESENCE_CHARACTERISTIC_UUID = CBUUID(string: "0000FFF1-0000-1000-8000-00805F9B34FB")
    private let SCAN_PERIOD_MS: TimeInterval = 10.0 // 10 seconds
    private let ADVERTISE_PERIOD_MS: TimeInterval = 15.0 // 15 seconds
    private let BACKGROUND_SCAN_INTERVAL_MS: TimeInterval = 30.0 // 30 seconds
    
    // MARK: - Bluetooth Components
    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    
    // MARK: - GATT Server Components (iOS-specific)
    private var gattService: CBMutableService?
    private var presenceCharacteristic: CBMutableCharacteristic?
    
    // MARK: - Current User Data
    private var currentUserId: String = ""
    private var currentUserHash: Data = Data(repeating: 0, count: 4)
    private var currentUserGender: UInt8 = 0x00
    private var currentUserName: String = ""
    
    // MARK: - State Management
    private var isAdvertising = false
    private var isScanning = false
    private var isBackgroundScanning = false
    private var isHighPowerMode = false
    private var isFastScanMode = false
    private var isPriorityMode = false
    
    // MARK: - Nearby Users Tracking
    private var nearbyUsersDict: [String: NearbyUser] = [:]
    @Published var nearbyUsers: [NearbyUser] = []
    
    struct NearbyUser: Identifiable {
        let id = UUID()
        let userHash: String
        var userName: String
        var gender: String
        var rssi: Int
        var lastSeen: Date
        var moodType: String?
        var moodMessage: String?
        
        init(userHash: String, userName: String, gender: String, rssi: Int, lastSeen: Date = Date(), moodType: String? = nil, moodMessage: String? = nil) {
            self.userHash = userHash
            self.userName = userName
            self.gender = gender
            self.rssi = rssi
            self.lastSeen = lastSeen
            self.moodType = moodType
            self.moodMessage = moodMessage
        }
    }
    
    // MARK: - Message Queue
    private var outgoingMessageQueue: [QueuedMessage] = []
    private var isProcessingQueue = false
    
    struct QueuedMessage {
        let type: UInt8
        let targetHash: String
        let data: String
        let timestamp: Date
        
        init(type: UInt8, targetHash: String, data: String = "", timestamp: Date = Date()) {
            self.type = type
            self.targetHash = targetHash
            self.data = data
            self.timestamp = timestamp
        }
    }
    
    // MARK: - Premium Feature State
    private var currentMoodType: String?
    private var currentMoodMessage: String?
    
    // MARK: - Duplicate Message Prevention
    private var processedMessages = Set<String>()
    private var messageTimeouts: [String: Date] = [:]
    private let MESSAGE_TIMEOUT: TimeInterval = 45.0 // 45 seconds
    
    // MARK: - Match Request Cooldown
    private var matchRequestTracker: [String: Date] = [:]
    private let MATCH_REQUEST_COOLDOWN: TimeInterval = 60.0 // 1 minute
    
    // MARK: - Listener Protocol
    protocol BLEManagerListener: AnyObject {
        func onIncomingMatchRequest(senderHash: String)
        func onMatchAccepted(senderHash: String)
        func onMatchRejected(senderHash: String)
        func onChatMessage(senderHash: String, message: String)
        func onPhotoReceived(senderHash: String, photoBase64: String)
        func onPhotoRequested(senderHash: String)
        func onUnmatchReceived(senderHash: String)
        func onBlockReceived(senderHash: String)
    }
    
    private var listeners: [BLEManagerListener] = []
    
    // MARK: - Initialization
    private override init() {
        super.init()
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        print("🚀 BLEManager: Initialized with GATT Server support")
        
        // CRITICAL FIX: Set default user from preferences BEFORE advertising starts
        let userPrefs = UserPreferences.shared
        let userId = userPrefs.userId
        if !userId.isEmpty {
            print("� BLEManager: Setting user from preferences: \(userId)")
            setCurrentUser(userId)
        } else {
            print("⚠️ BLEManager: No user ID in preferences yet")
        }
        
        // CRITICAL FIX: Start advertising health check
        startAdvertisingHealthCheck()
    }
    
    // MARK: - Advertising Health Check
    
    private func startAdvertisingHealthCheck() {
        // Check advertising status every 10 seconds
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Check if advertising should be active but isn't
            if self.peripheralManager.state == .poweredOn {
                let shouldBeAdvertising = UserPreferences.shared.isVisibilityEnabled
                let isActuallyAdvertising = self.peripheralManager.isAdvertising
                
                if shouldBeAdvertising && !isActuallyAdvertising {
                    print("⚠️ BLEManager: HEALTH_CHECK: Advertising should be active but isn't! Restarting...")
                    self.isAdvertising = false
                    self.startAdvertising()
                } else if shouldBeAdvertising && isActuallyAdvertising {
                    print("✅ BLEManager: HEALTH_CHECK: Advertising is healthy")
                } else {
                    print("ℹ️ BLEManager: HEALTH_CHECK: Advertising disabled by user")
                }
            }
        }
    }
    
    // MARK: - GATT Server Setup (iOS-specific)
    
    private func setupGATTServer() {
        guard peripheralManager.state == .poweredOn else {
            print("⚠️ BLEManager: Cannot setup GATT server, Bluetooth not powered on")
            return
        }
        
        print("🔧 BLEManager: Setting up GATT Server...")
        print("🔧 BLEManager: Peripheral state: \(peripheralManager.state.rawValue)")
        
        // CRITICAL FIX: Remove ALL existing services first
        peripheralManager.removeAllServices()
        print("🗑️ BLEManager: Removed all existing GATT services")
        
        // Small delay to ensure clean state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            print("🔧 BLEManager: Creating new GATT service...")
            
            // Create presence characteristic (readable by Android)
            // CRITICAL: Use .read and .notify properties, .readable permission
            self.presenceCharacteristic = CBMutableCharacteristic(
                type: self.PRESENCE_CHARACTERISTIC_UUID,
                properties: [.read, .notify],
                value: nil, // Dynamic value - will be set on read
                permissions: [.readable]
            )
            
            print("✅ BLEManager: Created characteristic")
            print("   - UUID: \(self.PRESENCE_CHARACTERISTIC_UUID.uuidString)")
            print("   - Properties: read, notify")
            print("   - Permissions: readable")
            
            // Create service with characteristic
            self.gattService = CBMutableService(type: self.AURA_SERVICE_UUID, primary: true)
            self.gattService?.characteristics = [self.presenceCharacteristic!]
            
            print("✅ BLEManager: Created service")
            print("   - UUID: \(self.AURA_SERVICE_UUID.uuidString)")
            print("   - Primary: true")
            print("   - Characteristics count: \(self.gattService?.characteristics?.count ?? 0)")
            
            // Verify characteristic is attached
            if let chars = self.gattService?.characteristics {
                for (index, char) in chars.enumerated() {
                    print("   - Characteristic[\(index)]: \(char.uuid.uuidString)")
                }
            }
            
            // Add service to peripheral manager
            self.peripheralManager.add(self.gattService!)
            
            print("✅ BLEManager: GATT Server setup initiated - waiting for didAdd callback")
        }
    }
    
    private func updateGATTCharacteristic() {
        guard let characteristic = presenceCharacteristic else {
            print("⚠️ BLEManager: Presence characteristic not initialized")
            return
        }
        
        // Create presence packet with user data
        let packets = BLEPacket.encodePresenceWithNameAndGender(senderHash: currentUserHash, userName: currentUserName, gender: currentUserGender)
        
        guard let packet = packets.first else {
            print("❌ BLEManager: Failed to create presence packet")
            return
        }
        
        // Update characteristic value
        let success = peripheralManager.updateValue(packet, for: characteristic, onSubscribedCentrals: nil)
        
        if success {
            print("✅ BLEManager: GATT characteristic updated with \(packet.count) bytes")
        } else {
            print("⚠️ BLEManager: GATT characteristic update queued")
        }
    }
    
    // CRITICAL FIX: Write message packet to GATT characteristic for Android to read
    private func updateGATTCharacteristicWithMessage(_ packet: Data) {
        guard let characteristic = presenceCharacteristic else {
            print("⚠️ BLEManager: Presence characteristic not initialized")
            return
        }
        
        print("📤 BLEManager: Writing message to GATT characteristic (\(packet.count) bytes)")
        
        // Update characteristic value with message packet
        let success = peripheralManager.updateValue(packet, for: characteristic, onSubscribedCentrals: nil)
        
        if success {
            print("✅ BLEManager: GATT characteristic updated with message")
        } else {
            print("⚠️ BLEManager: GATT characteristic message update queued")
        }
        
        // After 2 seconds, restore normal presence data
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.updateGATTCharacteristic()
            print("🔄 BLEManager: Restored normal presence data to GATT")
        }
    }
    
    // MARK: - Public Methods
    
    /// Set current user
    func setCurrentUser(_ userId: String) {
        print("📝 BLEManager: setCurrentUser called with userId: '\(userId)'")
        
        guard !userId.isEmpty else {
            print("❌ BLEManager: userId is EMPTY! Cannot set user.")
            return
        }
        
        currentUserId = userId
        currentUserHash = BLEPacket.hashUserIdTo4Bytes(userId)
        
        let userPrefs = UserPreferences.shared
        currentUserName = userPrefs.userName
        
        let gender = userPrefs.gender
        currentUserGender = gender == .male ? 0x01 : (gender == .female ? 0x02 : 0x00)
        
        print(" BLEManager: Set current user:")
        print("   - userId: \(userId)")
        print("   - hash: \(currentUserHash.hexString)")
        print("   - name: \(currentUserName)")
        print("   - gender: \(currentUserGender)")
        
        // Update GATT characteristic with new user data
        updateGATTCharacteristic()
        
        // CRITICAL FIX: Restart advertising with new user data
        if isAdvertising {
            print("🔄 BLEManager: Restarting advertising with new user data")
            stopAdvertising()
            // Small delay to ensure clean restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startAdvertising()
            }
        }
    }
    
    /// Add listener
    func addListener(_ listener: BLEManagerListener) {
        listeners.append(listener)
    }
    
    /// Remove listener
    func removeListener(_ listener: BLEManagerListener) {
        listeners.removeAll { $0 === listener }
    }
    
    // MARK: - Scanning
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("⚠️ BLEManager: Cannot start scanning, Bluetooth not powered on")
            return
        }
        
        guard !isScanning else {
            print("⚠️ BLEManager: Already scanning")
            return
        }
        
        print("🔍 BLEManager: Starting scan...")
        
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]
        
        // CRITICAL FIX: Scan for ALL devices (no filter) to find Android
        // Scan for Aura service (will find both Android manufacturer data and iOS GATT services)
        centralManager.scanForPeripherals(withServices: nil, options: options)
        isScanning = true
        
        print("✅ BLEManager: Scan started (NO FILTER for Android compatibility)")
    }
    
    func stopScanning() {
        guard isScanning else {
            return
        }
        
        print("🛑 BLEManager: Stopping scan...")
        centralManager.stopScan()
        isScanning = false
        
        print("✅ BLEManager: Scan stopped")
    }
    
    // MARK: - Advertising
    
    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else {
            print("⚠️ BLEManager: Cannot start advertising, Bluetooth not powered on")
            return
        }
        
        guard !isAdvertising else {
            print("⚠️ BLEManager: Already advertising")
            return
        }
        
        // CRITICAL: Don't advertise with empty user data
        guard currentUserHash.count == 4 && currentUserHash != Data(repeating: 0, count: 4) else {
            print("⚠️ BLEManager: Cannot start advertising, user data not set (hash: \(currentUserHash.hexString))")
            print("⚠️ BLEManager: Will retry when user data is available")
            return
        }
        
        guard !currentUserName.isEmpty else {
            print("⚠️ BLEManager: Cannot start advertising, user name not set")
            print("⚠️ BLEManager: Will retry when user name is available")
            return
        }
        
        print("📡 BLEManager: Starting advertising...")
        
        // DEBUG: Print current user data
        print("📡 BLEManager: Current user hash: \(currentUserHash.hexString)")
        print("📡 BLEManager: Current user name: \(currentUserName)")
        print("📡 BLEManager: Current user gender: \(currentUserGender)")
        
        // CRITICAL FIX: Create presence packet with service data (for Android compatibility)
        let presencePackets = BLEPacket.encodePresenceWithNameAndGender(senderHash: currentUserHash, userName: currentUserName, gender: currentUserGender)
        
        guard let presencePacket = presencePackets.first else {
            print("❌ BLEManager: Failed to create presence packet")
            return
        }
        
        print("📡 BLEManager: Presence packet: \(presencePacket.count) bytes")
        print("📡 BLEManager: Presence packet HEX: \(presencePacket.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // CRITICAL FIX: Use BOTH manufacturer data AND service data for maximum compatibility
        // - Manufacturer data: For Android devices (they scan for this)
        // - Service data: For iOS devices (backup method)
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [AURA_SERVICE_UUID],
            CBAdvertisementDataLocalNameKey: "Aura",
            CBAdvertisementDataManufacturerDataKey: presencePacket  // Android compatibility
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        
        print("✅ BLEManager: Advertising started with manufacturer data")
    }
    
    func stopAdvertising() {
        guard isAdvertising else {
            return
        }
        
        print("🛑 BLEManager: Stopping advertising...")
        peripheralManager.stopAdvertising()
        isAdvertising = false
        
        print("✅ BLEManager: Advertising stopped")
    }
    
    func isAdvertisingActive() -> Bool {
        return isAdvertising && peripheralManager.isAdvertising
    }
    
    // MARK: - Match Requests
    
    func sendMatchRequest(to targetHash: String) {
        print("💌 BLEManager: Sending match request to: \(targetHash)")
        
        guard let targetHashData = Data(hexString: targetHash) else {
            print("❌ BLEManager: Invalid target hash")
            return
        }
        
        // Queue the message
        let message = QueuedMessage(type: BLEPacket.TYPE_MATCH_REQ, targetHash: targetHash)
        outgoingMessageQueue.append(message)
        
        print("✅ BLEManager: Match request queued for: \(targetHash)")
        
        // CRITICAL: Start processing queue
        processMessageQueue()
        
        // Notify via notification
        NotificationCenter.default.post(name: .matchRequestSent, object: nil, userInfo: ["targetHash": targetHash])
    }
    
    func acceptMatchRequest(from senderHash: String) {
        print("✅ BLEManager: Accepting match request from: \(senderHash)")
        
        guard let senderHashData = Data(hexString: senderHash) else {
            print("❌ BLEManager: Invalid sender hash")
            return
        }
        
        // Queue the message
        let message = QueuedMessage(type: BLEPacket.TYPE_MATCH_ACC, targetHash: senderHash)
        outgoingMessageQueue.append(message)
        
        // Store match locally
        MatchStore.shared.storeMatch(userHash: senderHash, gender: String(format: "%c", senderHashData[0]))
        
        print("✅ BLEManager: Match acceptance queued for: \(senderHash)")
        
        // CRITICAL: Start processing queue
        processMessageQueue()
        
        // Notify listeners
        listeners.forEach { $0.onMatchAccepted(senderHash: senderHash) }
    }
    
    func rejectMatchRequest(from senderHash: String) {
        print("❌ BLEManager: Rejecting match request from: \(senderHash)")
        
        guard let senderHashData = Data(hexString: senderHash) else {
            print("❌ BLEManager: Invalid sender hash")
            return
        }
        
        // Queue the message
        let message = QueuedMessage(type: BLEPacket.TYPE_MATCH_REJ, targetHash: senderHash)
        outgoingMessageQueue.append(message)
        
        print("✅ BLEManager: Match rejection queued for: \(senderHash)")
        
        // Notify listeners
        listeners.forEach { $0.onMatchRejected(senderHash: senderHash) }
    }
    
    // MARK: - Chat Messages
    
    func sendChatMessage(_ message: String, to targetHash: String) {
        print("💬 BLEManager: Sending chat message to: \(targetHash)")
        
        guard let targetHashData = Data(hexString: targetHash) else {
            print("❌ BLEManager: Invalid target hash")
            return
        }
        
        let packets = BLEPacket.encodeChat(senderHash: currentUserHash, targetHash: targetHashData, message: message)
        
        print("📦 BLEManager: Chat message encoded into \(packets.count) packets")
        
        // Queue the message
        let queuedMessage = QueuedMessage(type: BLEPacket.TYPE_CHAT, targetHash: targetHash, data: message)
        outgoingMessageQueue.append(queuedMessage)
        
        // Store message locally
        let chatMessage = ChatStore.ChatMessage(
            matchId: targetHash,
            senderId: currentUserHash.hexString,
            receiverId: targetHash,
            content: message,
            isFromMe: true
        )
        ChatStore.shared.storeMessage(chatMessage)
        
        print("✅ BLEManager: Chat message queued and stored locally")
        
        // CRITICAL: Start processing queue
        processMessageQueue()
    }
    
    // MARK: - Unmatch/Block
    
    func sendUnmatch(to targetHash: String) {
        print("💔 BLEManager: Sending unmatch to: \(targetHash)")
        
        guard let targetHashData = Data(hexString: targetHash) else {
            print("❌ BLEManager: Invalid target hash")
            return
        }
        
        _ = BLEPacket.encodeUnmatch(senderHash: currentUserHash, targetHash: targetHashData)
        
        // Queue the message
        let message = QueuedMessage(type: BLEPacket.TYPE_UNMATCH, targetHash: targetHash)
        outgoingMessageQueue.append(message)
        
        // Remove match locally
        _ = MatchStore.shared.removeMatch(userHash: targetHash)
        
        print("✅ BLEManager: Unmatch queued for: \(targetHash)")
    }
    
    func sendBlock(to targetHash: String) {
        print("🚫 BLEManager: Sending block to: \(targetHash)")
        
        guard let targetHashData = Data(hexString: targetHash) else {
            print("❌ BLEManager: Invalid target hash")
            return
        }
        
        _ = BLEPacket.encodeBlock(senderHash: currentUserHash, targetHash: targetHashData)
        
        // Queue the message
        let message = QueuedMessage(type: BLEPacket.TYPE_BLOCK, targetHash: targetHash)
        outgoingMessageQueue.append(message)
        
        print("✅ BLEManager: Block queued for: \(targetHash)")
    }
    
    // MARK: - Message Queue Processing
    
    private func processMessageQueue() {
        guard !isProcessingQueue else {
            print("📋 BLEManager: Already processing queue")
            return
        }
        
        guard !outgoingMessageQueue.isEmpty else {
            print("📋 BLEManager: Queue is empty")
            return
        }
        
        isProcessingQueue = true
        let message = outgoingMessageQueue.removeFirst()
        
        print("📋 BLEManager: Processing message type \(message.type) to \(message.targetHash)")
        
        // Transmit message
        transmitMessage(message)
        
        // Process next message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isProcessingQueue = false
            if !(self?.outgoingMessageQueue.isEmpty ?? true) {
                self?.processMessageQueue()
            }
        }
    }
    
    private func transmitMessage(_ message: QueuedMessage) {
        guard let targetHashData = Data(hexString: message.targetHash) else {
            print("❌ BLEManager: Invalid target hash")
            return
        }
        
        print("📤 BLEManager: ===== TRANSMIT MESSAGE =====")
        print("📤 BLEManager: Message type: \(message.type)")
        print("📤 BLEManager: Target hash: \(message.targetHash)")
        print("📤 BLEManager: Current user hash: \(currentUserHash.hexString)")
        print("📤 BLEManager: Current user gender: \(currentUserGender)")
        
        let packets: [Data]
        
        switch message.type {
        case BLEPacket.TYPE_MATCH_REQ:
            let matchPacket = BLEPacket.createMatchRequest(from: currentUserHash.map { String(format: "%02x", $0) }.joined(), to: targetHashData.map { String(format: "%02x", $0) }.joined(), senderGender: currentUserGender == 0x01 ? "M" : "F")
            packets = [matchPacket.encode()]
            print("💌 BLEManager: Created MATCH_REQ packet: \(packets[0].count) bytes")
            print("💌 BLEManager: Packet HEX: \(packets[0].map { String(format: "%02X", $0) }.joined(separator: " "))")
            
        case BLEPacket.TYPE_MATCH_ACC:
            let matchPacket = BLEPacket.createMatchResponse(from: currentUserHash.map { String(format: "%02x", $0) }.joined(), to: targetHashData.map { String(format: "%02x", $0) }.joined(), accepted: true, responderGender: currentUserGender == 0x01 ? "M" : "F")
            packets = [matchPacket.encode()]
            
        case BLEPacket.TYPE_MATCH_REJ:
            let matchPacket = BLEPacket.createMatchResponse(from: currentUserHash.map { String(format: "%02x", $0) }.joined(), to: targetHashData.map { String(format: "%02x", $0) }.joined(), accepted: false, responderGender: currentUserGender == 0x01 ? "M" : "F")
            packets = [matchPacket.encode()]
            
        case BLEPacket.TYPE_CHAT:
            packets = BLEPacket.createChatMessage(from: currentUserHash.map { String(format: "%02x", $0) }.joined(), to: targetHashData.map { String(format: "%02x", $0) }.joined(), message: message.data).map { $0.encode() }
            
        case BLEPacket.TYPE_UNMATCH:
            let unmatchPacket = BLEPacket.createUnmatch(from: currentUserHash.map { String(format: "%02x", $0) }.joined(), to: targetHashData.map { String(format: "%02x", $0) }.joined())
            packets = [unmatchPacket.encode()]
            
        case BLEPacket.TYPE_BLOCK:
            let blockPacket = BLEPacket.createBlock(from: currentUserHash.map { String(format: "%02x", $0) }.joined(), to: targetHashData.map { String(format: "%02x", $0) }.joined())
            packets = [blockPacket.encode()]
            
        default:
            print("⚠️ BLEManager: Unknown message type: \(message.type)")
            return
        }
        
        print("📤 BLEManager: Transmitting \(packets.count) packets for message type \(message.type)")
        
        // CRITICAL FIX: For match requests, use MUCH longer burst duration (15 seconds for Android compatibility)
        let burstDuration: TimeInterval = (message.type == BLEPacket.TYPE_MATCH_REQ || message.type == BLEPacket.TYPE_MATCH_ACC || message.type == BLEPacket.TYPE_MATCH_REJ) ? 15.0 : 2.0
        
        // Transmit first packet immediately
        if let firstPacket = packets.first {
            transmitPacketViaAdvertising(firstPacket, duration: burstDuration)
        }
        
        // Transmit remaining packets with delay
        if packets.count > 1 {
            for index in 1..<packets.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * burstDuration) { [weak self] in
                    self?.transmitPacketViaAdvertising(packets[index], duration: burstDuration)
                }
            }
        }
    }
    
    private func transmitPacketViaAdvertising(_ packet: Data, duration: TimeInterval = 2.0) {
        print("📤 BLEManager: Transmitting packet via service data (\(packet.count) bytes, duration: \(duration)s)")
        
        // CRITICAL FIX: Always stop advertising before message burst
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
            print("🛑 BLEManager: Stopped advertising for message burst")
        }
        
        // Clear advertising flag
        isAdvertising = false
        
        print("📤 BLEManager: Service data: \(packet.count) bytes")
        
        // CRITICAL FIX: Check packet TYPE (byte 1, not byte 0!)
        let isMatchMessage = packet.count > 1 && (packet[1] == BLEPacket.TYPE_MATCH_REQ || packet[1] == BLEPacket.TYPE_MATCH_ACC || packet[1] == BLEPacket.TYPE_MATCH_REJ)
        
        if isMatchMessage {
            print(" BLEManager: Match message detected - will repeat every 2s for \(duration)s")
            var repeatCount = 0
            let maxRepeats = Int(duration / 2.0)
            
            func repeatAdvertising() {
                guard repeatCount < maxRepeats else {
                    print(" BLEManager: Message burst complete after \(repeatCount) repeats")
                    // Resume normal advertising
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self else { return }
                        print(" BLEManager: Resuming normal advertising")
                        self.startAdvertising()
                    }
                    return
                }
                
                // Stop previous advertising
                self.peripheralManager.stopAdvertising()
                
                // CRITICAL FIX: Use manufacturer data for Android compatibility
                let advertisementData: [String: Any] = [
                    CBAdvertisementDataServiceUUIDsKey: [AURA_SERVICE_UUID],
                    CBAdvertisementDataLocalNameKey: "Aura",
                    CBAdvertisementDataManufacturerDataKey: packet
                ]
                
                self.peripheralManager.startAdvertising(advertisementData)
                print("✅ BLEManager: Message advertising repeat #\(repeatCount + 1)/\(maxRepeats)")
                
                repeatCount += 1
                
                // Schedule next repeat
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    repeatAdvertising()
                }
            }
            
            // Start first repeat
            repeatAdvertising()
            
        } else {
            // Non-match message - single burst
            let advertisementData: [String: Any] = [
                CBAdvertisementDataServiceUUIDsKey: [AURA_SERVICE_UUID],
                CBAdvertisementDataLocalNameKey: "Aura",
                CBAdvertisementDataManufacturerDataKey: packet
            ]
            
            peripheralManager.startAdvertising(advertisementData)
            print("✅ BLEManager: Message advertising started (burst mode, \(duration)s)")
            
            // Stop message advertising after duration and resume normal advertising
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self = self else { return }
                
                self.peripheralManager.stopAdvertising()
                print("🛑 BLEManager: Message advertising stopped (burst complete)")
                
                // Resume normal advertising
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    print(" BLEManager: Resuming normal advertising")
                    self.startAdvertising()
                }
            }
        }
    }
    
    // MARK: - Premium Features
    
    func setHighPowerMode(_ enabled: Bool) {
        isHighPowerMode = enabled
        print("🔥 BLEManager: High power mode: \(enabled)")
    }
    
    func setFastScanMode(_ enabled: Bool) {
        isFastScanMode = enabled
        print("⚡ BLEManager: Fast scan mode: \(enabled)")
    }
    
    func setPriorityMode(_ enabled: Bool) {
        isPriorityMode = enabled
        print("🌅 BLEManager: Priority mode: \(enabled)")
    }
    
    func setMoodData(_ moodType: String, _ moodMessage: String) {
        currentMoodType = moodType
        currentMoodMessage = moodMessage
        print("😊 BLEManager: Mood set: \(moodType) - \(moodMessage)")
        
        // Update GATT characteristic with new mood data
        updateGATTCharacteristic()
    }
    
    func clearMoodData() {
        currentMoodType = nil
        currentMoodMessage = nil
        print("😊 BLEManager: Mood cleared")
        
        // Update GATT characteristic
        updateGATTCharacteristic()
    }
    
    // MARK: - Private Methods
    
    private func shouldProcessMessage(_ senderHash: String, _ messageType: UInt8) -> Bool {
        let messageKey = "\(senderHash)_\(messageType)"
        let currentTime = Date()
        
        // Special handling for match requests
        if messageType == BLEPacket.TYPE_MATCH_REQ {
            if let lastRequest = matchRequestTracker[senderHash] {
                if currentTime.timeIntervalSince(lastRequest) < MATCH_REQUEST_COOLDOWN {
                    print("🚫 BLEManager: MATCH_REQ_COOLDOWN: Ignoring match request from \(senderHash)")
                    return false
                }
            }
            matchRequestTracker[senderHash] = currentTime
        }
        
        // Clean up old timeouts
        let expiredKeys = messageTimeouts.filter { currentTime.timeIntervalSince($0.value) > MESSAGE_TIMEOUT }.map { $0.key }
        expiredKeys.forEach {
            messageTimeouts.removeValue(forKey: $0)
            processedMessages.remove($0)
        }
        
        // Clean up old match request tracking
        matchRequestTracker = matchRequestTracker.filter { currentTime.timeIntervalSince($0.value) < MATCH_REQUEST_COOLDOWN }
        
        // Check if already processed
        if processedMessages.contains(messageKey) {
            if let timestamp = messageTimeouts[messageKey] {
                if currentTime.timeIntervalSince(timestamp) < MESSAGE_TIMEOUT {
                    print("🚫 BLEManager: DUPLICATE: Ignoring duplicate message from \(senderHash), type: \(messageType)")
                    return false
                }
            }
        }
        
        // Mark as processed
        processedMessages.insert(messageKey)
        messageTimeouts[messageKey] = currentTime
        print("✅ BLEManager: PROCESSING: New message from \(senderHash), type: \(messageType)")
        return true
    }
    
    private func handleIncomingPacket(_ frame: BLEPacket.DecodedFrame) {
        let senderHashString = frame.senderHash.hexString
        
        // CRITICAL: Check if message is for me (except PRESENCE)
        if frame.type != BLEPacket.TYPE_PRESENCE {
            if frame.targetHash != currentUserHash {
                print("🚫 BLEManager: Message not for me (target: \(frame.targetHash.hexString), me: \(currentUserHash.hexString))")
                return
            }
        }
        
        // Check if should process
        guard shouldProcessMessage(senderHashString, frame.type) else {
            return
        }
        
        // Handle based on type
        switch frame.type {
        case BLEPacket.TYPE_PRESENCE:
            handlePresencePacket(frame)
            
        case BLEPacket.TYPE_MATCH_REQ:
            handleMatchRequest(frame)
            
        case BLEPacket.TYPE_MATCH_ACC:
            handleMatchAccept(frame)
            
        case BLEPacket.TYPE_MATCH_REJ:
            handleMatchReject(frame)
            
        case BLEPacket.TYPE_CHAT:
            if frame.isComplete, let message = frame.completeMessage {
                handleChatMessage(frame, message: message)
            }
            
        case BLEPacket.TYPE_UNMATCH:
            handleUnmatch(frame)
            
        case BLEPacket.TYPE_BLOCK:
            handleBlock(frame)
            
        default:
            print("⚠️ BLEManager: Unknown packet type: \(frame.type)")
        }
    }
    
    private func handlePresencePacket(_ frame: BLEPacket.DecodedFrame) {
        let senderHashString = frame.senderHash.hexString
        
        // Parse gender and userName from chunk data
        var gender = "U"
        var userName = "User\(senderHashString.prefix(4).uppercased())"
        
        if frame.chunkData.count > 0 {
            // CRITICAL FIX: Parse gender byte correctly
            let genderByte = frame.chunkData[0]
            gender = genderByte == 0x01 ? "M" : (genderByte == 0x02 ? "F" : "U")
            
            if frame.chunkData.count > 1 {
                if let name = String(data: frame.chunkData.subdata(in: 1..<frame.chunkData.count), encoding: .utf8) {
                    userName = name
                }
            }
        }
        
        // Update or add nearby user
        let user = NearbyUser(userHash: senderHashString, userName: userName, gender: gender, rssi: -50)
        nearbyUsersDict[senderHashString] = user
        nearbyUsers = Array(nearbyUsersDict.values)
        
        print("👤 BLEManager: Presence from \(senderHashString): \(userName) (\(gender))")
    }
    
    private func handleMatchRequest(_ frame: BLEPacket.DecodedFrame) {
        let senderHashString = frame.senderHash.hexString
        
        // Extract gender from chunk data
        var senderGender = "U"
        if frame.chunkData.count > 0 {
            // CRITICAL FIX: Parse gender byte correctly
            let genderByte = frame.chunkData[0]
            senderGender = genderByte == 0x01 ? "M" : (genderByte == 0x02 ? "F" : "U")
        }
        
        print("💌 BLEManager: Match request from \(senderHashString) (\(senderGender))")
        
        // Store pending request
        MatchStore.shared.storePendingRequest(fromUserHash: senderHashString, fromGender: senderGender)
        
        // Notify listeners
        listeners.forEach { $0.onIncomingMatchRequest(senderHash: senderHashString) }
        
        // Post notification
        NotificationCenter.default.post(name: .matchRequestReceived, object: nil, userInfo: ["senderHash": senderHashString])
    }
    
    private func handleMatchAccept(_ frame: BLEPacket.DecodedFrame) {
        let senderHashString = frame.senderHash.hexString
        
        // Extract gender
        var senderGender = "U"
        if frame.chunkData.count > 0 {
            // CRITICAL FIX: Parse gender byte correctly
            let genderByte = frame.chunkData[0]
            senderGender = genderByte == 0x01 ? "M" : (genderByte == 0x02 ? "F" : "U")
        }
        
        print("✅ BLEManager: Match accepted from \(senderHashString) (\(senderGender))")
        
        // Store match
        MatchStore.shared.storeMatch(userHash: senderHashString, gender: senderGender)
        
        // Notify listeners
        listeners.forEach { $0.onMatchAccepted(senderHash: senderHashString) }
        
        // Post notification
        NotificationCenter.default.post(name: .matchAccepted, object: nil, userInfo: ["senderHash": senderHashString])
    }
    
    private func handleMatchReject(_ frame: BLEPacket.DecodedFrame) {
        let senderHashString = frame.senderHash.hexString
        
        print("❌ BLEManager: Match rejected from \(senderHashString)")
        
        // Notify listeners
        listeners.forEach { $0.onMatchRejected(senderHash: senderHashString) }
        
        // Post notification
        NotificationCenter.default.post(name: .matchRejected, object: nil, userInfo: ["senderHash": senderHashString])
    }
    
    private func handleChatMessage(_ frame: BLEPacket.DecodedFrame, message: String) {
        let senderHashString = frame.senderHash.hexString
        
        print("💬 BLEManager: Chat message from \(senderHashString): \(message.prefix(50))")
        
        // Store message
        let chatMessage = ChatStore.ChatMessage(
            matchId: senderHashString,
            senderId: senderHashString,
            receiverId: currentUserHash.hexString,
            content: message,
            isFromMe: false
        )
        ChatStore.shared.storeMessage(chatMessage)
        
        // Notify listeners
        listeners.forEach { $0.onChatMessage(senderHash: senderHashString, message: message) }
        
        // Post notification
        NotificationCenter.default.post(name: .chatMessageReceived, object: nil, userInfo: ["senderHash": senderHashString, "message": message])
    }
    
    private func handleUnmatch(_ frame: BLEPacket.DecodedFrame) {
        let senderHashString = frame.senderHash.hexString
        
        print("💔 BLEManager: Unmatch from \(senderHashString)")
        
        // Remove match
        MatchStore.shared.removeMatch(userHash: senderHashString)
        
        // Notify listeners
        listeners.forEach { $0.onUnmatchReceived(senderHash: senderHashString) }
        
        // Post notification
        NotificationCenter.default.post(name: .unmatchReceived, object: nil, userInfo: ["senderHash": senderHashString])
    }
    
    private func handleBlock(_ frame: BLEPacket.DecodedFrame) {
        let senderHashString = frame.senderHash.hexString
        
        print("🚫 BLEManager: Block from \(senderHashString)")
        
        // Remove match
        MatchStore.shared.removeMatch(userHash: senderHashString)
        
        // Notify listeners
        listeners.forEach { $0.onBlockReceived(senderHash: senderHashString) }
        
        // Post notification
        NotificationCenter.default.post(name: .blockReceived, object: nil, userInfo: ["senderHash": senderHashString])
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("📱 BLEManager: Central state: \(central.state.rawValue)")
        
        switch central.state {
        case .poweredOn:
            print("✅ BLEManager: Bluetooth powered on")
            // CRITICAL FIX: Start scanning when Bluetooth is ready
            if !isScanning {
                print("🔍 BLEManager: Auto-starting scan (Bluetooth just powered on)")
                startScanning()
            }
        case .poweredOff:
            print("❌ BLEManager: Bluetooth powered off")
        case .unauthorized:
            print("⚠️ BLEManager: Bluetooth unauthorized")
        case .unsupported:
            print("❌ BLEManager: Bluetooth unsupported")
        default:
            print("⚠️ BLEManager: Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        // Simple discovery - only check device name and manufacturer data
        let deviceName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        
        // Try to extract manufacturer data (from Android devices)
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            print("📦 BLEManager: Found manufacturer data (\(manufacturerData.count) bytes) from Android")
            
            // CRITICAL FIX: Skip first 2 bytes (company ID 0xFFFF)
            // Android sends: [0xFF, 0xFF, VERSION, TYPE, ...]
            // We need to decode from: [VERSION, TYPE, ...]
            guard manufacturerData.count > 2 else {
                print("⚠️ BLEManager: Manufacturer data too small (need > 2 bytes)")
                return
            }
            
            let payloadData = manufacturerData.subdata(in: 2..<manufacturerData.count)
            print("📦 BLEManager: Stripped company ID, payload: \(payloadData.count) bytes")
            
            // Decode Android packet
            guard let frame = BLEPacket.decode(payloadData) else {
                print("⚠️ BLEManager: Failed to decode manufacturer data")
                return
            }
            
            print("✅ BLEManager: Decoded Android packet from \(frame.senderHash.hexString)")
            
            // Handle packet
            handleIncomingPacket(frame)
        }
        // Check if device name is "Aura" (iOS device with GATT)
        else if deviceName == "Aura" {
            print("📱 BLEManager: iOS device detected, connecting...")
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ BLEManager: Connected to iOS device: \(peripheral.identifier)")
        
        // Discover Aura service
        peripheral.discoverServices([AURA_SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("❌ BLEManager: Failed to connect to iOS device: \(error?.localizedDescription ?? "unknown")")
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("🔌 BLEManager: Disconnected from iOS device")
    }
}

// MARK: - CBPeripheralDelegate (for reading iOS characteristics)
extension BLEManager: CBPeripheralDelegate {
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ BLEManager: Error discovering services: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        guard let services = peripheral.services else {
            print("⚠️ BLEManager: No services found")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        // Find Aura service
        for service in services {
            if service.uuid == AURA_SERVICE_UUID {
                print("✅ BLEManager: Found Aura service, discovering characteristics...")
                peripheral.discoverCharacteristics([PRESENCE_CHARACTERISTIC_UUID], for: service)
                return
            }
        }
        
        print("⚠️ BLEManager: Aura service not found")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ BLEManager: Error discovering characteristics: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        guard let characteristics = service.characteristics else {
            print("⚠️ BLEManager: No characteristics found")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        // Find presence characteristic
        for characteristic in characteristics {
            if characteristic.uuid == PRESENCE_CHARACTERISTIC_UUID {
                print("✅ BLEManager: Found presence characteristic, reading value...")
                peripheral.readValue(for: characteristic)
                return
            }
        }
        
        print("⚠️ BLEManager: Presence characteristic not found")
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ BLEManager: Error reading characteristic: \(error.localizedDescription)")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        guard let data = characteristic.value else {
            print("⚠️ BLEManager: No data in characteristic")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        print("📦 BLEManager: Read \(data.count) bytes from iOS device")
        
        // Decode presence packet
        guard let frame = BLEPacket.decode(data) else {
            print("❌ BLEManager: Failed to decode presence packet")
            centralManager.cancelPeripheralConnection(peripheral)
            return
        }
        
        // Handle presence packet
        handleIncomingPacket(frame)
        
        // Disconnect after reading
        centralManager.cancelPeripheralConnection(peripheral)
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BLEManager: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("📱 BLEManager: Peripheral state: \(peripheral.state.rawValue)")
        
        switch peripheral.state {
        case .poweredOn:
            print("✅ BLEManager: Peripheral powered on")
            // Setup GATT server when Bluetooth is ready
            setupGATTServer()
            // CRITICAL FIX: Start advertising when Bluetooth is ready (if visibility enabled)
            if UserPreferences.shared.isVisibilityEnabled && !isAdvertising {
                print("📡 BLEManager: Auto-starting advertising (Bluetooth just powered on)")
                startAdvertising()
            }
        case .poweredOff:
            print("❌ BLEManager: Peripheral powered off")
        case .unauthorized:
            print("⚠️ BLEManager: Peripheral unauthorized")
        case .unsupported:
            print("❌ BLEManager: Peripheral unsupported")
        default:
            print("⚠️ BLEManager: Peripheral state: \(peripheral.state.rawValue)")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("❌ BLEManager: Advertising failed: \(error.localizedDescription)")
            isAdvertising = false
        } else {
            print("✅ BLEManager: Advertising started successfully")
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("❌ BLEManager: Failed to add service: \(error.localizedDescription)")
            print("❌ BLEManager: Error code: \((error as NSError).code)")
            print("❌ BLEManager: Error domain: \((error as NSError).domain)")
        } else {
            print("✅ BLEManager: GATT service added successfully!")
            
            // Safe UUID printing
            let serviceUUID = service.uuid.uuidString
            print("✅ BLEManager: Service UUID: \(serviceUUID)")
            print("✅ BLEManager: Service isPrimary: \(service.isPrimary)")
            print("✅ BLEManager: Service has \(service.characteristics?.count ?? 0) characteristics")
            
            // CRITICAL: Verify characteristic is present
            if let characteristics = service.characteristics {
                print("✅ BLEManager: Characteristics array:")
                for (index, char) in characteristics.enumerated() {
                    let charUUID = char.uuid.uuidString
                    print("   [\(index)] UUID: \(charUUID)")
                    print("   [\(index)] Properties: \(char.properties.rawValue)")
                    // Note: permissions only available on CBMutableCharacteristic, not CBCharacteristic
                }
                
                // Verify our characteristic is there
                let hasPresenceChar = characteristics.contains { $0.uuid == PRESENCE_CHARACTERISTIC_UUID }
                if hasPresenceChar {
                    print("✅ BLEManager: ✓ Presence characteristic CONFIRMED in service")
                } else {
                    print("❌ BLEManager: ✗ Presence characteristic NOT FOUND in service!")
                }
            } else {
                print("❌ BLEManager: Service has NO characteristics array!")
            }
            
            // Update characteristic with initial user data
            updateGATTCharacteristic()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("📖 BLEManager: ===== READ REQUEST RECEIVED =====")
        
        let charUUID = request.characteristic.uuid.uuidString
        print("📖 BLEManager: Characteristic UUID: \(charUUID)")
        print("📖 BLEManager: Offset: \(request.offset)")
        print("📖 BLEManager: Central: \(request.central.identifier)")
        
        if request.characteristic.uuid == PRESENCE_CHARACTERISTIC_UUID {
            print("✅ BLEManager: Correct characteristic requested!")
            
            // Create fresh presence packet
            let packets = BLEPacket.encodePresenceWithNameAndGender(senderHash: currentUserHash, userName: currentUserName, gender: currentUserGender)
            
            if let packet = packets.first {
                print("✅ BLEManager: Created presence packet: \(packet.count) bytes")
                print("   - UserHash: \(currentUserHash.hexString)")
                print("   - UserName: \(currentUserName)")
                print("   - Gender: \(currentUserGender)")
                
                // Set the value
                request.value = packet
                
                // Respond with success
                peripheralManager.respond(to: request, withResult: .success)
                
                print("✅ BLEManager: Responded to read request successfully")
            } else {
                print("❌ BLEManager: Failed to create presence packet!")
                peripheralManager.respond(to: request, withResult: .unlikelyError)
            }
        } else {
            let expectedUUID = PRESENCE_CHARACTERISTIC_UUID.uuidString
            print("⚠️ BLEManager: Unknown characteristic requested: \(charUUID)")
            print("⚠️ BLEManager: Expected: \(expectedUUID)")
            peripheralManager.respond(to: request, withResult: .attributeNotFound)
        }
        
        print("📖 BLEManager: ===== READ REQUEST COMPLETE =====")
    }
    
    // MARK: - Background/Foreground Handling
    
    func enterBackground() {
        print("🌙 BLEManager: Entering background mode")
        // Keep scanning active in background
        // iOS automatically handles background BLE
    }
    
    func enterForeground() {
        print("☀️ BLEManager: Entering foreground mode")
        // Resume full BLE functionality
        if !isScanning {
            startScanning()
        }
        // Restart advertising if it should be active
        if UserPreferences.shared.isVisibilityEnabled && !isAdvertising {
            startAdvertising()
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let matchRequestReceived = Notification.Name("matchRequestReceived")
    static let matchRequestSent = Notification.Name("matchRequestSent")
    static let matchAccepted = Notification.Name("matchAccepted")
    static let matchRejected = Notification.Name("matchRejected")
    static let chatMessageReceived = Notification.Name("chatMessageReceived")
    static let unmatchReceived = Notification.Name("unmatchReceived")
    static let blockReceived = Notification.Name("blockReceived")
}

// MARK: - Data Extension
extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hexString.index(hexString.startIndex, offsetBy: i*2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}
