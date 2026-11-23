//
//  DocumentPickerExportView.swift
//  fichier
//

#if !os(tvOS)
import UIKit

/// Presents `UIDocumentPickerViewController(forExporting:asCopy:)` directly from the topmost UIKit presenter.
///
/// Presenting `UIDocumentPickerViewController` directly avoids SwiftUI `.sheet` stacking conflicts and
/// double-modal presentation issues when exporting one or multiple downloaded files to the Files app.
@MainActor
final class DocumentPickerExportView: NSObject, UIDocumentPickerDelegate {
    private static var activePresenter: DocumentPickerExportView?

    private let onCompletion: @MainActor (Bool) -> Void

    private init(onCompletion: @escaping @MainActor (Bool) -> Void) {
        self.onCompletion = onCompletion
    }

    /// Presents the system Files export picker for the given local file URLs.
    static func present(urls: [URL], onCompletion: @escaping @MainActor (Bool) -> Void) {
        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty, let presenter = topMostViewController() else {
            onCompletion(false)
            return
        }

        let coordinator = DocumentPickerExportView(onCompletion: onCompletion)
        activePresenter = coordinator

        let picker = UIDocumentPickerViewController(forExporting: existingURLs, asCopy: true)
        picker.delegate = coordinator
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Self.activePresenter = nil
        onCompletion(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Self.activePresenter = nil
        onCompletion(false)
    }

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        let root = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
            ?? scenes.flatMap(\.windows).first?.rootViewController

        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}
#endif
