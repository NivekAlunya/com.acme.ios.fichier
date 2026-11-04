//
//  PictureInfoSheet.swift
//  fichier
//

import SwiftUI

/// Modal bottom sheet presenting detailed EXIF camera settings, optical metadata, and file attributes.
///
/// Organized into distinct grouped sections:
/// - **File Details**: File name, file size, codec format, pixel dimensions, megapixels, and timestamp.
/// - **Camera & Lens**: Body manufacturer/model and attached lens model.
/// - **Exposure Settings**: Lens aperture, shutter speed, sensor ISO, and focal length.
struct PictureInfoSheet: View {
    /// Parsed EXIF metadata object being inspected.
    let metadata: PictureEXIFData
    
    /// Target media item reference.
    let item: MediaItem
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section(.Strings.photoInfoSectionFileDetails) {
                    LabeledContent(.Strings.photoInfoLabelName, value: metadata.fileName)
                    LabeledContent(.Strings.photoInfoLabelSize, value: metadata.fileSize)
                    if let fmt = metadata.fileFormat {
                        LabeledContent(.Strings.photoInfoLabelFormat, value: fmt)
                    }
                    if let dim = metadata.dimensions {
                        LabeledContent(.Strings.photoInfoLabelDimensions, value: dim)
                    }
                    if let mp = metadata.megapixels {
                        LabeledContent(.Strings.photoInfoLabelResolution, value: mp)
                    }
                    if let date = metadata.dateTaken {
                        LabeledContent(.Strings.photoInfoLabelDateTaken, value: date)
                    }
                }
                
                if metadata.cameraModel != nil || metadata.lensModel != nil {
                    Section(.Strings.photoInfoSectionCameraLens) {
                        if let cam = metadata.cameraModel {
                            LabeledContent(.Strings.photoInfoLabelCamera, value: cam)
                        }
                        if let lens = metadata.lensModel {
                            LabeledContent(.Strings.photoInfoLabelLens, value: lens)
                        }
                    }
                }
                
                if metadata.aperture != nil || metadata.shutterSpeed != nil || metadata.iso != nil || metadata.focalLength != nil {
                    Section(.Strings.photoInfoSectionExposureSettings) {
                        if let ap = metadata.aperture {
                            LabeledContent(.Strings.photoInfoLabelAperture, value: ap)
                        }
                        if let shutter = metadata.shutterSpeed {
                            LabeledContent(.Strings.photoInfoLabelShutterSpeed, value: shutter)
                        }
                        if let iso = metadata.iso {
                            LabeledContent(.Strings.photoInfoLabelIso, value: iso)
                        }
                        if let fl = metadata.focalLength {
                            LabeledContent(.Strings.photoInfoLabelFocalLength, value: fl)
                        }
                    }
                }
            }
            .navigationTitle(.Strings.photoInfoTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.Strings.commonDone) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
