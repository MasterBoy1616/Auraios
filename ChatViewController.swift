import UIKit
import Combine

class ChatViewController: UIViewController {
    
    private var cancellables = Set<AnyCancellable>()
    private let match: MatchStore.Match
    
    // UI Elements
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.textColor = UIColor.white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("← Back", for: .normal)
        button.setTitleColor(UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.transform = CGAffineTransform(scaleX: 1, y: -1) // Flip for bottom-up
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let inputContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let messageTextField: UITextField = {
        let field = UITextField()
        field.placeholder = "Type a message..."
        field.textColor = .white
        field.backgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 1.0)
        field.layer.cornerRadius = 20
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 15, height: 0))
        field.leftViewMode = .always
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()
    
    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Send", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var messages: [ChatStore.ChatMessage] = []
    private var isSendingMessage = false
    
    // Duplicate prevention
    private var processedMessageIds = Set<String>()
    
    init(match: MatchStore.Match) {
        self.match = match
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        
        setupUI()
        setupTableView()
        setupActions()
        setupObservers()
        loadMessages()
        
        // Add BLE listener
        BLEManager.shared.addListener(self)
        
        // CRITICAL: Force advertising ON for chat
        UserPreferences.shared.setVisibilityEnabled(true)
        BLEManager.shared.startAdvertising()
        BLEManager.shared.startScanning()
        
        // Setup keyboard observers
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        print("💬 ChatViewController: Loaded for match: \(match.userHash)")
    }
    
    private func setupUI() {
        view.addSubview(backButton)
        view.addSubview(headerLabel)
        view.addSubview(tableView)
        view.addSubview(inputContainer)
        inputContainer.addSubview(messageTextField)
        inputContainer.addSubview(sendButton)
        
        NSLayoutConstraint.activate([
            // Back Button
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            // Header
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // TableView
            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainer.topAnchor),
            
            // Input Container
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 60),
            
            // Message TextField
            messageTextField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 15),
            messageTextField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            messageTextField.heightAnchor.constraint(equalToConstant: 40),
            
            // Send Button
            sendButton.leadingAnchor.constraint(equalTo: messageTextField.trailingAnchor, constant: 10),
            sendButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -15),
            sendButton.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 70),
            sendButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Set header text
        let genderIcon = match.gender == "M" ? "♂️" : match.gender == "F" ? "♀️" : "👤"
        headerLabel.text = "\(genderIcon) \(match.userName)"
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: "ChatMessageCell")
    }
    
    private func setupActions() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        messageTextField.delegate = self
    }
    
    private func setupObservers() {
        // Observe chat messages
        ChatStore.shared.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadMessages()
            }
            .store(in: &cancellables)
        
        // Observe unmatch/block notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleUnmatch), name: .unmatchReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBlock), name: .blockReceived, object: nil)
    }
    
    private func loadMessages() {
        messages = ChatStore.shared.getMessages(forUserHash: match.userHash)
        tableView.reloadData()
        
        // Scroll to bottom (which is top due to flip)
        if !messages.isEmpty {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        }
        
        print("💬 ChatViewController: Loaded \(messages.count) messages")
    }
    
    @objc private func sendMessage() {
        guard let text = messageTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }
        
        // Prevent double sending
        guard !isSendingMessage else {
            print("🚫 ChatViewController: Already sending message")
            return
        }
        
        isSendingMessage = true
        sendButton.isEnabled = false
        
        print("📤 ChatViewController: Sending message: \(text.prefix(20))...")
        
        // Clear input immediately
        messageTextField.text = ""
        
        // Send via BLE
        BLEManager.shared.sendChatMessage(text, to: match.userHash)
        
        // Re-enable after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isSendingMessage = false
            self?.sendButton.isEnabled = true
        }
    }
    
    @objc private func backTapped() {
        dismiss(animated: true)
    }
    
    @objc private func handleUnmatch(_ notification: Notification) {
        guard let senderHash = notification.userInfo?["senderHash"] as? String,
              senderHash == match.userHash else {
            return
        }
        
        let alert = UIAlertController(title: "Match Cancelled", message: "This match has been cancelled.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    @objc private func handleBlock(_ notification: Notification) {
        guard let senderHash = notification.userInfo?["senderHash"] as? String,
              senderHash == match.userHash else {
            return
        }
        
        let alert = UIAlertController(title: "Blocked", message: "You have been blocked by this user.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        
        let keyboardHeight = keyboardFrame.height
        
        UIView.animate(withDuration: 0.3) {
            self.inputContainer.transform = CGAffineTransform(translationX: 0, y: -keyboardHeight + self.view.safeAreaInsets.bottom)
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        UIView.animate(withDuration: 0.3) {
            self.inputContainer.transform = .identity
        }
    }
    
    deinit {
        BLEManager.shared.removeListener(self)
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource
extension ChatViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatMessageCell", for: indexPath) as! ChatMessageCell
        
        // Reverse index due to flip
        let message = messages[messages.count - 1 - indexPath.row]
        cell.configure(with: message)
        cell.transform = CGAffineTransform(scaleX: 1, y: -1) // Flip back
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// MARK: - UITextFieldDelegate
extension ChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendMessage()
        return true
    }
}

// MARK: - BLEManagerListener
extension ChatViewController: BLEManager.BLEManagerListener {
    func onIncomingMatchRequest(senderHash: String) {}
    func onMatchAccepted(senderHash: String) {}
    func onMatchRejected(senderHash: String) {}
    
    func onChatMessage(senderHash: String, message: String) {
        // Only handle messages from our chat partner
        guard senderHash == match.userHash else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("💬 ChatViewController: Received message from partner: \(message.prefix(20))...")
            
            // Enhanced duplicate prevention
            let messageContent = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let contentHash = messageContent.hashValue
            let currentTime = Date().timeIntervalSince1970
            let timeWindow = Int(currentTime / 5.0) // 5-second window
            let messageId = "\(senderHash)_\(contentHash)_\(timeWindow)"
            
            // Check if already processed
            if self.processedMessageIds.contains(messageId) {
                print("🚫 ChatViewController: DUPLICATE message, skipping: \(messageId)")
                return
            }
            
            // Check recent messages in store
            let existingMessages = ChatStore.shared.getMessages(forUserHash: senderHash).filter {
                !$0.isFromMe &&
                $0.content == messageContent &&
                (currentTime - $0.timestamp) < 10.0
            }
            
            if !existingMessages.isEmpty {
                print("🚫 ChatViewController: Message already exists in store, skipping")
                return
            }
            
            self.processedMessageIds.insert(messageId)
            print("✅ ChatViewController: NEW_MESSAGE: Processing message: \(messageId)")
            
            // Clean up old processed IDs
            if self.processedMessageIds.count > 50 {
                let toRemove = Array(self.processedMessageIds.prefix(self.processedMessageIds.count - 50))
                toRemove.forEach { self.processedMessageIds.remove($0) }
            }
            
            // Refresh UI
            self.loadMessages()
        }
    }
    
    func onPhotoReceived(senderHash: String, photoBase64: String) {
        guard senderHash == match.userHash else { return }
        print("📷 ChatViewController: Photo received from partner")
    }
    
    func onPhotoRequested(senderHash: String) {
        guard senderHash == match.userHash else { return }
        print("📷 ChatViewController: Photo requested by partner")
    }
    
    func onUnmatchReceived(senderHash: String) {
        guard senderHash == match.userHash else { return }
        
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: "Match Cancelled", message: "This match has been cancelled.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self?.dismiss(animated: true)
            })
            self?.present(alert, animated: true)
        }
    }
    
    func onBlockReceived(senderHash: String) {
        guard senderHash == match.userHash else { return }
        
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: "Blocked", message: "You have been blocked.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self?.dismiss(animated: true)
            })
            self?.present(alert, animated: true)
        }
    }
}

// MARK: - ChatMessageCell
class ChatMessageCell: UITableViewCell {
    
    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 15
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .lightGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
        
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(timeLabel)
        
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15)
        
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            
            timeLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 5),
            timeLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            timeLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            timeLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with message: ChatStore.ChatMessage) {
        messageLabel.text = message.content
        
        let date = Date(timeIntervalSince1970: message.timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: date)
        
        if message.isFromMe {
            // Sent message (right side, blue)
            bubbleView.backgroundColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
            messageLabel.textColor = .white
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
        } else {
            // Received message (left side, gray)
            bubbleView.backgroundColor = UIColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1.0)
            messageLabel.textColor = .white
            trailingConstraint.isActive = false
            leadingConstraint.isActive = true
        }
    }
}
