import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.lastOpenedAt, order: .reverse) private var projects: [Project]

    @AppStorage("onepic_pendingDetailProjectID") private var pendingDetailProjectID = ""
    @AppStorage("onepic_pendingDetailNonce") private var pendingDetailNonce = 0

    @State private var didBootstrap = false
    @State private var activeProjectID: UUID?
    @State private var isActionPresented = false
    @State private var path: [Route] = []
    @State private var isCameraPresented = false
    @State private var cameraProjectID: UUID?
    @State private var errorMessage: String?
    @State private var isRenamePresented = false
    @State private var renameDraft = ""
    @State private var projectIDPendingDelete: UUID?
    @State private var reminderProjectID: UUID?
    @State private var isReminderPresented = false

    var body: some View {
#if os(iOS)
        NavigationStack(path: $path) {
            List {
                ForEach(projects) { project in
                    ProjectRowButton(project: project) {
                        activeProjectID = project.id
                        isActionPresented = true
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
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
            .confirmationDialog(activeProject?.name ?? "", isPresented: $isActionPresented, titleVisibility: .visible) {
                Button("拍照") { openCamera() }
                Button("查看项目") { openDetail() }
                Button("提醒设置") { openReminderSettings() }
                Button("更改名字") { beginRename() }
                Button("删除项目", role: .destructive) { beginDeleteProject() }
                Button("取消", role: .cancel) {}
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

    private func openCamera() {
        guard let project = activeProject else { return }
        project.lastOpenedAt = Date()
        isActionPresented = false
        cameraProjectID = project.id
        DispatchQueue.main.async {
            isCameraPresented = true
        }
    }

    private func openDetail() {
        guard let project = activeProject else { return }
        project.lastOpenedAt = Date()
        isActionPresented = false
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
        isActionPresented = false
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
        isActionPresented = false
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
        isActionPresented = false
        reminderProjectID = project.id
        DispatchQueue.main.async {
            isReminderPresented = true
        }
    }
}

private struct ProjectRowView: View {
    let project: Project

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
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

private struct ProjectRowButton: View {
    let project: Project
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProjectRowView(project: project)
        }
        .buttonStyle(PlainButtonStyle())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}
