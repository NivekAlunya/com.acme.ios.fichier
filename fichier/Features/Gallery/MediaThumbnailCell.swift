//
//  MediaThumbnailCell.swift
//  fichier
//

import SwiftUI

struct MediaThumbnailCell: View {
    var manager: SMBDirectManager
    let item: SMBItem
    var maxDimension: CGFloat = 260
    @State private var image: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Color(.secondarySystemBackground)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    ProgressView()
                }
                
                if item.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                        Text("VIDEO")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(6)
                }
                
                if FavoritesManager.shared.isFavorite(item) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .padding(5)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(item.formattedSize)
                if let d = item.formattedDate {
                    Text("•")
                    Text(d)
                }
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .task(id: item.id) {
            self.image = await manager.downloadThumbnail(for: item, maxDimension: maxDimension)
        }
    }
}
