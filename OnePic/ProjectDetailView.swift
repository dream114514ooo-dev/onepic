import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct ProjectDetailView: View {
    let project: Project

#if os(iOS)
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
        ScrollView {
            VStack(spacing: 16) {
                NavigationLink(destination: CameraCaptureView(project: project)) {
                    Text("拍照")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

#if os(iOS)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(photos) { photo in
                        PhotoThumbnailView(relativePath: photo.relativePath)
                            .aspectRatio(1, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
#else
                Text("This view is available on iPhone only.")
                    .foregroundStyle(.secondary)
#endif
            }
            .padding(.top, 16)
        }
        .navigationTitle(project.name)
        .scrollContentBackground(.hidden)
        .background(Color.white)
    }
}

#if os(iOS)
private struct PhotoThumbnailView: View {
    let relativePath: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
            }
        }
        .task(id: relativePath) {
            image = PhotoStore.loadImage(relativePath: relativePath)
        }
    }
}
#endif
