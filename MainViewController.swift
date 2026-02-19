import UIKit
import Combine

class MainViewController: UIViewController {
    
    private var cancellables = Set<AnyCancellable>()
    
    // UI Elements
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = "AURA"
        label.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Scanning..."
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.textColor = .lightGray
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let radarView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 0.1)
        view.layer.cornerRadius = 100
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
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
        button.setTitleColor(.white, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let matchesButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("💕 Matches", for: .normal)
        button.setTitleColor(.lightGray, for: .normal)
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
    
    private var nearbyUsers: [BLEManager.NearbyUser] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0)
        
        setupUI()
        setupTableView()
        setupActions()
        setupObservers()
        
        // Start BLE
        BLEManager.shared.startScanning()
        if UserPreferences.shared.isVisibilityEnabled {
            BLEManager.shared.startAdvertising()
        }
        
        // Start radar animation
        startRadarAnimation()
        
        print("🎨 MainViewController: Loaded")
    }
    
    private func setupUI() {
        view.addSubview(headerLabel)
        view.addSubview(statusLabel)
        view.addSubview(radarView)
        view.addSubview(tableView)
        view.addSubview(bottomTabBar)
        
        bottomTabBar.addSubview(discoverButton)
        bottomTabBar.addSubview(matchesButton)
        bottomTabBar.addSubview(profileButton)
        
        NSLayoutConstraint.activate([
            // Header
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Status
            statusLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Radar
            radarView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 30),
            radarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            radarView.widthAnchor.constraint(equalToConstant: 200),
            radarView.heightAnchor.constraint(equalToConstant: 200),
            
            // TableView
            tableView.topAnchor.constraint(equalTo: radarView.bottomAnchor, constant: 30),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomTabBar.topAnchor),
            
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
        tableView.register(NearbyUserCell.self, forCellReuseIdentifier: "NearbyUserCell")
    }
    
    private func setupActions() {
        discoverButton.addTarget(self, action: #selector(discoverTapped), for: .touchUpInside)
        matchesButton.addTarget(self, action: #selector(matchesTapped), for: .touchUpInside)
        profileButton.addTarget(self, action: #selector(profileTapped), for: .touchUpInside)
        
        // Header tap to toggle broadcast
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(headerTapped))
        headerLabel.isUserInteractionEnabled = true
        headerLabel.addGestureRecognizer(tapGesture)
    }
    
    private func setupObservers() {
        // Observe nearby users
        BLEManager.shared.$nearbyUsers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] users in
                self?.nearbyUsers = users
                self?.tableView.reloadData()
                self?.statusLabel.text = "Found \(users.count) users"
            }
            .store(in: &cancellables)
        
        // Observe match requests
        NotificationCenter.default.addObserver(self, selector: #selector(handleMatchRequest), name: .matchRequestReceived, object: nil)
    }
    
    private func startRadarAnimation() {
        UIView.animate(withDuration: 2.0, delay: 0, options: [.repeat, .autoreverse], animations: {
            self.radarView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            self.radarView.alpha = 0.3
        })
    }
    
    @objc private func headerTapped() {
        let isVisible = UserPreferences.shared.isVisibilityEnabled
        UserPreferences.shared.isVisibilityEnabled = !isVisible
        
        if !isVisible {
            BLEManager.shared.startAdvertising()
            showToast("📡 Broadcasting ON")
        } else {
            BLEManager.shared.stopAdvertising()
            showToast("📡 Broadcasting OFF")
        }
    }
    
    @objc private func discoverTapped() {
        // Already on discover
        print("🔍 Discover tab")
    }
    
    @objc private func matchesTapped() {
        let matchesVC = MatchesViewController()
        matchesVC.modalPresentationStyle = .fullScreen
        present(matchesVC, animated: true)
        print("💕 Matches tab")
    }
    
    @objc private func profileTapped() {
        let profileVC = ProfileViewController()
        profileVC.modalPresentationStyle = .fullScreen
        present(profileVC, animated: true)
        print("👤 Profile tab")
    }
    
    @objc private func handleMatchRequest(_ notification: Notification) {
        guard let senderHash = notification.userInfo?["senderHash"] as? String else { return }
        
        let alert = UIAlertController(title: "Match Request", message: "Someone wants to match with you!", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Accept", style: .default) { [weak self] _ in
            BLEManager.shared.acceptMatchRequest(from: senderHash)
            self?.showToast("✅ Match Accepted!")
        })
        
        alert.addAction(UIAlertAction(title: "Reject", style: .cancel) { _ in
            BLEManager.shared.rejectMatchRequest(from: senderHash)
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
}

// MARK: - UITableViewDelegate, UITableViewDataSource
extension MainViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return nearbyUsers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "NearbyUserCell", for: indexPath) as! NearbyUserCell
        let user = nearbyUsers[indexPath.row]
        cell.configure(with: user)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let user = nearbyUsers[indexPath.row]
        
        let alert = UIAlertController(title: user.userName, message: "Send match request?", preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: "Send", style: .default) { [weak self] _ in
            BLEManager.shared.sendMatchRequest(to: user.userHash)
            self?.showToast("💌 Match request sent!")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
}

// MARK: - NearbyUserCell
class NearbyUserCell: UITableViewCell {
    
    private let userLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let genderLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 24)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let rssiLabel: UILabel = {
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
        contentView.addSubview(userLabel)
        contentView.addSubview(rssiLabel)
        
        NSLayoutConstraint.activate([
            genderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            genderLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            userLabel.leadingAnchor.constraint(equalTo: genderLabel.trailingAnchor, constant: 15),
            userLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            rssiLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rssiLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(with user: BLEManager.NearbyUser) {
        userLabel.text = user.userName
        genderLabel.text = user.gender == "M" ? "♂️" : user.gender == "F" ? "♀️" : "👤"
        rssiLabel.text = "\(user.rssi) dBm"
    }
}
