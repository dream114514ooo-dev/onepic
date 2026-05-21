import SwiftUI
import SwiftData

struct ProjectListView: View {
    fileprivate enum OverlayMode: Hashable {
        case quick
        case edit
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]

    @AppStorage("onepic_pendingDetailProjectID") private var pendingDetailProjectID = ""
    @AppStorage("onepic_pendingDetailNonce") private var pendingDetailNonce = 0

    @State private var didBootstrap = false
    @State private var activeProjectID: UUID?
    @State private var isActionPresented = false
    @State private var isActionOverlayVisible = false
    @State private var actionOverlayProgress: CGFloat = 0
    @State private var projectFrames: [UUID: CGRect] = [:]
    @State private var overlayMode: OverlayMode = .quick
    @State private var path: [Route] = []
    @State private var isCameraPresented = false
    @State private var cameraProjectID: UUID?
    @State private var errorMessage: String?
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @State private var projectIDPendingDelete: UUID?
    @State private var reminderProjectID: UUID?
    @State private var isReminderPresented = false
    @Namespace private var selectionNamespace

    var body: some View {
#if os(iOS)
        GeometryReader { proxy in
            ZStack {
                NavigationStack(path: $path) {
                    List {
                        ForEach(projects) { project in
                            ProjectRowButton(
                                project: project,
                                isActive: project.id == activeProjectID && isActionOverlayVisible,
                                isOverlayVisible: isActionOverlayVisible,
                                namespace: selectionNamespace
                            ) {
                                presentActionOverlay(projectID: project.id, mode: .quick)
                            } onLongPress: {
                                presentActionOverlay(projectID: project.id, mode: .edit)
                            } onChevronTap: {
                                activeProjectID = project.id
                                openDetail()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                    .scrollDisabled(isActionOverlayVisible)
                    .onPreferenceChange(ProjectCardFrameKey.self) { frames in
                        projectFrames = frames
                    }
                    .navigationTitle("Projects")
                    .toolbarBackground(Color(.systemBackground), for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem {
                            Button {
                                createProject()
                            } label: {
                                Image(systemName: "plus")
                            }
                            .disabled(!canCreateProject)
                        }
                    }
                    .alert("更改项目名字", isPresented: $isRenamePresented) {
                        TextField("Project name", text: $renameDraft)
                        Button("取消", role: .cancel) {}
                        Button("保存") { saveProjectName() }
                    } message: {
                        Text("给这个记录换一个更贴近它的名字。")
                    }
                    .alert("删除项目？", isPresented: Binding(get: { projectIDPendingDelete != nil }, set: { if !$0 { projectIDPendingDelete = nil } })) {
                        Button("取消", role: .cancel) { projectIDPendingDelete = nil }
                        Button("删除", role: .destructive) { deletePendingProject() }
                    } message: {
                        Text("项目里的照片和记录都会被删除。")
                    }
                    .navigationDestination(for: Route.self) { route in
                        switch route.kind {
                        case .detail:
                            if let project = projects.first(where: { $0.id == route.projectID }) {
                                ProjectDetailView(project: project)
                            } else {
                                EmptyView()
                            }
                        }
                    }
                }
                .blur(radius: 15 * actionOverlayProgress)
                .animation(.easeInOut(duration: 0.25), value: actionOverlayProgress)
                .allowsHitTesting(!isActionOverlayVisible)

                if isActionOverlayVisible,
                   let activeProjectID,
                   let rect = projectFrames[activeProjectID],
                   let project = activeProject {
                    ProjectActionOverlay(
                        project: project,
                        cardRect: rect,
                        containerSize: proxy.size,
                        progress: actionOverlayProgress,
                        mode: overlayMode,
                        namespace: selectionNamespace,
                        onDismiss: dismissActionOverlay,
                        onCamera: openCamera,
                        onDetail: openDetail,
                        onReminder: openReminderSettings,
                        onRename: beginRename,
                        onDelete: beginDeleteProject
                    )
                    .ignoresSafeArea()
                    .zIndex(999)
                }
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented, onDismiss: { cameraProjectID = nil }) {
            Group {
                if let cameraProjectID,
                   let project = projects.first(where: { $0.id == cameraProjectID }) {
                    NavigationStack {
                        CameraCaptureView(project: project)
                    }
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $isReminderPresented, onDismiss: { reminderProjectID = nil }) {
            Group {
                if let reminderProjectID,
                   let project = projects.first(where: { $0.id == reminderProjectID }) {
                    ReminderSettingsView(project: project)
                } else {
                    EmptyView()
                }
            }
        }
        .task {
            await bootstrapIfNeeded()
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: pendingDetailNonce) { _, _ in
            openDetailFromCameraIfNeeded()
        }
#else
        Text("Projects are available on iPhone only.")
#endif
    }

    private var canCreateProject: Bool {
        VIP.isVIP || projects.count < VIP.maxFreeProjects
    }

    private func bootstrapIfNeeded() async {
        if didBootstrap { return }
        didBootstrap = true

        guard projects.isEmpty else { return }
        let project = Project(name: "Project 1", lastOpenedAt: Date())
        modelContext.insert(project)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createProject() {
        let name = "Project \(projects.count + 1)"
        let project = Project(name: name, lastOpenedAt: Date())
        modelContext.insert(project)
        try? modelContext.save()
    }

    private var activeProject: Project? {
        guard let activeProjectID else { return nil }
        return projects.first(where: { $0.id == activeProjectID })
    }

    private func presentActionOverlay(projectID: UUID, mode: OverlayMode) {
        activeProjectID = projectID
        overlayMode = mode
        isActionPresented = true
        isActionOverlayVisible = true
        actionOverlayProgress = 0
        withAnimation(.interactiveSpring(response: 0.52, dampingFraction: 0.86, blendDuration: 0.14)) {
            actionOverlayProgress = 1
        }
    }

    private func dismissActionOverlay() {
        isActionPresented = false
        withAnimation(.interactiveSpring(response: 0.40, dampingFraction: 0.92, blendDuration: 0.12)) {
            actionOverlayProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            if !isActionPresented {
                isActionOverlayVisible = false
                activeProjectID = nil
            }
        }
    }

    private func openCamera() {
        guard let project = activeProject else { return }
        project.lastOpenedAt = Date()
        dismissActionOverlay()
        cameraProjectID = project.id
        DispatchQueue.main.async {
            isCameraPresented = true
        }
    }

    private func openDetail() {
        guard let project = activeProject else { return }
        project.lastOpenedAt = Date()
        dismissActionOverlay()
        DispatchQueue.main.async {
            path.append(Route(kind: .detail, projectID: project.id))
        }
    }

    private func openDetailFromCameraIfNeeded() {
        guard !pendingDetailProjectID.isEmpty,
              let projectID = UUID(uuidString: pendingDetailProjectID),
              let project = projects.first(where: { $0.id == projectID }) else {
            return
        }
        pendingDetailProjectID = ""
        activeProjectID = project.id
        project.lastOpenedAt = Date()
        DispatchQueue.main.async {
            path.append(Route(kind: .detail, projectID: project.id))
        }
    }

    private func beginRename() {
        guard let project = activeProject else { return }
        renameDraft = project.name
        dismissActionOverlay()
        DispatchQueue.main.async {
            isRenamePresented = true
        }
    }

    private func saveProjectName() {
        guard let project = activeProject else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.name = trimmed
        project.lastOpenedAt = Date()
        try? modelContext.save()
    }

    private func beginDeleteProject() {
        guard let project = activeProject else { return }
        let projectID = project.id
        dismissActionOverlay()
        DispatchQueue.main.async {
            projectIDPendingDelete = projectID
        }
    }

    private func deletePendingProject() {
        guard let projectID = projectIDPendingDelete,
              let project = projects.first(where: { $0.id == projectID }) else {
            projectIDPendingDelete = nil
            return
        }

        #if os(iOS)
        PhotoStore.deleteProjectDirectory(projectID: project.id)
        #endif

        path.removeAll { $0.projectID == project.id }
        modelContext.delete(project)
        try? modelContext.save()
        activeProjectID = nil
        projectIDPendingDelete = nil
    }

    struct Route: Hashable {
        enum Kind: Hashable {
            case detail
        }

        let kind: Kind
        let projectID: UUID
    }

    private func openReminderSettings() {
        guard let project = activeProject else { return }
        dismissActionOverlay()
        reminderProjectID = project.id
        DispatchQueue.main.async {
            isReminderPresented = true
        }
    }
}

private struct ProjectRowView: View {
    let project: Project
    let isActive: Bool
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text("Streak \(String(project.currentStreak))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .matchedGeometryEffect(id: project.id, in: namespace)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(isActive ? 0.26 : 0.18),
                                    .white.opacity(0.05),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(isActive ? 0.30 : 0.16), lineWidth: 1)
                .shadow(color: .white.opacity(isActive ? 0.20 : 0.10), radius: isActive ? 10 : 6, x: 0, y: 0)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.black.opacity(0.10), lineWidth: 1)
                .blur(radius: 6)
                .offset(y: 4)
                .mask(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.linearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)))
        }
        .shadow(color: .black.opacity(isActive ? 0.14 : 0.08), radius: isActive ? 18 : 12, x: 0, y: isActive ? 10 : 6)
        .scaleEffect(isActive ? 1.02 : 1)
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.86, blendDuration: 0.12), value: isActive)
    }
}

