//
//  MediaListRowCell.swift
//  fichier
//

import SwiftUI

struct MediaListRowCell: View {
    var manager: SMBDirectManager
    let item: SMBItem
    @State private var thumbnail: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 52, height: 52)
                
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                
                if item.isVideo {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Circle())
                        .padding(2)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(1)
                    if FavoritesManager.shared.isFavorite(item) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                    if let dateStr = item.formattedDate {
                        Text("•")
                        Text(dateStr)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .task(id: item.id) {
            self.thumbnail = await manager.downloadThumbnail(for: item, maxDimension: 140)
        }
    }
}
