import SwiftUI

// MARK: - Instagram Fetch Result

enum InstagramFetchResult {
    case image(url: String)
    case video(url: String)
}

// MARK: - InstagramFetchView

struct InstagramFetchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthManager

    var onResult: (InstagramFetchResult) -> Void

    @State private var urlText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // Handle bar
            Capsule()
                .fill(Color(hex: "#DDDDDD"))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#d62976"), Color(hex: "#962fbf")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Search from Instagram")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.snapsheBlack)
                    Text("Paste a post or Reels link")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#888"))
                }
                Spacer()

                Button { dismiss() } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F0F0F0"))
                            .frame(width: 30, height: 30)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#666"))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // URL Input
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#999"))

                    TextField("https://www.instagram.com/reel/...", text: $urlText)
                        .font(.system(size: 15))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($inputFocused)
                        .submitLabel(.go)
                        .onSubmit { Task { await fetchInstagram() } }

                    if !urlText.isEmpty {
                        Button { urlText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(hex: "#CCC"))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color(hex: "#F5F5F5"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Task { await fetchInstagram() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.snapsheBlack)
                            .frame(width: 56, height: 50)
                        if isLoading {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(isLoading || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)

            // Error message
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(err)
                        .font(.system(size: 13))
                }
                .foregroundStyle(Color(hex: "#E53935"))
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Paste from clipboard button
            if UIPasteboard.general.hasStrings {
                Button {
                    if let str = UIPasteboard.general.string {
                        urlText = str
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12))
                        Text("Paste from clipboard")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "#555"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#F0F0F0"))
                    .clipShape(Capsule())
                }
                .padding(.top, 12)
            }

            Spacer(minLength: 20)

            // Note
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#AAAAAA"))
                Text("Only public Instagram accounts are supported.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#AAAAAA"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .onAppear { inputFocused = true }
    }

    // MARK: - Fetch

    private func fetchInstagram() async {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        guard url.lowercased().contains("instagram.com") else {
            errorMessage = "Please enter a valid Instagram URL."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await APIService.shared.instagramFetch(url: url, token: auth.token)
            dismiss()

            if result.type == "video", let videoUrl = result.videoUrl {
                onResult(.video(url: videoUrl))
            } else if let imageUrl = result.imageUrl {
                onResult(.image(url: imageUrl))
            } else {
                errorMessage = "Could not retrieve media. Please try again."
            }
        } catch {
            errorMessage = (error as? InstagramFetchError)?.message ?? "Connection error. Please try again."
        }

        isLoading = false
    }
}
