#if os(iOS)
@preconcurrency import AVFoundation
import Combine
import Foundation

final class CameraController: NSObject, ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published private(set) var position: AVCaptureDevice.Position = .back
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "onepic.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let processorStore = ProcessorStore()
    private var currentInput: AVCaptureDeviceInput?
    private var internalPosition: AVCaptureDevice.Position = .back

    func requestAccessIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await MainActor.run { isAuthorized = true }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { isAuthorized = granted }
        default:
            await MainActor.run { isAuthorized = false }
        }
    }

    func configureIfNeeded() {
        guard isAuthorized else { return }
        let session = session
        let photoOutput = photoOutput
        sessionQueue.async {
            if !session.inputs.isEmpty { return }
            session.beginConfiguration()
            session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            self.currentInput = input
            self.internalPosition = .back
            Task { @MainActor in self.position = .back }

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.isHighResolutionCaptureEnabled = true
            }

            session.commitConfiguration()
        }
    }

    func toggleCamera() {
        let session = session
        sessionQueue.async {
            guard let currentInput = self.currentInput else { return }
            let newPosition: AVCaptureDevice.Position = (self.internalPosition == .back) ? .front : .back

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else {
                return
            }

            session.beginConfiguration()
            session.removeInput(currentInput)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                self.currentInput = newInput
                self.internalPosition = newPosition
                Task { @MainActor in self.position = newPosition }
            } else {
                session.addInput(currentInput)
            }
            session.commitConfiguration()
        }
    }

    func start() {
        let session = session
        sessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        let session = session
        sessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping @MainActor (Data) -> Void) {
        let photoOutput = photoOutput
        let processorStore = processorStore
        sessionQueue.async {
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true

            let processor = PhotoCaptureProcessor(
                onData: { data in
                    Task { @MainActor in completion(data) }
                },
                onFinish: { id in processorStore.remove(id: id) }
            )
            processorStore.insert(processor, id: processor.id)
            photoOutput.capturePhoto(with: settings, delegate: processor)
        }
    }

    private final class ProcessorStore: @unchecked Sendable {
        private var items: [Int64: PhotoCaptureProcessor] = [:]

        func insert(_ processor: PhotoCaptureProcessor, id: Int64) {
            items[id] = processor
        }

        func remove(id: Int64) {
            items[id] = nil
        }
    }

    private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
        let id: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        private let onData: (Data) -> Void
        private let onFinish: (Int64) -> Void

        init(onData: @escaping (Data) -> Void, onFinish: @escaping (Int64) -> Void) {
            self.onData = onData
            self.onFinish = onFinish
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            defer { onFinish(id) }
            guard error == nil, let data = photo.fileDataRepresentation() else { return }
            onData(data)
        }
    }
}
#endif
