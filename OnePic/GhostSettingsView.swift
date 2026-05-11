import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#endif

struct GhostSettingsView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Query private var photos: [Photo]
    @State private var isOpacityPresented = false

    init(project: Project) {
        self.project = project
        let projectID: UUID? = project.id
        _photos = Query(
            filter: #Predicate<Photo> { $0.projectID == projectID },
            sort: [SortDescriptor(\Photo.shotAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { project.ghostEnabled }, set: { project.ghostEnabled = $0 })) {
                        Text("叠加")
                    }
                }

                Section {
                    Button {
                        project.ghostEnabled = false
                        project.ghostPhotoID = nil
                    } label: {
                        HStack {
                            Text("关闭叠加")
                            Spacer()
                            if !project.ghostEnabled {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(.primary)

                    Button {
                        project.ghostEnabled = true
                        project.ghostPhotoID = nil
                    } label: {
                        HStack {
                            Text("使用最新一张")
                            Spacer()
                            if project.ghostEnabled, project.ghostPhotoID == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(photos) { photo in
                                GhostThumbnailCell(
                                    relativePath: photo.relativePath,
                                    isSelected: project.ghostEnabled && project.ghostPhotoID == photo.id
                                )
                                .onTapGesture {
                                    project.ghostEnabled = true
                                    project.ghostPhotoID = photo.id
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("选择叠加照片")
                }

                Section {
                    Button {
                        isOpacityPresented = true
                    } label: {
                        HStack {
                            Text("调整透明度")
                            Spacer()
                            Text("\(Int(project.ghostOpacity * 100))%")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("叠加设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem { Button("完成") { dismiss() } }
            }
            .sheet(isPresented: $isOpacityPresented) {
                GhostOpacitySheet(opacity: Binding(get: { project.ghostOpacity }, set: { project.ghostOpacity = $0 }))
                    #if os(iOS)
                    .presentationDetents([.height(220)])
                    #endif
            }
        }
    }
}

private struct GhostThumbnailCell: View {
    let relativePath: String
    let isSelected: Bool
#if os(iOS)
    @State private var image: UIImage?
#endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
#if os(iOS)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                }
#else
                Rectangle()
                    .fill(Color.black.opacity(0.06))
#endif
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .padding(6)
            }
        }
#if os(iOS)
        .task(id: relativePath) {
            image = PhotoStore.loadImage(relativePath: relativePath)
        }
#endif
    }
}

private struct GhostOpacitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var opacity: Double

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Slider(value: $opacity, in: 0...1)
                Text("\(Int(opacity * 100))%")
                    .font(.headline)
            }
            .padding(18)
            .navigationTitle("透明度")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem { Button("完成") { dismiss() } }
            }
        }
    }
}
