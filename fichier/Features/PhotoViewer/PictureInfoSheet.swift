//
//  PictureInfoSheet.swift
//  fichier
//

import SwiftUI

struct PictureInfoSheet: View {
    let metadata: PictureEXIFData
    let item: SMBItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("File Details") {
                    LabeledContent("Name", value: metadata.fileName)
                    LabeledContent("Size", value: metadata.fileSize)
                    if let fmt = metadata.fileFormat {
                        LabeledContent("Format", value: fmt)
                    }
                    if let dim = metadata.dimensions {
                        LabeledContent("Dimensions", value: dim)
                    }
                    if let mp = metadata.megapixels {
                        LabeledContent("Resolution", value: mp)
                    }
                    if let date = metadata.dateTaken {
                        LabeledContent("Date Taken", value: date)
                    }
                }
                
                if metadata.cameraModel != nil || metadata.lensModel != nil {
                    Section("Camera & Lens") {
                        if let cam = metadata.cameraModel {
                            LabeledContent("Camera", value: cam)
                        }
                        if let lens = metadata.lensModel {
                            LabeledContent("Lens", value: lens)
                        }
                    }
                }
                
                if metadata.aperture != nil || metadata.shutterSpeed != nil || metadata.iso != nil || metadata.focalLength != nil {
                    Section("Exposure Settings") {
                        if let ap = metadata.aperture {
                            LabeledContent("Aperture", value: ap)
                        }
                        if let shutter = metadata.shutterSpeed {
                            LabeledContent("Shutter Speed", value: shutter)
                        }
                        if let iso = metadata.iso {
                            LabeledContent("ISO", value: iso)
                        }
                        if let fl = metadata.focalLength {
                            LabeledContent("Focal Length", value: fl)
                        }
                    }
                }
            }
            .navigationTitle("Photo Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
