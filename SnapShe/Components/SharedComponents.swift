import SwiftUI

// MARK: - Design Tokens
extension Color {
    static let snapsheBlack  = Color(hex: "#111111")
    static let snapshePurple = Color(hex: "#7b2cff")
    static let snapshePink   = Color(hex: "#ff5b92")
    static let snapsheRed    = Color(hex: "#e60023")
    static let snapsheGray   = Color(hex: "#efefef")
    static let snapsheBorder = Color(hex: "#e8e8e8")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6: (a,r,g,b) = (255,int>>16,int>>8 & 0xFF,int & 0xFF)
        case 8: (a,r,g,b) = (int>>24,int>>16 & 0xFF,int>>8 & 0xFF,int & 0xFF)
        default:(a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

let snapsheGradient = LinearGradient(
    colors: [Color.snapsheBlack, Color.snapshePurple, Color.snapshePink],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

// MARK: - Brand Logo  (V icon + SnapShe text)
struct SnapSheBrandView: View {
    var size: CGFloat = 36
    var showText: Bool = true

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                snapsheGradient
                Text("V")
                    .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))

            if showText {
                Text("SnapShe")
                    .font(.system(size: size * 0.58, weight: .black, design: .rounded))
                    .foregroundStyle(Color.snapsheBlack)
            }
        }
    }
}

// MARK: - Primary Button
struct SnapShePrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                else {
                    HStack(spacing: 8) {
                        if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                        Text(title).font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color.snapsheBlack).foregroundStyle(.white).clipShape(Capsule())
        }
        .disabled(isLoading)
    }
}

// MARK: - Red Button
struct SnapSheRedButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                else { Text(title).font(.system(size: 15, weight: .bold)) }
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(Color.snapsheRed).foregroundStyle(.white).clipShape(Capsule())
        }
    }
}

// MARK: - Ghost Button
struct SnapSheGhostButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.snapsheGray).foregroundStyle(Color.snapsheBlack).clipShape(Capsule())
        }
    }
}

// MARK: - Pill Button
struct SnapShePillButton: View {
    let title: String
    var isRed: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(isRed ? Color.snapsheRed : Color.snapsheGray)
                .foregroundStyle(isRed ? .white : Color.snapsheBlack)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Text Field
struct SnapSheTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 15))
                    .foregroundStyle(Color(hex: "#999")).frame(width: 18)
            }
            Group {
                if isSecure { SecureField(placeholder, text: $text) }
                else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType).autocapitalization(.none).disableAutocorrection(true)
                }
            }
            .font(.system(size: 16))
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .background(Color.snapsheGray)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Profile Chip
struct SnapSheProfileChip: View {
    let user: SnapUser?
    var body: some View {
        HStack(spacing: 8) {
            AvatarCircle(user: user, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(user?.displayName ?? "").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.snapsheBlack).lineLimit(1)
                Text("@\(user?.username ?? "")").font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#666")).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.snapsheGray).clipShape(Capsule())
    }
}

// MARK: - Search Pill
struct SnapSheSearchPill: View {
    @Binding var text: String
    var placeholder: String = "Search users..."
    var onCameraTab: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(Color(hex: "#555"))
            TextField(placeholder, text: $text).font(.system(size: 17))
                .autocapitalization(.none).disableAutocorrection(true)
            if let onCameraTab {
                Button(action: onCameraTab) {
                    ZStack {
                        Circle().fill(Color.snapsheBlack).frame(width: 34, height: 34)
                        Image(systemName: "viewfinder.circle.fill").font(.system(size: 20)).foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.snapsheGray).clipShape(Capsule())
    }
}

// MARK: - Error Box
struct SnapSheErrorBox: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(message).font(.system(size: 14)).foregroundStyle(.red)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Avatar Circle
struct AvatarCircle: View {
    let user: SnapUser?
    var size: CGFloat = 40
    var body: some View {
        ZStack {
            if let url = user?.avatarURL {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { gradientFallback }
                }
            } else { gradientFallback }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
    var gradientFallback: some View {
        ZStack {
            snapsheGradient
            Text(user?.avatarLetter ?? "?")
                .font(.system(size: size * 0.42, weight: .black)).foregroundStyle(.white)
        }
    }
}

// AvatarView alias for compatibility
typealias AvatarView = AvatarCircleCompat
struct AvatarCircleCompat: View {
    let user: SnapUser?
    let size: CGFloat
    var body: some View { AvatarCircle(user: user, size: size) }
}

// MARK: - Shimmer
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content.overlay(
            LinearGradient(stops: [
                .init(color: .clear, location: phase - 0.3),
                .init(color: .white.opacity(0.35), location: phase),
                .init(color: .clear, location: phase + 0.3),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .animation(.linear(duration: 1.3).repeatForever(autoreverses: false), value: phase)
        )
        .onAppear { phase = 1.6 }
    }
}
extension View {
    func shimmering() -> some View { modifier(ShimmerModifier()) }
}
