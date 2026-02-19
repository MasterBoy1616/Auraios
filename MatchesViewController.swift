import UIKit
import Combine

class MatchesViewController: UIViewController {
    
    private var cancellables = Set<AnyCancellable>()
    
    // UI Elements
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = "MATCHES"
        label.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let segmentedControl: UISegmentedControl = {
        let items = ["Requests", "Matches"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()
    
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No requests yet"
        label.font = UIFont.systemFont(ofSize: 18)
        label.textColor = .lightGray
        label.textAlignment = .center
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bottomTabBar: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let discoverButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("🔍 Discover", for: .normal)
        button.setTitleColor(.lightGray, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let matchesButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("💕 Matches", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let profileButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("👤 Profile", for: .normal)
        button.setTitleColor(.lightGray, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private var pendingRequests: [MatchStore.PendingRequest] = []
    private var matches: [MatchStore.Match] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        
        setupUI()
        setupTableView()
        setupActions()
        setupObservers()
        
        // Add BLE listener
        BLEManager.shared.addListener(self)
        
        // Ensure background scanning
        BLEManager.shared.startScanning()
        
        print("💕 MatchesViewController: Loaded")
    }
    
    private func setupUI() {
        view.addSubview(headerLabel)
        view.addSubview(segmentedControl)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(bottomTabBar)
        bottomTabBar.addSubview(discoverButton)
        bottomTabBar.addSubview(matchesButton)
        bottomTabBar.addSubview(profileButton)
        
        NSLayoutConstraint.activate([
            // Header
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Segmented Control
            segmentedControl.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 20),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            // TableView
            tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomTabBar.topAnchor),
            
            // Empty Label
            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            
            // Bottom Tab Bar
            bottomTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomTabBar.heightAnchor.constraint(equalToConstant: 80),
            
            // Tab Buttons
            discoverButton.leadingAnchor.constraint(equalTo: bottomTabBar.leadingAnchor, constant: 20),
            discoverButton.centerYAnchor.constraint(equalTo: bottomTabBar.centerYAnchor, constant: -10),
            discoverButton.widthAnchor.constraint(equalToConstant: 100),
            
            matchesButton.centerXAnchor.constraint(equalTo: bottomTabBar.centerXAnchor),
            matchesButton.centerYAnchor.constraint(equalTo: bottomTabBar.centerYAnchor, constant: -10),
            matchesButton.widthAnchor.constraint(equalToConstant: 100),
            
            profileButton.trailingAnchor.constraint(equalTo: bottomTabBar.trailingAnchor, constant: -20),
            profileButton.centerYAnchor.constraint(equalTo: bottomTabBar.centerYAnchor, constant: -10),
            profileButton.widthAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(RequestCell.self, forCellReuseIdentifier: "RequestCell")
        tableView.register(MatchCell.self, forCellReuseIdentifier: "MatchCell")
    }
    
    private func setupActions() {
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        discoverButton.addTarget(self, action: #selector(discoverTapped), for: .touchUpInside)
        matchesButton.addTarget(self, action: #selector(matchesTapped), for: .touchUpInside)
        profileButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)
    }
    
    private func setupObservers() {
        // Observe pending requests
        MatchStore.shared.$pendingRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests in
                self?.pendingRequests = requests
                if self?.segmentedControl.selectedSegmentIndex == 0 {
                    self?.updateUI()
                }
            }
            .store(in: &cancellables)
        
        // Observe matches
        MatchStore.shared.$matches
            .receive(on: DispatchQueue.main)
            .sink { [weak self] matches in
                self?.matches = matches
                if self?.segmentedControl.selectedSegmentIndex == 1 {
                    self?.updateUI()
                }
            }
            .store(in: &cancellables)
        
        // Observe match request notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleMatchRequest), name: .matchRequestReceived, object: nil)
    }
    
    private func updateUI() {
        let isEmpty = (segmentedControl.selectedSegmentIndex == 0 && pendingRequests.isEmpty) ||
                      (segmentedControl.selectedSegmentIndex == 1 && matches.isEmpty)
        
        emptyLabel.isHidden = !isEmpty
        tableView.isHidden = isEmpty
        
        if segmentedControl.selectedSegmentIndex == 0 {
            emptyLabel.text = "No match requests yet"
        } else {
            emptyLabel.text = "No matches yet"
        }
        
        tableView.reloadData()
    }
    
    @objc private func segmentChanged() {
        updateUI()
    }
    
    @objc private func discoverTapped() {
        dismiss(animated: true)
    }
    
    @objc private func matchesTapped() {
        // Already on matches
    }
    
    @objc private func profileTapped() {
        let profileVC = ProfileViewController()
        profileVC.modalPresentationStyle = .fullScreen
        present(profileVC, animated: true)
    }
    
    @objc private func handleMatchRequest(_ notification: Notification) {
        guard let senderHash = notification.userInfo?["senderHash"] as? String else { return }
        
        let alert = UIAlertController(title: "Match Request", message: "Someone wants to match with you!", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Accept", style: .default) { [weak self] _ in
            // Find request and accept
            if let request = self?.pendingRequests.first(where: { $0.fromUserHash == senderHash }) {
                _ = MatchStore.shared.acceptRequest(requestId: request.id)
                BLEManager.shared.acceptMatchRequest(from: senderHash)
                self?.showToast("✅ Match Accepted!")
            }
        })
        
        alert.addAction(UIAlertAction(title: "Reject", style: .cancel) { [weak self] _ in
            if let request = self?.pendingRequests.first(where: { $0.fromUserHash == senderHash }) {
                _ = MatchStore.shared.rejectRequest(requestId: request.id)
                BLEManager.shared.rejectMatchRequest(from: senderHash)
            }
        })
        
        present(alert, animated: true)
    }
    
    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.textColor = .white
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toast.textAlignment = .center
        toast.font = UIFont.systemFont(ofSize: 14)
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(toast)
        
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -100),
            toast.widthAnchor.constraint(equalToConstant: 200),
            toast.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
            toast.alpha = 0
        }) { _ in
            toast.removeFromSuperview()
        }
    }
    
    deinit {
        BLEManager.shared.removeListener(self)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource
extension MatchesViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return segmentedControl.selectedSegmentIndex == 0 ? pendingRequests.count : matches.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if segmentedControl.selectedSegmentIndex == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "RequestCell", for: indexPath) as! RequestCell
            let request = pendingRequests[indexPath.row]
            cell.configure(with: request)
            cell.onAccept = { [weak self] in
                self?.acceptRequest(request)
            }
            cell.onReject = { [weak self] in
                self?.rejectRequest(request)
            }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "MatchCell", for: indexPath) as! MatchCell
            let match = matches[indexPath.row]
            cell.configure(with: match)
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if segmentedControl.selectedSegmentIndex == 1 {
            let match = matches[indexPath.row]
            openChat(with: match)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    private func acceptRequest(_ request: MatchStore.PendingRequest) {
        _ = MatchStore.shared.acceptRequest(requestId: request.id)
        BLEManager.shared.acceptMatchRequest(from: request.fromUserHash)
        showToast("✅ Match Accepted!")
    }
    
    private func rejectRequest(_ request: MatchStore.PendingRequest) {
        _ = MatchStore.shared.rejectRequest(requestId: request.id)
        BLEManager.shared.rejectMatchRequest(from: request.fromUserHash)
        showToast("❌ Request Rejected")
    }
    
    private func openChat(with match: MatchStore.Match) {
        let chatVC = ChatViewController(match: match)
        chatVC.modalPresentationStyle = .fullScreen
        present(chatVC, animated: true)
    }
}

