import Foundation
import AgentKit
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class TalkifyUserAssetPicker {
    private let fileStore: ManagedUserAssetFileStore
    private let normalizer: UserImageNormalizer
    private let accountScope: @Sendable () -> String
    #if os(iOS)
    private var coordinator: IOSPickerCoordinator?
    private var documentCoordinator: IOSDocumentPickerCoordinator?
    private var cameraCoordinator: IOSCameraCoordinator?
    #endif

    init(
        fileStore: ManagedUserAssetFileStore,
        normalizer: UserImageNormalizer,
        accountScope: @escaping @Sendable () -> String
    ) {
        self.fileStore = fileStore
        self.normalizer = normalizer
        self.accountScope = accountScope
    }

    func pick() async throws -> [DraftAttachmentReference] {
        #if os(iOS)
        let attachments = try await pickOnIOS()
        #elseif os(macOS)
        let attachments = try pickOnMacOS()
        #else
        let attachments: [DraftAttachmentReference] = []
        #endif
        return try await preflight(attachments)
    }

    private func preflight(
        _ attachments: [DraftAttachmentReference]
    ) async throws -> [DraftAttachmentReference] {
        let normalizer = normalizer
        let images = try await Task.detached(priority: .userInitiated) {
            var normalizedImages: [NormalizedUserImage] = []
            for attachment in attachments {
                guard let url = URL(string: attachment.resourceURI), url.isFileURL else {
                    throw ManagedUserAssetFileError.invalidResource
                }
                let type = try TalkifyLocalAssetPolicy.type(for: url)
                if type.conforms(to: .image) {
                    normalizedImages.append(try normalizer.normalize(
                        sourceURL: url,
                        attachmentID: attachment.id,
                        preferredFilename: attachment.displayName
                    ))
                } else {
                    _ = try TalkifyLocalAssetPolicy.validateDocument(at: url, type: type)
                }
            }
            return normalizedImages
        }.value
        try UserImageNormalizer.validateCombinedSize(images)
        return attachments
    }

    #if os(iOS)
    private func pickOnIOS() async throws -> [DraftAttachmentReference] {
        let source = await chooseIOSSource()
        guard source != .cancel else { return [] }
        // Let the action sheet finish its dismissal before presenting the next
        // controller; presenting from the disappearing alert is unreliable on iPad.
        try? await Task.sleep(for: .milliseconds(200))
        switch source {
        case .photos:
            return try await pickPhotosOnIOS()
        case .files:
            return try await pickDocumentsOnIOS()
        case .camera:
            return try await pickCameraOnIOS()
        case .cancel:
            return []
        }
    }

    private func chooseIOSSource() async -> IOSPickerSource {
        guard let presenter = Self.presentingViewController() else { return .cancel }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: TalkifyLocalized.string("userassets.add_attachment"),
                message: nil,
                preferredStyle: .actionSheet
            )
            #if os(iOS)
            alert.addAction(UIAlertAction(title: TalkifyLocalized.string("userassets.take_photo"), style: .default) { _ in
                continuation.resume(returning: .camera)
            })
            #endif
            alert.addAction(UIAlertAction(title: TalkifyLocalized.string("userassets.photos"), style: .default) { _ in
                continuation.resume(returning: .photos)
            })
            alert.addAction(UIAlertAction(title: TalkifyLocalized.string("userassets.pdf_or_document"), style: .default) { _ in
                continuation.resume(returning: .files)
            })
            alert.addAction(UIAlertAction(title: TalkifyLocalized.string("common.action.cancel"), style: .cancel) { _ in
                continuation.resume(returning: .cancel)
            })
            if let popover = alert.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.maxY,
                    width: 1,
                    height: 1
                )
            }
            presenter.present(alert, animated: true)
        }
    }

    private func pickPhotosOnIOS() async throws -> [DraftAttachmentReference] {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 4
        configuration.selection = .ordered

        let picker = PHPickerViewController(configuration: configuration)
        let coordinator = IOSPickerCoordinator(
            fileStore: fileStore,
            accountScope: accountScope()
        )
        self.coordinator = coordinator
        picker.delegate = coordinator

        guard let presenter = Self.presentingViewController() else {
            self.coordinator = nil
            throw ManagedUserAssetFileError.unavailable
        }
        presenter.present(picker, animated: true)
        defer { self.coordinator = nil }
        return try await coordinator.result()
    }

    private func pickDocumentsOnIOS() async throws -> [DraftAttachmentReference] {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: TalkifyLocalAssetPolicy.pickerContentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        let coordinator = IOSDocumentPickerCoordinator(
            fileStore: fileStore,
            accountScope: accountScope()
        )
        documentCoordinator = coordinator
        picker.delegate = coordinator
        guard let presenter = Self.presentingViewController() else {
            documentCoordinator = nil
            throw ManagedUserAssetFileError.unavailable
        }
        presenter.present(picker, animated: true)
        defer { documentCoordinator = nil }
        return try await coordinator.result()
    }

    private func pickCameraOnIOS() async throws -> [DraftAttachmentReference] {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return []
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        let coordinator = IOSCameraCoordinator(
            fileStore: fileStore,
            accountScope: accountScope()
        )
        cameraCoordinator = coordinator
        picker.delegate = coordinator
        guard let presenter = Self.presentingViewController() else {
            cameraCoordinator = nil
            throw ManagedUserAssetFileError.unavailable
        }
        presenter.present(picker, animated: true)
        defer { cameraCoordinator = nil }
        return try await coordinator.result()
    }

    private static func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var controller = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
    #endif

    #if os(macOS)
    private func pickOnMacOS() throws -> [DraftAttachmentReference] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = TalkifyLocalAssetPolicy.pickerContentTypes
        panel.message = String(localized: "user-assets.picker.message")
        guard panel.runModal() == .OK else { return [] }

        let scope = accountScope()
        return try panel.urls.prefix(4).map { url in
            let id = UUID().uuidString.lowercased()
            let managed = try fileStore.importFile(from: url, attachmentID: id, accountScope: scope)
            return DraftAttachmentReference(
                id: id,
                displayName: UserImageNormalizer.safeFilename(url.lastPathComponent, mimeType: nil),
                resourceURI: managed.absoluteString
            )
        }
    }
    #endif
}

