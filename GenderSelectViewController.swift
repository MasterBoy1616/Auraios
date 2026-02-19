import UIKit

class GenderSelectionViewController: UIViewController {
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let maleButton = UIButton()
    private let femaleButton = UIButton()
    private let stackView = UIStackView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.043, green: 0.059, blue: 0.078, alpha: 1) // #0B0F14
        
        // Title
        titleLabel.text = "Cinsiyetinizi seçin"
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // Subtitle
        subtitleLabel.text = "Bu bilgi eşleşme için kullanılacak"
        subtitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)
        
        // Male button
        setupGenderButton(maleButton,
                         title: "👨 Erkek",
                         backgroundColor: UIColor(red: 0, green: 0.122, blue: 0.247, alpha: 1),
                         borderColor: UIColor(red: 0, green: 0.898, blue: 1, alpha: 1),
                         action: #selector(maleButtonTapped))
        
        // Female button
        setupGenderButton(femaleButton,
                         title: "👩 Kadın",
                         backgroundColor: UIColor(red: 0.302, green: 0.102, blue: 0.180, alpha: 1),
                         borderColor: UIColor(red: 1, green: 0.078, blue: 0.576, alpha: 1),
                         action: #selector(femaleButtonTapped))
        
        // Stack view
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.distribution = .fillEqually
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(maleButton)
        stackView.addArrangedSubview(femaleButton)
        view.addSubview(stackView)
        
        // Layout
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            maleButton.heightAnchor.constraint(equalToConstant: 60),
            femaleButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    private func setupGenderButton(_ button: UIButton, title: String, backgroundColor: UIColor, borderColor: UIColor, action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 2
        button.layer.borderColor = borderColor.cgColor
        button.addTarget(self, action: action, for: .touchUpInside)
        
        // Add press animation
        button.addTarget(self, action: #selector(buttonPressed(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(buttonReleased(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    @objc private func buttonPressed(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }
    
    @objc private func buttonReleased(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = .identity
        }
    }
    
    @objc private func maleButtonTapped() {
        selectGender(.male)
    }
    
    @objc private func femaleButtonTapped() {
        selectGender(.female)
    }
    
    private func selectGender(_ gender: Gender) {
        // Save gender preference
        UserPreferences.shared.gender = gender
        UserPreferences.shared.hasCompletedGenderSelection = true
        
        // CRITICAL FIX: Update BLE with new user data
        let userId = UserPreferences.shared.userId
        if !userId.isEmpty {
            BLEManager.shared.setCurrentUser(userId)
            print("✅ GenderSelection: Updated BLE with user data after gender selection")
        }
        
        // Show success animation
        let selectedButton = gender == .male ? maleButton : femaleButton
        
        UIView.animate(withDuration: 0.3, animations: {
            selectedButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            selectedButton.alpha = 0.8
        }, completion: { _ in
            UIView.animate(withDuration: 0.2, animations: {
                selectedButton.transform = .identity
                selectedButton.alpha = 1.0
            }, completion: { _ in
                // Navigate to main app
                self.navigateToMainApp()
            })
        })
    }
    
    private func navigateToMainApp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let mainViewController = MainViewController()
            mainViewController.modalPresentationStyle = .fullScreen
            self.present(mainViewController, animated: true)
        }
    }
}
