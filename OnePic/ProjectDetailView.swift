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
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
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
    @State private var isCardFlipped = false
    @Environment(\.modelContext) private var modelContext

    private var currentPhoto: Photo? {
        guard photos.indices.contains(physics.currentIndex) else { return photos.first }
        return photos[physics.currentIndex]
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                DynamicPhotoBackground(image: currentImage, photoID: currentPhoto?.id)
                    .ignoresSafeArea()

                if photos.isEmpty {
                    EmptyFilmState()
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    photoContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let currentPhoto {
                    DateBadge(
                        date: currentPhoto.shotAt,
                        dayNumber: dayNumber(for: currentPhoto),
                        isVisible: isDateBadgeVisible
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 28)
                    .padding(.top, 12)
                }
            }
            .safeAreaInset(edge: .top) {
                topBar
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                bottomInfoBar
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 22)
                    .padding(.trailing, 50)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
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
            isCardFlipped = false
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
                Text("尝试用手拨动时间")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
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
        FlipPhotoCard(
            image: currentImage,
            tilt: physics.displayOffset,
            isFlipped: $isCardFlipped,
            note: currentPhoto.flatMap { notePreview(for: $0, showPlaceholder: false) },
            dayNumber: currentPhoto.map { dayNumber(for: $0) },
            onEditNote: beginEditing
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onLongPressGesture {
            isDeletePresented = true
        }
    }

    private var bottomInfoBar: some View {
        ZStack {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.25))

                Spacer()

                Button {
                    beginEditing()
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 34, height: 34)
                }
            }

            if let currentPhoto {
                HStack(spacing: 10) {
                    Text("DAY \(dayNumber(for: currentPhoto))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.5))
                    Text(currentPhoto.shotAt.formatted(.dateTime.year().month().day().hour().minute()))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            } else {
                Text("还没有照片")
                    .font(.subheadline.weight(.medium))
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

    @ViewBuilder
    private func photoContent() -> some View {
        GeometryReader { geo in
            let stripW: CGFloat = 72
            let outerPad: CGFloat = 22
            let stripInset: CGFloat = 26
            let stripReserve = stripW + stripInset + 6
            let innerW = geo.size.width - outerPad * 2
            let innerH = geo.size.height - 20
            let maxPhotoW = innerW - stripW - stripInset - 14
            let maxPhotoH = innerH - 12
            let fitsByWidth = maxPhotoW * 16 / 9 <= maxPhotoH
            let photoW = fitsByWidth ? maxPhotoW : maxPhotoH * 9 / 16
            let photoH = fitsByWidth ? maxPhotoW * 16 / 9 : maxPhotoH

            ZStack(alignment: .trailing) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    mainPhotoArea
                        .frame(width: photoW, height: photoH)
                        .gesture(filmDragGesture)
                    Spacer()
                        .frame(width: stripReserve)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                StackedCardStrip(
                    photos: photos,
                    selectedIndex: physics.currentIndex,
                    stripWidth: stripW,
                    onSelect: { index in
                        physics.setIndex(index, totalPhotos: photos.count)
                        revealDateBadge()
                    }
                )
                .frame(width: stripW)
                .padding(.trailing, stripInset)
                .clipped()
                .highPriorityGesture(filmDragGesture)
            }
            .padding(.horizontal, outerPad)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

    private func notePreview(for photo: Photo, showPlaceholder: Bool = true) -> String? {
        let trimmed = (photo.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return showPlaceholder ? "点大图编辑这一天的文字" : nil }
        return trimmed
    }
}

private final class FilmScrollPhysics: NSObject, ObservableObject {
    @Published var currentIndex: Int = 0
    @Published var displayOffset: CGFloat = 0
    @Published var isDragging = false

    private let cellHeight: CGFloat = 84
    private let damping: CGFloat = 0.82
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
        velocity = (predictedTranslation - translation) / cellHeight * 0.22
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
                    .blur(radius: 60)
                    .opacity(0.4)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.11, blue: 0.14),
                        Color(red: 0.06, green: 0.07, blue: 0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            Color.black.opacity(0.5)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.4), value: photoID)
    }
}

private struct FlipPhotoCard: View {
    let image: UIImage?
    let tilt: CGFloat
    @Binding var isFlipped: Bool
    let note: String?
    let dayNumber: Int?
    let onEditNote: () -> Void

