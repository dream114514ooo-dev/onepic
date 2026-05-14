import SwiftUI
import SwiftData
#if os(iOS)
import Combine
import QuartzCore
import UIKit
#endif

struct ProjectDetailView: View {
    let project: Project

#if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var photos: [Photo]

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
        FilmProjectDetailView(
            project: project,
            photos: photos,
            onBack: { dismiss() },
            onDelete: deletePhoto
        )
        .toolbar(.hidden, for: .navigationBar)
#else
        Text("This view is available on iPhone only.")
#endif
    }

#if os(iOS)
    private func deletePhoto(_ photo: Photo) {
        PhotoStore.deletePhoto(relativePath: photo.relativePath)
        if project.ghostPhotoID == photo.id {
            project.ghostPhotoID = nil
        }
        modelContext.delete(photo)
        try? modelContext.save()
    }
#endif
}

#if os(iOS)
private struct FilmProjectDetailView: View {
    let project: Project
    let photos: [Photo]
    let onBack: () -> Void
    let onDelete: (Photo) -> Void

    @StateObject private var physics = FilmScrollPhysics()
    @State private var currentImage: UIImage?
    @State private var isDateBadgeVisible = false
    @State private var isNoteEditorPresented = false
    @State private var noteDraft = ""
    @State private var isDeletePresented = false
    @Environment(\.modelContext) private var modelContext

    private var currentPhoto: Photo? {
        guard photos.indices.contains(physics.currentIndex) else { return photos.first }
        return photos[physics.currentIndex]
    }

    var body: some View {
        ZStack {
            DynamicPhotoBackground(image: currentImage, photoID: currentPhoto?.id)

            VStack(spacing: 14) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if photos.isEmpty {
                    EmptyFilmState()
                        .padding(.horizontal, 18)
                        .frame(maxHeight: .infinity)
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 12) {
                            mainPhotoArea
                                .frame(width: geo.size.width * 0.74)

                            FilmStripView(
                                photos: photos,
                                currentIndex: physics.currentIndex,
                                onSelect: { index in
                                    physics.setIndex(index, totalPhotos: photos.count)
                                    revealDateBadge()
                                }
                            )
                            .frame(width: max(72, geo.size.width * 0.22))
                            .gesture(filmDragGesture)
                        }
                        .padding(.horizontal, 16)
                    }

                    bottomInfoBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }

            if let currentPhoto {
                DateBadge(
                    date: currentPhoto.shotAt,
                    dayNumber: dayNumber(for: currentPhoto),
                    isVisible: isDateBadgeVisible
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 28)
                .padding(.top, 86)
            }
        }
        .onAppear {
            physics.configure(totalPhotos: photos.count)
            loadCurrentImage()
        }
        .onChange(of: photos.count) { _, count in
            physics.configure(totalPhotos: count)
            loadCurrentImage()
        }
        .onChange(of: physics.currentIndex) { _, _ in
            loadCurrentImage()
            revealDateBadge()
        }
        .sheet(isPresented: $isNoteEditorPresented) {
            PhotoNoteEditorView(
                note: $noteDraft,
                onCancel: { isNoteEditorPresented = false },
                onSave: saveNote
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("删除这张照片？", isPresented: $isDeletePresented, titleVisibility: .visible) {
            Button("删除照片", role: .destructive) {
                if let currentPhoto {
                    onDelete(currentPhoto)
                    physics.configure(totalPhotos: max(photos.count - 1, 0))
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("照片文件和背面的文字都会被删除。")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text("用手拨动时间")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
            }

            Spacer()

            NavigationLink(destination: CameraCaptureView(project: project)) {
                Image(systemName: "camera.fill")
                    .font(.headline.weight(.semibold))
                    .frame(width: 42, height: 38)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
    }

    private var mainPhotoArea: some View {
        ZStack(alignment: .bottomLeading) {
            GlassPhotoCard(image: currentImage, tilt: physics.displayOffset)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    beginEditing()
                }
                .onLongPressGesture {
                    isDeletePresented = true
                }

            if let currentPhoto {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DAY \(dayNumber(for: currentPhoto))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(notePreview(for: currentPhoto))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
                .padding(12)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(14)
            }
        }
    }

    private var bottomInfoBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.25))

            if let currentPhoto {
                Text("DAY \(dayNumber(for: currentPhoto))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                Text("·")
                    .foregroundStyle(.white.opacity(0.5))
                Text(currentPhoto.shotAt.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text("还没有照片")
                    .font(.subheadline.weight(.medium))
            }

            Spacer()

            Button {
                beginEditing()
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 34, height: 34)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
    }

    private var filmDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                physics.onDragChanged(
                    translation: value.translation.height,
                    totalPhotos: photos.count
                )
                isDateBadgeVisible = true
            }
            .onEnded { value in
                physics.onDragEnded(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height,
                    totalPhotos: photos.count
                ) {
                    hideDateBadgeLater()
                }
            }
    }

    private func loadCurrentImage() {
        guard let currentPhoto else {
            currentImage = nil
            return
        }
        currentImage = PhotoStore.loadImage(relativePath: currentPhoto.relativePath)
    }

    private func beginEditing() {
        guard let currentPhoto else { return }
        noteDraft = currentPhoto.note ?? ""
        isNoteEditorPresented = true
    }

    private func saveNote() {
        guard let currentPhoto else { return }
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        currentPhoto.note = trimmed.isEmpty ? nil : trimmed
        try? modelContext.save()
        isNoteEditorPresented = false
    }

    private func revealDateBadge() {
        isDateBadgeVisible = true
        hideDateBadgeLater()
    }

    private func hideDateBadgeLater() {
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                if !physics.isDragging {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isDateBadgeVisible = false
                    }
                }
            }
        }
    }

    private func dayNumber(for photo: Photo) -> Int {
        let start = Calendar.current.startOfDay(for: project.createdAt)
        let day = Calendar.current.startOfDay(for: photo.shotAt)
        return max((Calendar.current.dateComponents([.day], from: start, to: day).day ?? 0) + 1, 1)
    }

    private func notePreview(for photo: Photo) -> String {
        let trimmed = (photo.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "点大图编辑这一天的文字" : trimmed
    }
}

private final class FilmScrollPhysics: NSObject, ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var displayOffset: CGFloat = 0
    @Published var isDragging = false

    private let cellHeight: CGFloat = 84
    private let damping: CGFloat = 0.88
    private var dragStartIndex: Int = 0
    private var velocity: CGFloat = 0
    private var displayLink: CADisplayLink?
    private let selectionFeedback = UISelectionFeedbackGenerator()

    func configure(totalPhotos: Int) {
        currentIndex = clampedIndex(currentIndex, totalPhotos: totalPhotos)
        displayOffset = 0
    }

    func setIndex(_ index: Int, totalPhotos: Int) {
        let clamped = clampedIndex(index, totalPhotos: totalPhotos)
        guard clamped != currentIndex else { return }
        currentIndex = clamped
        selectionFeedback.selectionChanged()
    }

    func onDragChanged(translation: CGFloat, totalPhotos: Int) {
        guard totalPhotos > 0 else { return }
        if !isDragging {
            isDragging = true
            dragStartIndex = currentIndex
            displayLink?.invalidate()
            selectionFeedback.prepare()
        }

        let rawIndex = CGFloat(dragStartIndex) + translation / cellHeight
        let nextIndex = clampedIndex(Int(rawIndex.rounded()), totalPhotos: totalPhotos)
        displayOffset = rawIndex - CGFloat(nextIndex)

        if nextIndex != currentIndex {
            currentIndex = nextIndex
            selectionFeedback.selectionChanged()
        }
    }

    func onDragEnded(
        translation: CGFloat,
        predictedTranslation: CGFloat,
        totalPhotos: Int,
        onSettled: @escaping () -> Void
    ) {
        guard totalPhotos > 0 else { return }
        isDragging = false
        velocity = (predictedTranslation - translation) / cellHeight * 0.28
        if abs(velocity) < 0.05 {
            snap(totalPhotos: totalPhotos, onSettled: onSettled)
            return
        }
        startInertia(totalPhotos: totalPhotos, onSettled: onSettled)
    }

    private func startInertia(totalPhotos: Int, onSettled: @escaping () -> Void) {
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(updateInertia(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        inertiaTotalPhotos = totalPhotos
        inertiaSettled = onSettled
    }

    private var inertiaTotalPhotos = 0
    private var inertiaSettled: (() -> Void)?

    @objc private func updateInertia(_ link: CADisplayLink) {
        guard inertiaTotalPhotos > 0 else {
            link.invalidate()
            return
        }

        velocity *= damping
        if abs(velocity) < 0.015 {
            snap(totalPhotos: inertiaTotalPhotos, onSettled: inertiaSettled)
            return
        }

        let rawIndex = CGFloat(currentIndex) + velocity
        let nextIndex = clampedIndex(Int(rawIndex.rounded()), totalPhotos: inertiaTotalPhotos)
        displayOffset = rawIndex - CGFloat(nextIndex)

        if nextIndex != currentIndex {
            currentIndex = nextIndex
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.45)
        }
    }

    private func snap(totalPhotos: Int, onSettled: (() -> Void)?) {
        displayLink?.invalidate()
        displayLink = nil
        currentIndex = clampedIndex(currentIndex, totalPhotos: totalPhotos)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            displayOffset = 0
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSettled?()
    }

    private func clampedIndex(_ index: Int, totalPhotos: Int) -> Int {
        guard totalPhotos > 0 else { return 0 }
        return min(max(index, 0), totalPhotos - 1)
    }
}

