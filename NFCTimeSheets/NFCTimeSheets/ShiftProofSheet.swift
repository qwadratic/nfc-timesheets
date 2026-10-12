import SwiftUI
import UIKit
import AVFoundation

/// A server challenge must exist before opening the camera. No library source or saved
/// photo URL is accepted, and the encoded image is transient (never saved to Photos).
struct ShiftProofSheet: View {
    let clientUuid: String
    let completed: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var challenge: ProofChallenge?
    @State private var showCamera = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Text("Take a photo of the completed work now. Gallery photos cannot be used. An internet connection is required.")
                Button("Take work photo") { Task { await prepare() } }
                    .disabled(busy)
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Proof of work")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .fullScreenCover(isPresented: $showCamera) {
                ShiftCamera { image in
                    showCamera = false
                    guard let image else { return }
                    let capturedAt = Date.now
                    Task { await upload(image, capturedAt: capturedAt) }
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private func prepare() async {
        busy = true
        error = nil
        defer { busy = false }
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard authorized, UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = String(localized: "Camera unavailable. Allow camera access in Settings and use a device with a camera.")
            return
        }
        do {
            challenge = try await apiPost("/shifts/\(clientUuid)/proof-challenge", ProofEmpty())
            showCamera = true
        } catch {
            self.error = String(localized: "Could not prepare the photo. Check your connection and try again. Your shift has not been finished.")
        }
    }

    private func upload(_ image: UIImage, capturedAt: Date) async {
        guard let challenge else { return }
        guard capturedAt < challenge.expires_at else {
            error = String(localized: "Take a new photo to finish this shift. Your shift has not been finished.")
            return
        }
        busy = true
        defer { busy = false }
        // Redraw pixels to strip camera metadata and bound upload size and memory use.
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let reduced = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpeg = reduced.jpegData(compressionQuality: 0.65), jpeg.count <= 2 * 1024 * 1024 else {
            error = String(localized: "Photo could not be prepared. Please take another photo.")
            return
        }
        do {
            let response: ProofResponse = try await apiPost("/shifts/\(clientUuid)/proof",
                ProofUpload(challenge_id: challenge.challenge_id, captured_at: capturedAt, jpeg_base64: jpeg.base64EncodedString()))
            completed(response.proof_id)
            dismiss()
        } catch {
            self.error = String(localized: "Photo could not be sent. Check your connection and take another photo. Your shift has not been finished.")
        }
    }
}

private struct ProofEmpty: Encodable {}
private struct ProofChallenge: Decodable { let challenge_id: String; let expires_at: Date }
private struct ProofUpload: Encodable { let challenge_id: String; let captured_at: Date; let jpeg_base64: String }
private struct ProofResponse: Decodable { let proof_id: String }

private struct ShiftCamera: UIViewControllerRepresentable {
    let completed: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completed: (UIImage?) -> Void
        init(completed: @escaping (UIImage?) -> Void) { self.completed = completed }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completed(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completed(info[.originalImage] as? UIImage)
        }
    }
}
