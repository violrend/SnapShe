import SwiftUI

struct ProductCard: View {
    let product: Product
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image — tapping opens affiliate link
            AsyncImage(url: product.thumbnailURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .failure:
                    Color.snapsheGray.overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                default: Color.snapsheGray.shimmering()
                }
            }
            .frame(height: 170)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                // Price badge
                Text(product.price)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.snapsheBlack.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(8)
            }
            .contentShape(Rectangle())
            .onTapGesture { openAffiliate() }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.snapsheBlack)
                    .lineLimit(2)
                Text(product.source)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#999"))
                    .lineLimit(1)

                // Save button — separate from image tap
                Button(action: onSave) {
                    Text("Save")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.snapsheRed)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
                // Prevent tap from bubbling up to image gesture
                .simultaneousGesture(TapGesture().onEnded { _ in })
            }
            .padding(10)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.snapsheBlack.opacity(0.07), radius: 8, y: 2)
    }

    func openAffiliate() {
        if let url = APIService.affiliateURL(for: product.link) {
            UIApplication.shared.open(url)
        }
    }
}