private struct DynamicPhotoBackground: View {
    let image: UIImage?
    let photoID: UUID?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 62)
                    .saturation(1.18)
                    .opacity(0.46)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.16, blue: 0.18),
                        Color(red: 0.08, green: 0.09, blue: 0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            Color.black.opacity(0.52)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.4), value: photoID)
    }
}

private struct GlassPhotoCard: View {
    let image: UIImage?
    let tilt: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }

            LinearGradient(
                colors: [.white.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.62), .white.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: .black.opacity(0.32), radius: 22, x: 0, y: 12)
        .rotation3DEffect(.degrees(Double(tilt * -8)), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: tilt)
    }
}

private struct FilmStripView: View {
    let photos: [Photo]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            FilmCell(
                                photo: photo,
                                isSelected: index == currentIndex
                            )
                            .id(index)
                            .onTapGesture {
                                onSelect(index)
                            }
                        }
                    }
                    .padding(.vertical, max((geo.size.height - 76) / 2, 18))
                }
                .scrollDisabled(true)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .onChange(of: currentIndex) { _, index in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct FilmCell: View {
    let photo: Photo
    let isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.32))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .opacity(isSelected ? 1 : 0.48)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 56, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.86), lineWidth: 1.6)
                    .frame(width: 56, height: 72)
            }
        }
        .frame(width: 66, height: 82)
        .scaleEffect(isSelected ? 1.06 : 1)
        .overlay(alignment: .leading) {
            FilmSprocketColumn()
                .offset(x: -3)
        }
        .overlay(alignment: .trailing) {
            FilmSprocketColumn()
                .offset(x: 3)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: isSelected)
        .task(id: photo.relativePath) {
            image = PhotoStore.loadImage(relativePath: photo.relativePath)
        }
    }
}

private struct FilmSprocketColumn: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(.black.opacity(0.48))
                    .frame(width: 8, height: 6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 0.5)
                    }
            }
        }
    }
}

private struct DateBadge: View {
    let date: Date
    let dayNumber: Int
    let isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DAY \(dayNumber)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            Text(date.formatted(.dateTime.year().month().day()))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isVisible)
    }
}

private struct EmptyFilmState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            Text("还没有胶片")
                .font(.headline.weight(.semibold))
            Text("拍下第一张，时间就会从这里开始。")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct PhotoNoteEditorView: View {
    @Binding var note: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("照片背面的文字")
                    .font(.headline.weight(.semibold))

                TextEditor(text: $note)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 180)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if note.isEmpty {
                            Text("写一点这一天的变化或心情。")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }
                    }

                Spacer()
            }
            .padding(20)
            .navigationTitle("编辑 note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: onSave)
                }
            }
        }
    }
}
#endif
