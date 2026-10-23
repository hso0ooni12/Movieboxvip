import SwiftUI
import UIKit

struct XSCinemaImage: View {
    let url: URL
    var maxDimension: Int = 500
    @State private var bitmap: UIImage?
    var body: some View {
        ZStack {
            if let bitmap {
                Image(uiImage: bitmap).resizable().scaledToFill()
            } else {
                Image(systemName: "film.stack").font(.system(size: 26, weight: .thin))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .task(id: url) {
            bitmap = nil
            let result = await XSArtworkPipeline.shared.image(for: url, maxDimension: maxDimension)
            guard !Task.isCancelled else { return }
            bitmap = result
        }
    }
}