#if os(iOS)
private enum IOSPickerSource: Equatable {
    case camera
    case photos
    case files
    case cancel
}

@MainActor
private final class IOSPickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    private let fileStore: ManagedUserAssetFileStore
    private let accountScope: String
    private var continuation: CheckedContinuation<[PHPickerResult], Never>?
    private var bufferedResults: [PHPickerResult]?

    init(fileStore: ManagedUserAssetFileStore, accountScope: String) {
        self.fileStore = fileStore
        self.accountScope = accountScope
    }

    func result() async throws -> [DraftAttachmentReference] {
        let results: [PHPickerResult] = await withCheckedContinuation { continuation in
            if let bufferedResults {
                continuation.resume(returning: bufferedResults)
                self.bufferedResults = nil
            } else {
                self.continuation = continuation
            }
        }
        var attachments: [DraftAttachmentReference] = []
        for result in results.prefix(4) {
            let id = UUID().uuidString.lowercased()
            let name = result.itemProvider.suggestedName ?? "image"
            let managedURL = try await importProvider(result.itemProvider, attachmentID: id)
            attachments.append(DraftAttachmentReference(
                id: id,
                displayName: UserImageNormalizer.safeFilename(name, mimeType: nil),
                resourceURI: managedURL.absoluteString
            ))
        }
        return attachments
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: results)
        } else {
            bufferedResults = results
        }
    }

    private func importProvider(_ provider: NSItemProvider, attachmentID: String) async throws -> URL {
        let type = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) ?? UTType.image.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { [fileStore, accountScope] url, error in
                guard error == nil, let url else {
                    continuation.resume(throwing: ManagedUserAssetFileError.unavailable)
                    return
                }
                do {
                    let copied = try fileStore.importFile(
                        from: url,
                        attachmentID: attachmentID,
                        accountScope: accountScope
                    )
                    continuation.resume(returning: copied)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
private final class IOSDocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private let fileStore: ManagedUserAssetFileStore
    private let accountScope: String
    private var continuation: CheckedContinuation<[URL], Never>?
    private var bufferedURLs: [URL]?

    init(fileStore: ManagedUserAssetFileStore, accountScope: String) {
        self.fileStore = fileStore
        self.accountScope = accountScope
    }

    func result() async throws -> [DraftAttachmentReference] {
        let urls = await withCheckedContinuation { continuation in
            if let bufferedURLs {
                continuation.resume(returning: bufferedURLs)
                self.bufferedURLs = nil
            } else {
                self.continuation = continuation
            }
        }
        return try urls.prefix(4).map { url in
            let id = UUID().uuidString.lowercased()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }
            let managed = try fileStore.importFile(
                from: url,
                attachmentID: id,
                accountScope: accountScope
            )
            return DraftAttachmentReference(
                id: id,
                displayName: TalkifyLocalAssetPolicy.safeFilename(url.lastPathComponent),
                resourceURI: managed.absoluteString
            )
        }
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finish(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish([])
    }

    private func finish(_ urls: [URL]) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: urls)
        } else {
            bufferedURLs = urls
        }
    }
}

@MainActor
private final class IOSCameraCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let fileStore: ManagedUserAssetFileStore
    private let accountScope: String
    private var continuation: CheckedContinuation<URL?, Never>?
    private var bufferedURL: URL?

    init(fileStore: ManagedUserAssetFileStore, accountScope: String) {
        self.fileStore = fileStore
        self.accountScope = accountScope
    }

    func result() async throws -> [DraftAttachmentReference] {
        let capturedURL: URL? = await withCheckedContinuation { continuation in
            if let bufferedURL {
                continuation.resume(returning: bufferedURL)
                self.bufferedURL = nil
            } else {
                self.continuation = continuation
            }
        }
        guard let url = capturedURL else { return [] }
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID().uuidString.lowercased()
        let managed = try fileStore.importFile(
            from: url,
            attachmentID: id,
            accountScope: accountScope
        )
        return [DraftAttachmentReference(
            id: id,
            displayName: UserImageNormalizer.safeFilename("photo.jpg", mimeType: nil),
            resourceURI: managed.absoluteString
        )]
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        let url: URL? = {
            guard let image = info[.originalImage] as? UIImage else { return nil }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("camera-\(UUID().uuidString).jpg")
            guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
            do {
                try data.write(to: tempURL, options: .completeFileProtectionUnlessOpen)
                return tempURL
            } catch {
                return nil
            }
        }()
        resume(with: url)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        resume(with: nil)
    }

    private func resume(with url: URL?) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: url)
        } else {
            bufferedURL = url
        }
    }
}
#endif