private struct ProjectRowButton: View {
    let project: Project
    let isActive: Bool
    let isOverlayVisible: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onChevronTap: () -> Void
    @State private var didLongPress = false

    var body: some View {
        ProjectRowView(project: project, isActive: isActive, namespace: namespace)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onTapGesture {
                if !didLongPress {
                    onTap()
                }
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        didLongPress = true
                        onLongPress()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            didLongPress = false
                        }
                    }
            )
            .overlay(alignment: .trailing) {
                Color.black.opacity(0.001)
                    .frame(width: 56)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture()
                            .onEnded { onChevronTap() }
                    )
            }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .opacity(isActive && isOverlayVisible ? 0 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ProjectCardFrameKey.self, value: [project.id: proxy.frame(in: .global)])
            }
        }
    }
}

private struct ProjectCardFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct ProjectActionOverlay: View {
    let project: Project
    let cardRect: CGRect
    let containerSize: CGSize
    let progress: CGFloat
    let mode: ProjectListView.OverlayMode
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    let onCamera: () -> Void
    let onDetail: () -> Void
    let onReminder: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let center = CGPoint(x: containerSize.width * 0.5, y: containerSize.height * 0.44)

        ZStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.20 * progress)
                Color.black.opacity(0.20 * progress)
            }
            .ignoresSafeArea()

            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            ProjectCenterCapsule(project: project, namespace: namespace, maxWidth: containerSize.width - 120)
                .position(x: center.x, y: center.y)
                .scaleEffect(0.94 + 0.06 * progress)
                .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 16)
                .onTapGesture {}

            radialMenu(center: center)
                .allowsHitTesting(progress > 0.9)
        }
    }

    private func radialMenu(center: CGPoint) -> some View {
        let y = min(78, containerSize.height * 0.11) * 0.72
        let yCTA = y * 2.05

        let items: [(String, String, ButtonRole?, CGVector, Bool, () -> Void)]
        switch mode {
        case .quick:
            items = [
                ("删除项目", "trash.fill", .destructive, .init(dx: 0, dy: -y), false, onDelete),
                ("提醒设置", "bell.badge.fill", nil, .init(dx: 0, dy: y), false, onReminder),
                ("拍照", "camera.fill", nil, .init(dx: 0, dy: yCTA), true, onCamera)
            ]
        case .edit:
            items = [
                ("编辑名字", "pencil", nil, .init(dx: 0, dy: -y), false, onRename),
                ("删除项目", "trash.fill", .destructive, .init(dx: 0, dy: y), false, onDelete)
            ]
        }

        return ZStack {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                ProjectActionCard(
                    title: item.0,
                    systemImage: item.1,
                    role: item.2,
                    isCTA: item.4,
                    action: item.5
                )
                .position(x: center.x, y: center.y)
                .offset(x: item.3.dx * progress, y: item.3.dy * progress)
                .opacity(Double(progress) * (item.4 ? 1 : 0.92))
                .scaleEffect((item.4 ? 0.94 : 0.95) + (item.4 ? 0.06 : 0.05) * progress)
                .animation(
                    .interactiveSpring(response: 0.50, dampingFraction: 0.84, blendDuration: 0.12)
                        .delay(0.03 * Double(index) + (item.4 ? 0.06 : 0)),
                    value: progress
                )
            }
        }
    }
}

