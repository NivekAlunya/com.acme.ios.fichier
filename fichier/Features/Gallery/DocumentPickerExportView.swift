//
//  DocumentPickerExportView.swift
//  fichier
//

#if !os(tvOS)
import ObjectiveC
import UIKit

/// Presents `UIDocumentPickerViewController(forExporting:asCopy:)` directly from the topmost UIKit presenter.
///
/// Presenting `UIDocumentPickerViewController` directly avoids SwiftUI `.sheet` stacking conflicts and
/// double-modal presentation issues when exporting one or multiple downloaded files to the Files app.
@MainActor
final class DocumentPickerExportView: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    private static var coordinatorAssociationKey: UInt8 = 0

    private let onCompletion: @MainActor (Bool) -> Void
    private var didComplete = false

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
        let picker = UIDocumentPickerViewController(forExporting: existingURLs, asCopy: true)
        picker.delegate = coordinator
        picker.presentationController?.delegate = coordinator
        objc_setAssociatedObject(
            picker,
            &coordinatorAssociationKey,
            coordinator,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        complete(success: true, controller: controller)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        complete(success: false, controller: controller)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        complete(success: false, controller: presentationController.presentedViewController)
    }

    private func complete(success: Bool, controller: UIViewController) {
        guard !didComplete else { return }
        didComplete = true
        objc_setAssociatedObject(
            controller,
            &Self.coordinatorAssociationKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        onCompletion(success)
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