// MARK: - BLEManagerListener
extension MatchesViewController: BLEManager.BLEManagerListener {
    func onIncomingMatchRequest(senderHash: String) {
        // Handled by notification observer
    }
    
    func onMatchAccepted(senderHash: String) {
        DispatchQueue.main.async {
            self.showToast("✅ Match Accepted!")
        }
    }
    
    func onMatchRejected(senderHash: String) {
        DispatchQueue.main.async {
            self.showToast("❌ Match Rejected")
        }
    }
    
    func onChatMessage(senderHash: String, message: String) {
        DispatchQueue.main.async {
            self.showToast("💬 New message")
        }
    }
    
    func onPhotoReceived(senderHash: String, photoBase64: String) {}
    func onPhotoRequested(senderHash: String) {}
    
    func onUnmatchReceived(senderHash: String) {
        DispatchQueue.main.async {
            self.showToast("💔 Match cancelled")
            self.updateUI()
        }
    }
    
    func onBlockReceived(senderHash: String) {
        DispatchQueue.main.async {
            self.showToast("🚫 User blocked you")
            self.updateUI()
        }
    }
}

// MARK: - RequestCell
class RequestCell: UITableViewCell {
    
    private let genderLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 32)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .lightGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let acceptButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("✓", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.0, green: 0.8, blue: 0.4, alpha: 1.0)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let rejectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("✗", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    var onAccept: (() -> Void)?
    var onReject: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        
        contentView.addSubview(genderLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(acceptButton)
        contentView.addSubview(rejectButton)
        
        NSLayoutConstraint.activate([
            genderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            genderLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            timeLabel.leadingAnchor.constraint(equalTo: genderLabel.trailingAnchor, constant: 15),
            timeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            rejectButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rejectButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rejectButton.widthAnchor.constraint(equalToConstant: 40),
            rejectButton.heightAnchor.constraint(equalToConstant: 40),
            
            acceptButton.trailingAnchor.constraint(equalTo: rejectButton.leadingAnchor, constant: -10),
            acceptButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            acceptButton.widthAnchor.constraint(equalToConstant: 40),
            acceptButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)
        rejectButton.addTarget(self, action: #selector(rejectTapped), for: .touchUpInside)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with request: MatchStore.PendingRequest) {
        genderLabel.text = request.fromGender == "M" ? "♂️" : request.fromGender == "F" ? "♀️" : "👤"
        
        let date = Date(timeIntervalSince1970: request.timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: date)
    }
    
    @objc private func acceptTapped() {
        onAccept?()
    }
    
    @objc private func rejectTapped() {
        onReject?()
    }
}

// MARK: - MatchCell
class MatchCell: UITableViewCell {
    
    private let genderLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 32)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .lightGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        
        contentView.addSubview(genderLabel)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        
        NSLayoutConstraint.activate([
            genderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            genderLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            nameLabel.leadingAnchor.constraint(equalTo: genderLabel.trailingAnchor, constant: 15),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            
            timeLabel.leadingAnchor.constraint(equalTo: genderLabel.trailingAnchor, constant: 15),
            timeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with match: MatchStore.Match) {
        genderLabel.text = match.gender == "M" ? "♂️" : match.gender == "F" ? "♀️" : "👤"
        nameLabel.text = match.userName
        
        let date = Date(timeIntervalSince1970: match.matchedAt)
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        timeLabel.text = formatter.string(from: date)
    }
}
