import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    @State private var loginField = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    // Brand
                    VStack(spacing: 12) {
                        SnapSheBrandView(size: 44)
                            .padding(.top, 8)
                        Text("Welcome to SnapShe")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Log in to discover visual fashion inspiration\nand save your favorite finds.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "#666"))
                            .multilineTextAlignment(.center)
                    }

                    // Form
                    VStack(spacing: 12) {
                        if !errorMessage.isEmpty { SnapSheErrorBox(message: errorMessage) }

                        SnapSheTextField(placeholder: "Username or email", text: $loginField, icon: "person")
                        SnapSheTextField(placeholder: "Password", text: $password, isSecure: true)

                        Button {
                            Task { await performLogin() }
                        } label: {
                            ZStack {
                                if isLoading { ProgressView().tint(.white) }
                                else { Text("Log in").font(.system(size: 17, weight: .bold)) }
                            }
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color.snapsheBlack)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .disabled(isLoading || loginField.isEmpty || password.isEmpty)
                    }

                    // Switch to register
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showRegister = true }
                    } label: {
                        (Text("Not on SnapShe yet? ").foregroundStyle(Color(hex: "#888"))
                         + Text("Sign up").foregroundStyle(Color.snapsheBlack).bold())
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
                            .font(.system(size: 22))
                            .foregroundStyle(Color(hex: "#ccc"))
                    }
                }
            }
        }
        .sheet(isPresented: $showRegister) { RegisterView() }
    }

    func performLogin() async {
        isLoading = true; errorMessage = ""
        do {
            let r = try await APIService.shared.login(login: loginField, password: password)
            if r.ok, let user = r.user, let token = r.token {
                auth.setUser(user, token: token); dismiss()
            } else { errorMessage = r.error ?? "Invalid username or password." }
        } catch { errorMessage = "Network error. Please try again." }
        isLoading = false
    }
}
