import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
import AVFoundation
import AudioToolbox
#endif

struct CameraCaptureView: View {
    let project: Project
#if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onepic_pendingDetailProjectID") private var pendingDetailProjectID = ""
    @AppStorage("onepic_pendingDetailNonce") private var pendingDetailNonce = 0
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
    @State private var showGrid = false
    @State private var isCapturing = false
    @State private var lastSliderStep = 0
    @State private var streakFlameScale: CGFloat = 1.0
    @State private var streakIsLit = false
    @State private var streakIsExpanded = false
    @State private var flashOpacity: CGFloat = 0
    @State private var shutterInFlight = false
    @State private var shutterCoreOffset: CGFloat = 0
    @State private var shutterCoreDim: CGFloat = 0
    @State private var showStreakEasterEgg = false
    @State private var streakBackdropImage: UIImage?
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
        NavigationStack {
            ZStack(alignment: .top) {
                // 1. 相机实时预览（全屏）
                Color.black.ignoresSafeArea()

                if camera.isAuthorized {
                    CameraPreviewView(session: camera.session)
                        .ignoresSafeArea()

                    // 2. Ghost 叠图（上一张半透明）
                    if let ghostImage, project.ghostEnabled {
                        Image(uiImage: ghostImage)
                            .resizable()
                            .scaledToFill()
                            .opacity(project.ghostOpacity)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    if camera.position == .front, pendingPhoto == nil, !showStreakEasterEgg {
                        FaceDistanceGuideOverlay(faceRect: camera.faceRect)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    overlayControls

                    Color.white
                        .opacity(flashOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

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

                if showStreakEasterEgg {
                    StreakFlameEasterEgg(
                        streakCount: project.currentStreak,
                        backdropImage: streakBackdropImage,
                        onCompleted: {
                            showStreakEasterEgg = false
                            streakBackdropImage = nil
                            pendingDetailProjectID = project.id.uuidString
                            pendingDetailNonce &+= 1
                            dismiss()
                        }
                    )
                    .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: pendingPhoto?.id)
            .navigationBarBackButtonHidden(true)
            .sheet(isPresented: $isGhostSettingsPresented) {
                GhostSettingsView(project: project)
            }
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
    // MARK: - UI Components

    private var overlayControls: some View {
        ZStack {
            HStack {
                GlassCircleButton(icon: "chevron.left") {
                    dismiss()
                }

                Spacer()

                GlassCircleButton(icon: "gearshape.fill") {
                    isGhostSettingsPresented = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, safeAreaTopInset + 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(spacing: 18) {
                LeicaShutterButton(coreOffset: $shutterCoreOffset, coreDim: $shutterCoreDim) {
                    await runShutterSequenceAndCapture()
                }

                GlassCircleButton(icon: "arrow.triangle.2.circlepath.camera") {
                    camera.toggleCamera()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .padding(.bottom, safeAreaBottomInset + 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(pendingPhoto == nil && !showStreakEasterEgg ? 1 : 0)
        .allowsHitTesting(pendingPhoto == nil && !showStreakEasterEgg)
    }

    private var topBar: some View {
        HStack {
            GlassCapsule {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
            }

            Spacer()

            GlassCapsule {
                Text("DAY \(dayNumber)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, safeAreaTopInset + 10)
        .opacity(pendingPhoto == nil ? 1 : 0)
        .allowsHitTesting(pendingPhoto == nil)
    }

    private var ghostSlider: some View {
        VStack {
            if project.ghostEnabled {
                GlassCapsule {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))

                        Slider(value: Binding(
                            get: { project.ghostOpacity },
                            set: { newValue in
                                project.ghostOpacity = newValue
                                let step = Int(newValue * 10)
                                if step != lastSliderStep {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    lastSliderStep = step
                                }
                            }
                        ), in: 0...0.8)
                        .tint(.white)
                        .frame(width: 120)

                        Text("\(Int(project.ghostOpacity * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 32)
                    }
                }
                .padding(.top, safeAreaTopInset + 50)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .opacity(pendingPhoto == nil ? 1 : 0)
        .allowsHitTesting(pendingPhoto == nil)
    }

    private var leftToolbar: some View {
        VStack(spacing: 12) {
            ToolButton(icon: "arrow.triangle.2.circlepath.camera", isActive: false) {
                camera.toggleCamera()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .opacity(pendingPhoto == nil ? 1 : 0)
        .allowsHitTesting(pendingPhoto == nil)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Spacer(minLength: 0)

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

                        if isCapturing {
                            Circle()
                                .fill(.white.opacity(0.5))
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .scaleEffect(isCapturing ? 0.9 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)

                ToolButton(icon: "arrow.triangle.2.circlepath.camera", isActive: false) {
                    camera.toggleCamera()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, safeAreaBottomInset + 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .opacity(pendingPhoto == nil ? 1 : 0)
        .allowsHitTesting(pendingPhoto == nil)
    }

    private var streakBadge: some View {
        VStack {
            if streakIsExpanded {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Text("🔥")
                            .font(.system(size: 28))
                        Text("\(project.currentStreak)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }

                    Text("连拍 \(project.currentStreak) 天")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .background(Color.orange.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.orange.opacity(0.6), .orange.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
            } else {
                Text("🔥")
                    .font(.system(size: 32))
                    .scaleEffect(streakFlameScale)
                    .opacity(streakIsLit ? 1.0 : 0.5)
                    .shadow(color: streakIsLit ? .orange.opacity(0.8) : .clear, radius: 12, x: 0, y: 0)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, safeAreaBottomInset + 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .opacity(pendingPhoto == nil ? 1 : 0)
        .allowsHitTesting(pendingPhoto == nil)
        .gesture(
            LongPressGesture(minimumDuration: 0.6)
                .onChanged { _ in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeIn(duration: 0.8)) { streakIsLit = true }
                    streakFlameScale = 1.1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            streakIsExpanded = true
                        }
                    }
                }
                .onEnded { _ in
                    streakFlameScale = 1.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeOut(duration: 0.6)) {
                            streakIsLit = false
                            streakIsExpanded = false
                        }
                    }
                }
        )
    }

    private var dayNumber: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: project.createdAt, to: Date()).day ?? 0
        return days + 1
    }

    private var safeAreaTopInset: CGFloat {
#if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 0
        }
        return window.safeAreaInsets.top
#else
        return 0
#endif
    }

    private var safeAreaBottomInset: CGFloat {
#if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 0
        }
        return window.safeAreaInsets.bottom
#else
        return 0
#endif
    }

    // MARK: - Camera Logic (unchanged)

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

    private func runShutterSequenceAndCapture() async {
        guard !isSaving, pendingPhoto == nil, !shutterInFlight else { return }
        shutterInFlight = true
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.08)) {
            shutterCoreOffset = 4
            shutterCoreDim = 0.08
        }
        try? await Task.sleep(nanoseconds: 80_000_000)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.linear(duration: 0.03)) {
            flashOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.3)) {
            flashOpacity = 0
        }
        capture()
        AudioServicesPlaySystemSound(1108)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.62)) {
            shutterCoreOffset = -2
            shutterCoreDim = 0
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            shutterCoreOffset = 0
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        shutterInFlight = false
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
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                self.streakBackdropImage = pendingPhoto.image
                self.pendingPhoto = nil
                self.noteDraft = ""
                self.saveCompleted = false
                self.showStreakEasterEgg = true
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

// MARK: - New UI Components

private struct GlassCapsule<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

private struct FaceGuideFrameView: View {
    let faceRect: CGRect?
    let lineLength: CGFloat = 20
    let lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { geo in
            if let faceRect {
                let rect = convertRect(faceRect, in: geo.size)

                Path { p in
                    // 左上角
                    p.move(to: CGPoint(x: rect.minX, y: rect.minY + lineLength))
                    p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                    p.addLine(to: CGPoint(x: rect.minX + lineLength, y: rect.minY))

                    // 右上角
                    p.move(to: CGPoint(x: rect.maxX - lineLength, y: rect.minY))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + lineLength))

                    // 左下角
                    p.move(to: CGPoint(x: rect.minX, y: rect.maxY - lineLength))
                    p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    p.addLine(to: CGPoint(x: rect.minX + lineLength, y: rect.maxY))

                    // 右下角
                    p.move(to: CGPoint(x: rect.maxX - lineLength, y: rect.maxY))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - lineLength))
                }
                .stroke(Color.yellow.opacity(0.8), lineWidth: lineWidth)
            }
        }
    }

    private func convertRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width,
            y: rect.minY * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        )
    }
}

private struct ToolButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isActive ? .yellow : .white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(
                                    isActive ? Color.yellow.opacity(0.6) : Color.white.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                )
        }
    }
}

private struct GlassCircleButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
        }
    }
}

