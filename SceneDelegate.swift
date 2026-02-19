import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        print("🚀 SceneDelegate: Setting up window for iOS 13+")
        
        window = UIWindow(windowScene: windowScene)
        
        // Check if user has completed gender selection
        let hasCompletedGenderSelection = UserPreferences.shared.hasCompletedGenderSelection
        
        let rootViewController: UIViewController
        
        if hasCompletedGenderSelection {
            rootViewController = MainViewController()
            print("🚀 SceneDelegate: Showing Main App")
        } else {
            rootViewController = GenderSelectionViewController()
            print("🚀 SceneDelegate: Showing Gender Selection")
        }
        
        window?.rootViewController = rootViewController
        window?.makeKeyAndVisible()
        
        // Initialize BLE Manager
        _ = BLEManager.shared
        
        // Start scanning (always needed for message reception)
        BLEManager.shared.startScanning()
        
        // Start advertising if visibility is enabled
        if UserPreferences.shared.isVisibilityEnabled {
            BLEManager.shared.startAdvertising()
        }
        
        print("✅ SceneDelegate: Window setup complete")
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        print("🔌 Scene disconnected")
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        print("🔋 Scene became active")
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        print("⏸️ Scene will resign active")
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        BLEManager.shared.enterForeground()
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        BLEManager.shared.enterBackground()
    }
}