private struct ProjectActionCard: View {
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let isCTA: Bool
    let action: () -> Void

    @State private var isPressed = false
    @State private var isBreathing = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(role == .destructive ? .red : .primary)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(role == .destructive ? .red : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 15)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(isCTA ? 0.38 : 0.18),
                                        .white.opacity(isCTA ? 0.16 : 0.06),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(isPressed ? 0.44 : (isCTA ? 0.30 : 0.22)), lineWidth: 1)
                    .shadow(color: .white.opacity(isCTA ? 0.18 : 0.14), radius: isCTA ? 12 : 10, x: 0, y: 0)
                    .clipShape(Capsule(style: .continuous))
            }
            .shadow(color: .white.opacity(isCTA ? 0.16 : 0), radius: isCTA ? 18 : 0, x: 0, y: 0)
            .shadow(color: .white.opacity(isCTA ? 0.07 : 0), radius: isCTA ? 64 : 0, x: 0, y: 0)
            .shadow(color: .black.opacity(0.16), radius: isCTA ? 24 : 18, x: 0, y: isCTA ? 16 : 14)
            .scaleEffect(isPressed ? 0.98 : (isCTA ? (1.16 * (isBreathing ? 1.012 : 1)) : 1))
        }
        .buttonStyle(.plain)
        .onAppear {
            guard isCTA else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .pressEvents(onPress: {
            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.78, blendDuration: 0.12)) {
                isPressed = true
            }
        }, onRelease: {
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.80, blendDuration: 0.12)) {
                isPressed = false
            }
        })
    }
}

private struct ProjectCenterCapsule: View {
    let project: Project
    let namespace: Namespace.ID
    let maxWidth: CGFloat

    var body: some View {
        Text(project.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: min(110, max(90, maxWidth)), height: 44)
            .matchedGeometryEffect(id: project.id, in: namespace)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.26),
                                        .white.opacity(0.06),
                                        .clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
                    .shadow(color: .white.opacity(0.12), radius: 8, x: 0, y: 0)
                    .clipShape(Capsule(style: .continuous))
            }
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
    }
}

private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventsModifier(onPress: onPress, onRelease: onRelease))
    }
}

private struct PressEventsModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPress()
                        }
                    }
                    .onEnded { _ in
                        if isPressed {
                            isPressed = false
                            onRelease()
                        }
                    }
            )
    }
}