private struct LeicaShutterButton: View {
    @Binding var coreOffset: CGFloat
    @Binding var coreDim: CGFloat
    let action: () async -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.65), lineWidth: 1.5)
                .frame(width: 86, height: 86)
                .shadow(color: .white.opacity(0.14), radius: 10, x: 0, y: 0)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 78, height: 78)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )

            ZStack {
                Circle()
                    .fill(Color.white.opacity(1 - coreDim))

                LinearGradient(
                    colors: [
                        .white.opacity(0.92),
                        .white.opacity(0.8),
                        .black.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.overlay)
                .clipShape(Circle())
            }
            .frame(width: 60, height: 60)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 8)
            .shadow(color: .white.opacity(0.65), radius: 10, x: 0, y: -6)
            .offset(y: coreOffset)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    Task { await action() }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

private struct StreakFlameEasterEgg: View {
    let streakCount: Int
    let backdropImage: UIImage?
    let onCompleted: () -> Void

    @State private var igniteProgress: CGFloat = 0
    @State private var isPressing = false
    @State private var didComplete = false
    @State private var showBurst = false
    @State private var showCount = false
    @State private var hideSelf = false
    @State private var igniteTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let backdropImage {
                Image(uiImage: backdropImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 24)
                    .opacity(0.5)
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            }

