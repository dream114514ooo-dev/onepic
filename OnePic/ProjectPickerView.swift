import SwiftUI
import SwiftData

struct ProjectPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loc: LocalizationManager

    let projects: [Project]
    @Binding var selectedProjectID: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(projects) { project in
                        Button {
                            selectedProjectID = project.id.uuidString
                            project.lastOpenedAt = Date()
                            dismiss()
                        } label: {
                            HStack {
                                Text(project.name)
                                Spacer()
                                if selectedProjectID == project.id.uuidString {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Button {
                        createProject()
                    } label: {
                        Label(loc.t("project.new"), systemImage: "plus")
                    }
                    .disabled(!canCreateProject)
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle(loc.t("home.title"))
            .toolbar {
                ToolbarItem { Button(loc.t("common.done")) { dismiss() } }
            }
        }
    }

    private var canCreateProject: Bool {
        VIP.isVIP || projects.count < VIP.maxFreeProjects
    }

    private func createProject() {
        let name = loc.tf("project.default_name_format", projects.count + 1)
        let project = Project(name: name, lastOpenedAt: Date())
        modelContext.insert(project)
        selectedProjectID = project.id.uuidString
        dismiss()
    }
}