    var body: some View {
        Flip3DCard(isFlipped: isFlipped) {
            cardFront
        } back: {
            cardBack
        }
        .clipped()
        .rotation3DEffect(.degrees(Double(tilt * -8)), axis: (x: 0, y: 1, z: 0))
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: tilt)
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                isFlipped.toggle()
            }
        }
    }

    private var cardFront: some View {
        ZStack(alignment: .bottomLeading) {
            GlassPhotoCard(image: image)

            if let dayNumber {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DAY \(dayNumber)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                    if let note {
                        Text(note)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(14)
            }
        }
    }

    private var cardBack: some View {
        ZStack {
            FrostedMirrorCardBack(image: image)

            VStack(spacing: 18) {
                if let note {
                    Text(note)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("还没有文字")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Button(action: onEditNote) {
                    Text("编辑")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.88), in: Capsule())
                }
            }
        }
        .shadow(color: .black.opacity(0.32), radius: 22, x: 0, y: 12)
    }
}

private struct Flip3DCard<Front: View, Back: View>: View {
    let isFlipped: Bool
    let front: Front
    let back: Back

    init(
        isFlipped: Bool,
        @ViewBuilder front: () -> Front,
        @ViewBuilder back: () -> Back
    ) {
        self.isFlipped = isFlipped
        self.front = front()
        self.back = back()
    }

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .modifier(Flip3DModifier(angle: isFlipped ? 180 : 0, cornerRadius: 24, front: front, back: back))
    }
}

private struct Flip3DModifier<Front: View, Back: View>: AnimatableModifier {
    var angle: Double
    let cornerRadius: CGFloat
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let radians = angle * .pi / 180
        let edgeOpacity = 1 - abs(cos(radians))
        let edgeWidth = max(1, CGFloat(edgeOpacity) * 14)
        let showingBack = angle >= 90

        return ZStack {
            ZStack {
                if showingBack {
                    back
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                } else {
                    front
                }
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.6),
                            .white.opacity(0.18),
                            .black.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: edgeWidth)
                .opacity(edgeOpacity)
                .blur(radius: 0.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
    }
}

private struct FrostedMirrorCardBack: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(x: -1, y: 1)
                    .saturation(0.85)
                    .blur(radius: 18)
                    .opacity(0.9)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.84)

            LinearGradient(
                colors: [.white.opacity(0.12), .black.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.7), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 8)
                .blur(radius: 6)
                .mask(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(lineWidth: 10)
                )
        }
    }
}

private struct GlassPhotoCard: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .layoutPriority(-1)
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
                        colors: [.white.opacity(0.52), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .shadow(color: .black.opacity(0.14), radius: 22, x: 0, y: 12)
    }
}

private struct StackedCardStrip: View {
    let photos: [Photo]
    let selectedIndex: Int
    let stripWidth: CGFloat
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        GlassCardCell(
                            photo: photo,
                            isSelected: index == selectedIndex,
                            distanceFromSelected: abs(index - selectedIndex)
                        )
                        .frame(width: stripWidth - 12, height: 76)
                        .id(index)
                        .onTapGesture { onSelect(index) }
                    }
                }
                .padding(.vertical, 18)
                .frame(width: stripWidth)
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .onAppear {
                proxy.scrollTo(selectedIndex, anchor: .center)
            }
            .onChange(of: selectedIndex) { _, next in
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    proxy.scrollTo(next, anchor: .center)
                }
            }
        }
    }
}

private struct GlassCardCell: View {
    let photo: Photo
    let isSelected: Bool
    let distanceFromSelected: Int
    @State private var image: UIImage?

    private var cardOpacity: Double {
        isSelected ? 1.0 : max(0.28, 1.0 - Double(distanceFromSelected) * 0.18)
    }
    private var cardScaleX: CGFloat {
        isSelected ? 1.0 : max(0.82, 1.0 - CGFloat(distanceFromSelected) * 0.06)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(isSelected ? 0.7 : 0.3),
                            .white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            LinearGradient(
                colors: [.white.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(Double(distanceFromSelected) * 0.12))
            }
        }
        .opacity(cardOpacity)
        .scaleEffect(x: cardScaleX * (isSelected ? 1.08 : 1.0), y: isSelected ? 1.08 : 1.0)
        .offset(x: isSelected ? -6 : 0)
        .zIndex(isSelected ? 1000 : Double(100 - distanceFromSelected))
        .shadow(
            color: .black.opacity(isSelected ? 0.4 : 0.2),
            radius: isSelected ? 16 : 6,
            x: 0, y: isSelected ? 10 : 3
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelected)
        .task(id: photo.relativePath) {
            image = PhotoStore.loadImage(relativePath: photo.relativePath)
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
