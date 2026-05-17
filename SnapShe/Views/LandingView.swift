import SwiftUI

struct LandingView: View {
    @State private var showLogin = false
    @State private var showRegister = false
    @State private var collagePhotos: [URL] = []

    // Fallback Unsplash fashion photos (shown while loading or if server empty)
    let fallbackURLs = [
        "https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=400&q=80",
        "https://images.unsplash.com/photo-1469334031218-e382a71b716b?w=400&q=80",
        "https://images.unsplash.com/photo-1483985988355-763728e1935b?w=400&q=80",
        "https://images.unsplash.com/photo-1539109136881-3be0616acf4b?w=400&q=80",
        "https://images.unsplash.com/photo-1445205170230-053b83016050?w=400&q=80",
    ]

    var displayPhotos: [URL] {
        collagePhotos.isEmpty
            ? fallbackURLs.compactMap(URL.init)
            : collagePhotos
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── NAV ──────────────────────────────────────────
                    HStack {
                        SnapSheBrandView(size: 36)
                        Spacer()
                        HStack(spacing: 10) {
                            Button("Log in") { showLogin = true }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.snapsheBlack)
                            Button("Sign up") { showRegister = true }
                                .font(.system(size: 15, weight: .bold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Color.snapsheRed).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)

                    // ── HERO TEXT ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Visual fashion discovery")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.snapsheBlack.opacity(0.07)).clipShape(Capsule())

                        Text("Find the outfit\nyou love with\na photo or video.")
                            .font(.system(size: 40, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("SnapShe helps you search fashion visually. Upload a style photo or video , discover similar products, and save your favorite finds.")
                            .font(.system(size: 16)).foregroundStyle(Color(hex: "#555")).lineSpacing(3)

                        HStack(spacing: 12) {
                            Button { showRegister = true } label: {
                                Text("Join SnapShe for free")
                                    .font(.system(size: 16, weight: .bold))
                                    .padding(.horizontal, 22).padding(.vertical, 14)
                                    .background(Color.snapsheRed).foregroundStyle(.white).clipShape(Capsule())
                            }
                            Button("Log in") { showLogin = true }
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 22).padding(.vertical, 14)
                                .background(Color.snapsheGray).foregroundStyle(Color.snapsheBlack).clipShape(Capsule())
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)

                    // ── PHOTO COLLAGE ────────────────────────────────
                    LandingPhotoCollage(photos: Array(displayPhotos.prefix(5)))
                        .padding(.top, 28).padding(.bottom, 8)

                    // ── FEATURES ─────────────────────────────────────
                    VStack(spacing: 0) {
                        LandingFeatureRow(icon: "photo.on.rectangle.angled",
                            gradient: [Color.snapsheBlack, Color.snapshePurple],
                            title: "Search visually with images or video.",
                            description: "Upload a photo or video, crop the item you want, and explore similar fashion products instantly.")
                        Divider().padding(.horizontal, 20)
                        LandingFeatureRow(icon: "sparkles",
                            gradient: [Color.snapshePurple, Color.snapshePink],
                            title: "Discover inspiration first.",
                            description: "Your home feed shows recent uploads from the community. Tap any photoor video to shop the look.")
                        Divider().padding(.horizontal, 20)
                        LandingFeatureRow(icon: "heart.fill",
                            gradient: [Color.snapshePink, Color(hex: "#ff8c42")],
                            title: "Save your favorite finds.",
                            description: "Create collections to organize products you discover through visual search.")
                    }
                    .padding(.top, 32)

                    // ── INSTAGRAM LINK SEARCH ────────────────────────
                    InstagramSearchSection()
                        .padding(.top, 40)

                    // ── DISCOVER SECTION ──────────────────────────────
                    DiscoverPromoSection()
                        .padding(.top, 8)

                    // ── JOIN BAND ─────────────────────────────────────
                    VStack(spacing: 16) {
                        Text("Welcome to SnapShe")
                            .font(.system(size: 26, weight: .black)).foregroundStyle(Color.snapsheBlack)
                        Text("Sign up to unlock the visual fashion feed.")
                            .font(.system(size: 16)).foregroundStyle(Color(hex: "#666")).multilineTextAlignment(.center)
                        Button { showRegister = true } label: {
                            Text("Continue").font(.system(size: 17, weight: .bold))
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(Color.snapsheBlack).foregroundStyle(.white).clipShape(Capsule())
                        }
                        Button { showLogin = true } label: {
                            (Text("Already a member? ").foregroundStyle(Color(hex: "#888"))
                             + Text("Log in").foregroundStyle(Color.snapsheBlack).bold())
                                .font(.system(size: 15))
                        }
                    }
                    .padding(28)
                    .background(Color.snapsheGray)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 20).padding(.top, 40).padding(.bottom, 50)

                    VStack(spacing: 6) {
                        SnapSheBrandView(size: 28)
                        Text("Visual fashion search for outfits, style ideas, and similar products.")
                            .font(.system(size: 12)).foregroundStyle(Color(hex: "#aaa")).multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 32)
                }
            }
            .background(Color.white)
        }
        .task { await loadCollagePhotos() }
        .sheet(isPresented: $showLogin) { LoginView() }
        .sheet(isPresented: $showRegister) { RegisterView() }
    }

    func loadCollagePhotos() async {
        guard let url = URL(string: "\(APIService.baseURL)/api_mobile/public-feed.php") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONDecoder().decode(PublicFeedResponse.self, from: data),
              json.ok else { return }

        let base = APIService.baseURL
        collagePhotos = (json.photos ?? []).compactMap { p in
            guard let img = p.image, !img.isEmpty else { return nil }
            if img.hasPrefix("http") { return URL(string: img) }
            return URL(string: "\(base)/\(img)")
        }
    }
}

