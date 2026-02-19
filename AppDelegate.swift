import UIKit
import CoreBluetooth
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Initialize window
        window = UIWindow(frame: UIScreen.main.bounds)
        
        // Check if user has completed gender selection
        let userDefaults = UserDefaults.standard
        let hasCompletedGenderSelection = userDefaults.bool(forKey: "hasCompletedGenderSelection")
        
        let rootViewController: UIViewController
        
        if hasCompletedGenderSelection {
            // Show main app
            rootViewController = MainViewController()
        } else {
            // Show gender selection
            rootViewController = GenderSelectionViewController()
        }
        
        window?.rootViewController = rootViewController
        window?.makeKeyAndVisible()
        
        // Request notification permissions
        requestNotificationPermissions()
        
        return true
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permissions granted")
            } else {
                print("❌ Notification permissions denied")
            }
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Keep BLE scanning active in background
        BLEManager.shared.enterBackground()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Resume full BLE functionality
        BLEManager.shared.enterForeground()
    }
}
