import AsaCore
import SwiftUI

/// The cover of a book, with the shape of a paperback and a soft shadow.
struct CoverView: View {
    let url: URL
    var title: String = ""
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Palette.surfaceHigh)
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(title)
                        .font(Karla.font(12, .bold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner - 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner - 4, style: .continuous).stroke(Palette.outline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .task(id: url) { image = await PageImages.shared.image(url, maxPixels: 600) }
            .accessibilityHidden(true)
    }
}

/// A thin bar that shows the part of a book that the user read.
struct ProgressLine: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.outline)
                Capsule().fill(Palette.accent).frame(width: proxy.size.width * value)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }
}
