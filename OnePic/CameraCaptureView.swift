import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct CameraCaptureView: View {
    let project: Project
#if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var isConfigured = false
    @Environment(\.modelContext) private var modelContext
    @Query private var photos: [Photo]
    @State private var ghostImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isGhostSettingsPresented = false
#endif

    #if os(iOS)
    init(project: Project) {
        self.project = project
        let projectID: UUID? = project.id
        _photos = Query(
            filter: #Predicate<Photo> { $0.projectID == projectID },
            sort: [SortDescriptor(\Photo.shotAt, order: .reverse)]
        )
    }
    #else
    init(project: Project) {
        self.project = project
    }
    #endif

    var body: some View {
#if os(iOS)
#if targetEnvironment(simulator)
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 44, weight: .semibold))
                Text("Simulator 不支持相机预览")
                    .font(.headline)
                Text("请用真机运行 onepic 才能拍照。\n（时间线/导出等功能后续可以继续在模拟器测试）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
            }
        }
#else
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.isAuthorized {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()

                if let ghostImage, project.ghostEnabled {
                    Image(uiImage: ghostImage)
                        .resizable()
                        .scaledToFill()
                        .opacity(project.ghostOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40, weight: .semibold))
                    Text("Camera permission is required.")
                        .font(.headline)
                    Text("Please enable Camera access in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .padding()
            }

            VStack {
                Spacer()

                VStack(spacing: 16) {
                    Button {
                        capture()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.25))
                                .frame(width: 72, height: 72)
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 68, height: 68)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }

            HStack {
                Spacer()
                Text("\(project.currentStreak)")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.trailing, 14)
                    .padding(.top, 10)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button { isGhostSettingsPresented = true } label: { Image(systemName: project.ghostEnabled ? "square.stack.3d.up.fill" : "square.stack.3d.up") }
                    Button { camera.toggleCamera() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }
                }
            }
        }
        .sheet(isPresented: $isGhostSettingsPresented) {
            GhostSettingsView(project: project)
        }
        .task {
            await camera.requestAccessIfNeeded()
            if camera.isAuthorized, !isConfigured {
                isConfigured = true
                camera.configureIfNeeded()
                camera.start()
            }
        }
        .onDisappear {
            camera.stop()
        }
        .task(id: ghostPhotoRelativePath) {
            guard let path = ghostPhotoRelativePath else {
                ghostImage = nil
                return
            }
            ghostImage = PhotoStore.loadImage(relativePath: path)
        }
        .alert("Capture failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
#endif
#else
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Camera is available on iPhone only.")
                .foregroundStyle(.white)
        }
#endif
    }

#if os(iOS)
    private var ghostPhotoRelativePath: String? {
        if !project.ghostEnabled { return nil }
        if let selectedID = project.ghostPhotoID {
            return photos.first(where: { $0.id == selectedID })?.relativePath
        }
        return photos.first?.relativePath
    }

    private func capture() {
        guard !isSaving else { return }
        isSaving = true
        camera.capturePhoto { data in
            Task {
                do {
                    try await saveCapturedPhoto(data: data)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSaving = false
            }
        }
    }

    private func saveCapturedPhoto(data: Data) async throws {
        guard let rawImage = UIImage(data: data) else {
            throw NSError(domain: "onepic.capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid photo data."])
        }

        let shotAt = Date()
        let image = ImageWatermark.applyDate(shotAt, to: rawImage)

        let photoID = UUID()
        _ = try PhotoStore.ensureProjectDirectory(projectID: project.id)
        let relativePath = PhotoStore.makeRelativePath(projectID: project.id, photoID: photoID)
        let url = PhotoStore.url(for: relativePath)

        guard let jpgData = image.jpegData(compressionQuality: 0.95) else {
            throw NSError(domain: "onepic.capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JPEG."])
        }
        try jpgData.write(to: url, options: [.atomic])

        let dayKey = DayKey.make(for: shotAt, calendar: .current)
        let photo = Photo(
            id: photoID,
            shotAt: shotAt,
            dayKey: dayKey,
            relativePath: relativePath,
            projectID: project.id,
            project: project
        )
        modelContext.insert(photo)
        _ = project.registerShot(at: shotAt)
    }
#endif
}
