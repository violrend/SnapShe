import Foundation
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var currentUser: SnapUser? = nil
    @Published var token: String = ""
    @Published var isLoggedIn: Bool = false
    
    private init() {
        // Persist session with UserDefaults (simple token-based)
        if let savedToken = UserDefaults.standard.string(forKey: "snapshe_token"),
           let userData = UserDefaults.standard.data(forKey: "snapshe_user"),
           let user = try? JSONDecoder().decode(SnapUser.self, from: userData) {
            self.token = savedToken
            self.currentUser = user
            self.isLoggedIn = true
        }
    }
    
    func setUser(_ user: SnapUser, token: String) {
        self.currentUser = user
        self.token = token
        self.isLoggedIn = true
        UserDefaults.standard.set(token, forKey: "snapshe_token")
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "snapshe_user")
        }
    }
    
    func updateUser(_ user: SnapUser) {
        self.currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "snapshe_user")
        }
    }
    
    func logout() {
        currentUser = nil
        token = ""
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: "snapshe_token")
        UserDefaults.standard.removeObject(forKey: "snapshe_user")
    }
}