struct PublicFeedResponse: Codable {
    let ok: Bool
    let photos: [PublicFeedPhoto]?
}
struct PublicFeedPhoto: Codable {
    let image: String?
}

// MARK: - Photo Collage — matches site's stacked fashion grid
struct LandingPhotoCollage: View {
    let photos: [URL]

    // Positions matching site screenshot (staggered, overlapping, slight rotation)
    struct CardSpec {
        let w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, rot: Double, z: Double
    }
    let specs: [CardSpec] = [
        CardSpec(w: 138, h: 182, x: 8,   y: 0,   rot: -6.0, z: 1),
        CardSpec(w: 118, h: 158, x: 156, y: 30,  rot:  3.5, z: 3),
        CardSpec(w: 132, h: 172, x: 272, y: 4,   rot:  7.0, z: 2),
        CardSpec(w: 126, h: 166, x: 56,  y: 160, rot: -2.5, z: 4),
        CardSpec(w: 144, h: 176, x: 196, y: 148, rot:  5.0, z: 5),
    ]

    let fallbackGrads: [[Color]] = [
        [Color.snapsheBlack, Color.snapshePurple],
        [Color.snapshePurple, Color.snapshePink],
        [Color.snapshePink, Color(hex: "#ff8c42")],
        [Color(hex: "#2cb5ff"), Color.snapshePurple],
        [Color.snapsheBlack, Color.snapshePink],
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(5, max(photos.count, specs.count)), id: \.self) { i in
                let spec = specs[i]
                ZStack {
                    if i < photos.count {
                        AsyncImage(url: photos[i]) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            default:
                                gradientCard(i)
                            }
                        }
                    } else {
                        gradientCard(i)
                    }
                }
                .frame(width: spec.w, height: spec.h)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white, lineWidth: 2.5)
                )
                .rotationEffect(.degrees(spec.rot))
                .offset(x: spec.x, y: spec.y)
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
                .zIndex(spec.z)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 340)
        .padding(.leading, 6)
        .clipped()
    }

    @ViewBuilder
    func gradientCard(_ i: Int) -> some View {
        ZStack {
            LinearGradient(
                colors: fallbackGrads[i % fallbackGrads.count],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - Feature Row
struct LandingFeatureRow: View {
    let icon: String
    let gradient: [Color]
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.snapsheBlack)
                Text(description).font(.system(size: 14)).foregroundStyle(Color(hex: "#666")).lineSpacing(2)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 20)
    }
}

// MARK: - Instagram Link Search Section

