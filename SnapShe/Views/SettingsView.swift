import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var username: String = ""
    @State private var isSaving = false
    @State private var notice = ""
    @State private var error = ""
    @State private var showDeleteConfirm = false
    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var isUploadingAvatar = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {

                    // Avatar section
                    VStack(spacing: 14) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarCircle(user: auth.currentUser, size: 90)
                                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                                .shadow(color: .black.opacity(0.1), radius: 8)

                            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                                ZStack {
                                    Circle().fill(Color.snapsheBlack).frame(width: 30, height: 30)
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                }
                            }
                            .disabled(isUploadingAvatar)
                        }

                        if isUploadingAvatar {
                            Text("Uploading…")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#888"))
                        }
                    }
                    .padding(.top, 8)

                    // Fields
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: "#888"))
                            SnapSheTextField(placeholder: "Your name", text: $name)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: "#888"))
                            SnapSheTextField(placeholder: "username", text: $username, icon: "at")
                        }
                    }

                    // Notice / Error
                    if !notice.isEmpty {
                        HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(notice).font(.system(size: 14)).foregroundStyle(.green) }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if !error.isEmpty { SnapSheErrorBox(message: error) }

                    // Save
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        ZStack {
                            if isSaving { ProgressView().tint(.white) }
                            else { Text("Save changes").font(.system(size: 16, weight: .bold)) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.snapsheBlack)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isSaving)

                    Divider()

                    // Account actions
                    VStack(spacing: 10) {
                        Button {
                            Task { await performLogout() }
                        } label: {
                            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color.snapsheGray)
                                .foregroundStyle(Color.snapsheBlack)
                                .clipShape(Capsule())
                        }

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete account", systemImage: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color.red.opacity(0.07))
                                .foregroundStyle(.red)
                                .clipShape(Capsule())
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .background(Color.white)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
        .onAppear {
            name = auth.currentUser?.name ?? ""
            username = auth.currentUser?.username ?? ""
        }
        .onChange(of: avatarPickerItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item: item) }
        }
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all your data. This cannot be undone.")
        }
    }

    func saveProfile() async {
        isSaving = true; notice = ""; error = ""
        do {
            let r = try await APIService.shared.updateProfile(name: name, username: username, token: auth.token)
            if r.ok {
                notice = "Profile saved."
                if var u = auth.currentUser {
                    u = SnapUser(id: u.id, name: name, username: username, email: u.email, avatar: u.avatar)
                    auth.updateUser(u)
                }
            } else { error = r.error ?? "Could not save." }
        } catch { self.error = "Network error." }
        isSaving = false
    }

    func uploadAvatar(item: PhotosPickerItem) async {
        isUploadingAvatar = true
        if let data = try? await item.loadTransferable(type: Data.self),
           let resized = UIImage(data: data)?.jpegData(compressionQuality: 0.75) {
            _ = try? await APIService.shared.uploadAvatar(imageData: resized, token: auth.token)
        }
        isUploadingAvatar = false
    }

    func performLogout() async {
        try? await APIService.shared.logout(token: auth.token)
        auth.logout(); dismiss()
    }

    func deleteAccount() async {
        _ = try? await APIService.shared.deleteAccount(token: auth.token)
        auth.logout(); dismiss()
    }
}
