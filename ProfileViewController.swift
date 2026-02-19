import UIKit

class ProfileViewController: UIViewController {
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    private let profileImageView = UIImageView()
    private let nameTextField = UITextField()
    private let genderLabel = UILabel()
    private let changeGenderButton = UIButton()
    private let visibilitySwitch = UISwitch()
    private let userHashLabel = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadUserData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Refresh visibility switch state
        visibilitySwitch.isOn = UserPreferences.shared.isVisibilityEnabled
        
        // CRITICAL FIX: Force restart advertising if visibility is enabled
        // This ensures advertising is active even after tab switches
        if UserPreferences.shared.isVisibilityEnabled {
            print("🔄 ProfileViewController: Force restarting advertising (tab switch)")
            BLEManager.shared.stopAdvertising()
            
            // Small delay to ensure clean restart
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                BLEManager.shared.startAdvertising()
            }
        }
    }
    
    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.043, green: 0.059, blue: 0.078, alpha: 1) // #0B0F14
        navigationItem.title = "Profil"
        
        // Scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // Profile image
        profileImageView.backgroundColor = UIColor(red: 0.067, green: 0.094, blue: 0.125, alpha: 1)
        profileImageView.layer.cornerRadius = 60
        profileImageView.contentMode = .scaleAspectFill
        profileImageView.clipsToBounds = true
        profileImageView.isUserInteractionEnabled = true
        profileImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(profileImageTapped)))
        profileImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(profileImageView)
        
        // Name text field
        setupTextField(nameTextField, placeholder: "Adınızı girin")
        nameTextField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        
        // Gender section
        let genderSectionView = createSectionView(title: "Cinsiyet")
        contentView.addSubview(genderSectionView)
        
        genderLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        genderLabel.textColor = .white
        genderLabel.translatesAutoresizingMaskIntoConstraints = false
        genderSectionView.addSubview(genderLabel)
        
        changeGenderButton.setTitle("Değiştir", for: .normal)
        changeGenderButton.setTitleColor(UIColor(red: 0, green: 0.898, blue: 1, alpha: 1), for: .normal)
        changeGenderButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        changeGenderButton.addTarget(self, action: #selector(changeGenderTapped), for: .touchUpInside)
        changeGenderButton.translatesAutoresizingMaskIntoConstraints = false
        genderSectionView.addSubview(changeGenderButton)
        
        // Visibility section
        let visibilitySectionView = createSectionView(title: "Görünürlük")
        contentView.addSubview(visibilitySectionView)
        
        let visibilityLabel = UILabel()
        visibilityLabel.text = "Diğer kullanıcılar tarafından görülebilir"
        visibilityLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        visibilityLabel.textColor = .white
        visibilityLabel.numberOfLines = 0
        visibilityLabel.translatesAutoresizingMaskIntoConstraints = false
        visibilitySectionView.addSubview(visibilityLabel)
        
        visibilitySwitch.onTintColor = UIColor(red: 0, green: 0.898, blue: 1, alpha: 1)
        visibilitySwitch.addTarget(self, action: #selector(visibilityChanged), for: .valueChanged)
        visibilitySwitch.translatesAutoresizingMaskIntoConstraints = false
        visibilitySectionView.addSubview(visibilitySwitch)
        
        // User hash section
        let hashSectionView = createSectionView(title: "Kullanıcı ID")
        contentView.addSubview(hashSectionView)
        
        userHashLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        userHashLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        userHashLabel.numberOfLines = 0
        userHashLabel.translatesAutoresizingMaskIntoConstraints = false
        hashSectionView.addSubview(userHashLabel)
        
        // Layout
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            profileImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            profileImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            profileImageView.widthAnchor.constraint(equalToConstant: 120),
            profileImageView.heightAnchor.constraint(equalToConstant: 120),
            
            nameTextField.topAnchor.constraint(equalTo: profileImageView.bottomAnchor, constant: 32),
            nameTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            nameTextField.heightAnchor.constraint(equalToConstant: 50),
            
            genderSectionView.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: 32),
            genderSectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            genderSectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            genderLabel.leadingAnchor.constraint(equalTo: genderSectionView.leadingAnchor, constant: 16),
            genderLabel.centerYAnchor.constraint(equalTo: genderSectionView.centerYAnchor),
            
            changeGenderButton.trailingAnchor.constraint(equalTo: genderSectionView.trailingAnchor, constant: -16),
            changeGenderButton.centerYAnchor.constraint(equalTo: genderSectionView.centerYAnchor),
            
            visibilitySectionView.topAnchor.constraint(equalTo: genderSectionView.bottomAnchor, constant: 16),
            visibilitySectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            visibilitySectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            visibilityLabel.leadingAnchor.constraint(equalTo: visibilitySectionView.leadingAnchor, constant: 16),
            visibilityLabel.centerYAnchor.constraint(equalTo: visibilitySectionView.centerYAnchor),
            visibilityLabel.trailingAnchor.constraint(lessThanOrEqualTo: visibilitySwitch.leadingAnchor, constant: -16),
            
            visibilitySwitch.trailingAnchor.constraint(equalTo: visibilitySectionView.trailingAnchor, constant: -16),
            visibilitySwitch.centerYAnchor.constraint(equalTo: visibilitySectionView.centerYAnchor),
            
            hashSectionView.topAnchor.constraint(equalTo: visibilitySectionView.bottomAnchor, constant: 16),
            hashSectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hashSectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            hashSectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32),
            
            userHashLabel.topAnchor.constraint(equalTo: hashSectionView.topAnchor, constant: 16),
            userHashLabel.leadingAnchor.constraint(equalTo: hashSectionView.leadingAnchor, constant: 16),
            userHashLabel.trailingAnchor.constraint(equalTo: hashSectionView.trailingAnchor, constant: -16),
            userHashLabel.bottomAnchor.constraint(equalTo: hashSectionView.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupTextField(_ textField: UITextField, placeholder: String) {
        textField.placeholder = placeholder
        textField.backgroundColor = UIColor(red: 0.067, green: 0.094, blue: 0.125, alpha: 1)
        textField.textColor = .white
        textField.layer.cornerRadius = 12
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        textField.rightViewMode = .always
        textField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textField)
    }
    
    private func createSectionView(title: String) -> UIView {
        let sectionView = UIView()
        sectionView.backgroundColor = UIColor(red: 0.067, green: 0.094, blue: 0.125, alpha: 1)
        sectionView.layer.cornerRadius = 12
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            sectionView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            titleLabel.topAnchor.constraint(equalTo: sectionView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor, constant: 16)
        ])
        
        return sectionView
    }
    
    private func loadUserData() {
        let userPrefs = UserPreferences.shared
        
        nameTextField.text = userPrefs.userName
        
        if let gender = userPrefs.gender {
            genderLabel.text = "\(gender.icon) \(gender.displayName)"
        }
        
        visibilitySwitch.isOn = userPrefs.isVisibilityEnabled
        
        userHashLabel.text = "ID: \(userPrefs.userHash)\n\nBu ID diğer kullanıcıların sizi tanıması için kullanılır."
        
        // Set default profile image based on gender
        updateProfileImage()
    }
    
    private func updateProfileImage() {
        let gender = UserPreferences.shared.gender ?? .male
        let emoji = gender.icon
        
        // Create image with emoji
        let label = UILabel()
        label.text = emoji
        label.font = UIFont.systemFont(ofSize: 60)
        label.textAlignment = .center
        label.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
        
        UIGraphicsBeginImageContextWithOptions(label.bounds.size, false, 0)
        label.layer.render(in: UIGraphicsGetCurrentContext()!)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        profileImageView.image = image
    }
    
    @objc private func profileImageTapped() {
        // Could implement photo selection here
        let alert = UIAlertController(title: "Profil Fotoğrafı", message: "Şu anda sadece cinsiyet emojisi desteklenmektedir", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Tamam", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func nameChanged() {
        UserPreferences.shared.userName = nameTextField.text ?? ""
    }
    
    @objc private func changeGenderTapped() {
        let alert = UIAlertController(title: "Cinsiyet Seçin", message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "👨 Erkek", style: .default) { _ in
            UserPreferences.shared.gender = .male
            self.loadUserData()
        })
        
        alert.addAction(UIAlertAction(title: "👩 Kadın", style: .default) { _ in
            UserPreferences.shared.gender = .female
            self.loadUserData()
        })
        
        alert.addAction(UIAlertAction(title: "İptal", style: .cancel))
        
        // For iPad
        if let popover = alert.popoverPresentationController {
            popover.sourceView = changeGenderButton
            popover.sourceRect = changeGenderButton.bounds
        }
        
        present(alert, animated: true)
    }
    
    @objc private func visibilityChanged() {
        UserPreferences.shared.isVisibilityEnabled = visibilitySwitch.isOn
        
        if visibilitySwitch.isOn {
            BLEManager.shared.startAdvertising()
        } else {
            BLEManager.shared.stopAdvertising()
        }
    }
}