struct InstagramSearchSection: View {
@State private var isAnimating = false
    let exampleLinks = [
        "instagram.com/p/ABC123...",
        "instagram.com/reel/XYZ789...",
        "instagram.com/p/fashion_post...",
    ]
    @State private var exampleIndex = 0
    @State private var placeholderText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        LinearGradient(
                            colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Image(systemName: "link")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Search from Instagram")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Paste any post or Reels link")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#888"))
                    }
                    Spacer()
                }

                Text("Copy a link from Instagram and paste it here — SnapShe finds similar fashion products from the photo or video automatically.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#666"))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)

            // Input card
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Instagram gradient icon
                    ZStack {
                        LinearGradient(
                            colors: [Color(hex: "#833ab4"), Color(hex: "#fd1d1d"), Color(hex: "#fcb045")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(placeholderText.isEmpty ? "instagram.com/p/..." : placeholderText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#bbb"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: "#e8e8e8"), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)

                // Search button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isAnimating = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isAnimating = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isAnimating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Text(isAnimating ? "Searching…" : "Find similar products")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#e0e0e0"), Color(hex: "#e0e0e0")],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(true)

                // How it works steps
                HStack(spacing: 0) {
                    ForEach(["Copy link", "Paste here", "Discover"], id: \.self) { step in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.snapshePurple.opacity(0.15))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Text(String(["Copy link", "Paste here", "Discover"].firstIndex(of: step)! + 1))
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(Color.snapshePurple)
                                )
                            Text(step)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: "#888"))
                        }
                        if step != "Discover" {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#ccc"))
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .onAppear { animatePlaceholder() }
    }

    func animatePlaceholder() {
        let target = exampleLinks[exampleIndex]
        placeholderText = ""
        var charIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if charIndex < target.count {
                let idx = target.index(target.startIndex, offsetBy: charIndex)
                placeholderText += String(target[idx])
                charIndex += 1
            } else {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { placeholderText = "" }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        exampleIndex = (exampleIndex + 1) % exampleLinks.count
                        animatePlaceholder()
                    }
                }
            }
        }
    }
}

// MARK: - Discover Promo Section

struct DiscoverPromoSection: View {
    @State private var activeCard = 0
    let timer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    let cards: [(icon: String, color: Color, title: String, sub: String)] = [
        ("play.rectangle.fill", Color.snapshePurple, "Street style", "@fashionista"),
        ("video.fill", Color.snapshePink, "Summer looks", "@styleinspo"),
        ("camera.fill", Color.snapsheBlack, "Minimal outfits", "@minimalmode"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header badge
            HStack(spacing: 8) {
                ZStack {
                    LinearGradient(
                        colors: [Color.snapshePurple, Color.snapshePink],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Discover")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("NEW")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.snapshePurple)
                            .clipShape(Capsule())
                    }
                    Text("Swipe through fashion snaps")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#888"))
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            // Description
            Text("A full-screen vertical feed of fashion photos and videos from the community. Swipe up to explore, tap to find similar products instantly.")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#666"))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // Mock phone preview
            ZStack {
                // Phone frame
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.snapsheBlack)
                    .frame(width: 180, height: 300)
                    .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)

                // Screen
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 168, height: 288)
                    .overlay(
                        ZStack(alignment: .bottom) {
                            // Animated card background
                            ForEach(0..<cards.count, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [cards[i].color.opacity(0.7), Color.black],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                    .opacity(activeCard == i ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.5), value: activeCard)
                            }

                            // Content overlay
                            VStack(alignment: .leading, spacing: 6) {
                                // User row
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(cards[activeCard].color)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Image(systemName: cards[activeCard].icon)
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(cards[activeCard].title)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                        Text(cards[activeCard].sub)
                                            .font(.system(size: 8))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                    Spacer()
                                }

                                // Find similar button (mini)
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Find similar products")
                                        .font(.system(size: 8, weight: .black))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 7, weight: .bold))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .padding(12)

                            // Discover label top
                            VStack {
                                Text("Discover")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.top, 14)
                                Spacer()
                            }

                            // Swipe indicator
                            VStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    ForEach(0..<cards.count, id: \.self) { i in
                                        Capsule()
                                            .fill(Color.white.opacity(activeCard == i ? 1 : 0.3))
                                            .frame(width: activeCard == i ? 16 : 4, height: 4)
                                            .animation(.spring(response: 0.3), value: activeCard)
                                    }
                                }
                                .padding(.bottom, 50)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    )

                // Notch
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.snapsheBlack)
                    .frame(width: 52, height: 14)
                    .offset(y: -143)

                // Home bar
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 50, height: 3)
                    .offset(y: 138)
            }
            .padding(.top, 28)
            .frame(maxWidth: .infinity)
            .onReceive(timer) { _ in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    activeCard = (activeCard + 1) % cards.count
                }
            }

            // Feature pills
            HStack(spacing: 8) {
                ForEach(["Auto-play videos", "Swipe to browse", "Instant search"], id: \.self) { pill in
                    Text(pill)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.snapshePurple)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.snapshePurple.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }
}
