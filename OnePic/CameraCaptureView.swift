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
    @State private var pendingPhoto: PendingCapturedPhoto?
    @State private var noteDraft = ""
    @State private var saveCompleted = false
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

                if camera.position == .front {
                    FaceDistanceGuideOverlay(faceRect: camera.faceRect)
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
            .opacity(pendingPhoto == nil ? 1 : 0)
            .allowsHitTesting(pendingPhoto == nil)

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
            .opacity(pendingPhoto == nil ? 1 : 0)

            if let pendingPhoto {
                CaptureNoteOverlay(
                    image: pendingPhoto.image,
                    note: $noteDraft,
                    isSaving: isSaving,
                    isCompleted: saveCompleted,
                    onRetake: resetPendingPhoto,
                    onCancel: { dismiss() },
                    onSkip: {
                        savePendingPhoto(pendingPhoto, noteOverride: "")
                    },
                    onSave: {
                        savePendingPhoto(pendingPhoto)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: pendingPhoto?.id)
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
        guard !isSaving, pendingPhoto == nil else { return }
        isSaving = true
        camera.capturePhoto { data in
            do {
                try prepareCapturedPhoto(data: data)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func prepareCapturedPhoto(data: Data) throws {
        guard let rawImage = UIImage(data: data) else {
            throw NSError(domain: "onepic.capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid photo data."])
        }

        let shotAt = Date()
        let image = ImageWatermark.applyDate(shotAt, to: rawImage)
        pendingPhoto = PendingCapturedPhoto(image: image, shotAt: shotAt)
        noteDraft = ""
        saveCompleted = false
    }

    private func savePendingPhoto(_ pendingPhoto: PendingCapturedPhoto, noteOverride: String? = nil) {
        guard !isSaving else { return }
        isSaving = true
        do {
            try saveCapturedPhoto(pendingPhoto, note: noteOverride ?? noteDraft)
            isSaving = false
            saveCompleted = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                await MainActor.run {
                    dismiss()
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }

    private func saveCapturedPhoto(_ pendingPhoto: PendingCapturedPhoto, note: String) throws {
        let shotAt = pendingPhoto.shotAt
        let image = pendingPhoto.image

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
            note: normalizedNote(note),
            projectID: project.id,
            project: project
        )
        modelContext.insert(photo)
        _ = project.registerShot(at: shotAt)
    }

    private func resetPendingPhoto() {
        pendingPhoto = nil
        noteDraft = ""
        saveCompleted = false
    }

    private func normalizedNote(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
#endif
}

#if os(iOS)
private struct PendingCapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let shotAt: Date
}

private struct FaceDistanceGuideOverlay: View {
    let faceRect: CGRect?

    private var guideState: FaceGuideState {
        guard let faceRect else { return .searching }
        let faceSize = max(faceRect.width, faceRect.height)
        if faceSize < 0.18 { return .moveCloser }
        if faceSize > 0.42 { return .moveBack }
        return .good
    }

    var body: some View {
        GeometryReader { geo in
            let circleSize = min(geo.size.width * 0.68, geo.size.height * 0.44, 310)
            let centerY = geo.size.height * 0.42

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.32), lineWidth: 18)
                        .frame(width: circleSize, height: circleSize)
                        .blur(radius: 0.4)

                    Circle()
                        .stroke(guideState.color.opacity(0.92), lineWidth: 3)
                        .frame(width: circleSize, height: circleSize)
                        .shadow(color: guideState.color.opacity(0.42), radius: 14, x: 0, y: 0)

                    Circle()
                        .stroke(.white.opacity(0.42), style: StrokeStyle(lineWidth: 1.4, dash: [8, 8]))
                        .frame(width: circleSize - 24, height: circleSize - 24)
                }
                .overlay(alignment: .bottom) {
                    Text(guideState.message)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.34), in: Capsule())
                        .offset(y: 46)
                }
                .position(x: geo.size.width / 2, y: centerY)
            }
        }
    }
}

private enum FaceGuideState {
    case searching
    case moveCloser
    case moveBack
    case good

    var message: String {
        switch self {
        case .searching:
            return "把脸放进圆框"
        case .moveCloser:
            return "靠近一点"
        case .moveBack:
            return "远一点"
        case .good:
            return "保持住"
        }
    }

    var color: Color {
        switch self {
        case .searching:
            return .white
        case .moveCloser, .moveBack:
            return Color(red: 1.0, green: 0.82, blue: 0.25)
        case .good:
            return Color(red: 0.45, green: 0.95, blue: 0.68)
        }
    }
}

private struct CaptureNoteOverlay: View {
    let image: UIImage
    @Binding var note: String
    let isSaving: Bool
    let isCompleted: Bool
    let onRetake: () -> Void
    let onCancel: () -> Void
    let onSkip: () -> Void
    let onSave: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .blur(radius: isCompleted ? 24 : 12)
                    .opacity(isCompleted ? 0.5 : 0.28)
                    .clipped()
                    .ignoresSafeArea()

                Color.black.opacity(isCompleted ? 0.42 : 0.22)
                    .ignoresSafeArea()

                if isCompleted {
                    completionView
                        .frame(maxWidth: proxy.size.width - 44)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    noteCard(maxHeight: proxy.size.height)
                        .frame(maxWidth: min(proxy.size.width - 36, 390))
                        .frame(maxHeight: proxy.size.height - 80, alignment: .bottom)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: isCompleted)
        }
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 156, height: 156)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 14)

            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                Text("完成")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
        }
    }

    private func noteCard(maxHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                    Text("今天想记下什么？")
                        .font(.headline.weight(.semibold))
                }

                Spacer()

                Button("跳过", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .disabled(isSaving)
            }

            TextEditor(text: $note)
                .scrollContentBackground(.hidden)
                .frame(height: min(116, max(88, maxHeight * 0.16)))
                .padding(10)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("写一点变化、心情，或者点跳过。")
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.14), in: Circle())
                }

                Button(action: onRetake) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.14), in: Circle())
                }

                Button(action: onSave) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                        }
                        Text(isSaving ? "保存中" : "保存")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(.black)
                    .background(.white.opacity(isSaving ? 0.72 : 0.94), in: Capsule())
                }
                .disabled(isSaving)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 22, x: 0, y: 14)
        .buttonStyle(.plain)
    }
}
#endif
