import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    VStack(spacing: 12) {
                        SnapSheBrandView(size: 44).padding(.top, 8)
                        Text("Create account")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Sign up to unlock the visual fashion feed.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "#666"))
                    }

                    VStack(spacing: 12) {
                        if !errorMessage.isEmpty { SnapSheErrorBox(message: errorMessage) }
                        SnapSheTextField(placeholder: "Name", text: $name, icon: "person")
                        SnapSheTextField(placeholder: "Username", text: $username, icon: "at")
                        SnapSheTextField(placeholder: "Email", text: $email, icon: "envelope", keyboardType: .emailAddress)
                        SnapSheTextField(placeholder: "Password", text: $password, isSecure: true)

                        Button {
                            Task { await performRegister() }
                        } label: {
                            ZStack {
                                if isLoading { ProgressView().tint(.white) }
                                else { Text("Continue").font(.system(size: 17, weight: .bold)) }
                            }
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color.snapsheBlack)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .disabled(isLoading || name.isEmpty || username.isEmpty || email.isEmpty || password.count < 6)
                    }

                    Button { dismiss() } label: {
                        (Text("Already a member? ").foregroundStyle(Color(hex: "#888"))
                         + Text("Log in").foregroundStyle(Color.snapsheBlack).bold())
                            .font(.system(size: 15))
                    }
                }
                .padding(24)
            }
            .background(Color.white)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(Color(hex: "#ccc"))
                    }
                }
            }
        }
    }

    func performRegister() async {
        isLoading = true; errorMessage = ""
        do {
            let r = try await APIService.shared.register(name: name, username: username, email: email, password: password)
            if r.ok, let user = r.user, let token = r.token {
                auth.setUser(user, token: token); dismiss()
            } else { errorMessage = r.error ?? "Registration failed." }
        } catch { errorMessage = "Network error. Please try again." }
        isLoading = false
    }
}
