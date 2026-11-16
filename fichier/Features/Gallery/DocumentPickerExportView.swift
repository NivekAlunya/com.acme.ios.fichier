//
//  DocumentPickerExportView.swift
//  fichier
//
//

#if !os(tvOS)
import SwiftUI
import UIKit

/// UIViewControllerRepresentable wrapping `UIDocumentPickerViewController` for exporting files into the iOS Files app.
struct DocumentPickerExportView: UIViewControllerRepresentable {
    /// Local file URLs to be copied into the user-selected destination directory.
    let urls: [URL]
    
    /// Callback invoked when the user finishes picking a destination or dismisses the picker.
    var onCompletion: ((Bool) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: ((Bool) -> Void)?
        
        init(onCompletion: ((Bool) -> Void)?) {
            self.onCompletion = onCompletion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion?(true)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCompletion?(false)
        }
    }
}
#endif