            Color.black.opacity(0.42).ignoresSafeArea()

            if !showCount {
                promptCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 140)
                    .padding(.horizontal, 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if showCount {
                VStack(spacing: 10) {
                    Text("🔥")
                        .font(.system(size: 34))
                    Text("连续打卡 \(streakCount) 天")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.26), radius: 22, x: 0, y: 16)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            flameButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(hideSelf ? 0 : 1)
        .animation(.easeOut(duration: 0.28), value: hideSelf)
        .allowsHitTesting(!showCount)
        .onDisappear {
            igniteTask?.cancel()
            igniteTask = nil
        }
    }

    private var flameButton: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 1)

                circleFill
                    .opacity(didComplete ? 1 : max(0, Double(igniteProgress)))

                flameOutline

                if !didComplete {
                    SmokePuffs()
                        .opacity(igniteProgress < 0.08 ? 1 : 0.2)
                        .allowsHitTesting(false)
                }

                if showBurst {
                    FlameBurst()
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 14)
            .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.22).opacity(Double(igniteProgress) * 0.55), radius: 22, x: 0, y: 0)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !didComplete else { return }
                    if !isPressing {
                        isPressing = true
                        UISelectionFeedbackGenerator().selectionChanged()
                        startIgniteLoop()
                    }
                }
                .onEnded { _ in
                    isPressing = false
                    if !didComplete, igniteProgress < 0.98 {
                        igniteTask?.cancel()
                        igniteTask = nil
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            igniteProgress = 0
                        }
                    }
                }
        )
    }

    private var flameFill: some View {
        EmptyView()
    }

    private var circleFill: some View {
        GeometryReader { geo in
            let height = geo.size.height * igniteProgress
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.54, blue: 0.16),
                            Color(red: 1.0, green: 0.86, blue: 0.22)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: max(0, height))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .clipShape(Circle())
    }

    private var flameOutline: some View {
        Image(systemName: "flame")
            .resizable()
            .scaledToFit()
            .padding(42)
            .foregroundStyle(.white.opacity(0.26))
            .shadow(color: .white.opacity(0.08), radius: 12, x: 0, y: 0)
    }

    private var promptCard: some View {
        VStack(spacing: 10) {
            Text("真厉害，你已经坚持了 \(streakCount) 天")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("请长按火焰")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.26), radius: 22, x: 0, y: 16)
    }

    private func startIgniteLoop() {
        igniteTask?.cancel()
        igniteTask = Task { @MainActor in
            var steps = 0
            while !Task.isCancelled, isPressing, steps < 10 {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard isPressing else { break }
                steps += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if steps >= 10 {
                    igniteProgress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.26)) {
                        igniteProgress = min(1, CGFloat(steps) / 10)
                    }
                }
            }

            if !Task.isCancelled, !didComplete, igniteProgress >= 0.98 {
                igniteProgress = 1
                didComplete = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                AudioServicesPlaySystemSound(1007)
                showBurst = true
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    showCount = true
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeOut(duration: 0.35)) {
                    showCount = false
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                withAnimation(.easeOut(duration: 0.28)) {
                    hideSelf = true
                }
                try? await Task.sleep(nanoseconds: 280_000_000)
                onCompleted()
            }
        }
    }
}

private struct SmokePuffs: View {
    var body: some View {
        ZStack {
            SmokePuff(delay: 0.0, x: -8)
            SmokePuff(delay: 0.25, x: 4)
            SmokePuff(delay: 0.5, x: 10)
            SmokePuff(delay: 0.75, x: -2)
        }
        .offset(y: -30)
    }
}

private struct SmokePuff: View {
    let delay: Double
    let x: CGFloat
    @State private var y: CGFloat = 0
    @State private var opacity: CGFloat = 0
    @State private var scale: CGFloat = 0.8

    var body: some View {
        Circle()
            .fill(.white.opacity(0.28))
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(x: x, y: y)
            .onAppear {
                Task { @MainActor in
                    while true {
                        y = 0
                        opacity = 0
                        scale = 0.8
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        withAnimation(.easeOut(duration: 1.0)) {
                            y = -20
                            opacity = 0
                            scale = 1.25
                        }
                        opacity = 0.6
                        try? await Task.sleep(nanoseconds: 1_100_000_000)
                    }
                }
            }
    }
}

private struct FlameBurst: View {
    @State private var t: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * .pi * 2
                let dx = CGFloat(cos(angle)) * 18 * t
                let dy = CGFloat(sin(angle)) * 18 * t
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.9, blue: 0.25),
                                Color(red: 1.0, green: 0.5, blue: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 4)
                    .opacity(1 - t)
                    .offset(x: dx, y: dy - 2)
                    .blur(radius: 0.2)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                t = 1
            }
        }
    }
}
#endif
