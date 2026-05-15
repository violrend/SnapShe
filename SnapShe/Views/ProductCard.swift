import SwiftUI

struct ProductCard: View {
    let product: Product
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Görsel — sabit yükseklik, taşma yok
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: product.thumbnailURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(height: 160)
                            .clipped()
                    case .failure:
                        Color.snapsheGray
                            .frame(height: 160)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    default:
                        Color.snapsheGray.frame(height: 160).shimmering()
                    }
                }
                .frame(height: 160)
                .clipped()

                // Fiyat badge
                if !product.price.isEmpty {
                    Text(product.price)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.snapsheBlack.opacity(0.82))
                        .clipShape(Capsule())
                        .padding(7)
                }
            }
            .frame(height: 160)
            .contentShape(Rectangle())
            .onTapGesture { openAffiliate() }

            // Başlık + kaydet
            VStack(alignment: .leading, spacing: 4) {
                Text(product.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.snapsheBlack)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(product.source)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#999"))
                    .lineLimit(1)

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
