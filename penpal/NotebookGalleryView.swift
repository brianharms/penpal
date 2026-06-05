import SwiftUI

struct NotebookGalleryView: View {
    @ObservedObject var store: NotebookStore
    var onSelectNotebook: (Notebook) -> Void

    @State private var editingNotebook: Notebook?
    @State private var newName: String = ""
    @State private var showingDeleteConfirm = false
    @State private var notebookToDelete: Notebook?

    let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Notebooks")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 60)
                    .padding(.bottom, 24)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 28) {
                        // New notebook button
                        Button(action: createNewNotebook) {
                            VStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                        .aspectRatio(3.0/4.0, contentMode: .fit)

                                    Image(systemName: "plus")
                                        .font(.system(size: 40, weight: .light))
                                        .foregroundColor(.white.opacity(0.6))
                                }

                                Text("New Notebook")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        // Existing notebooks
                        ForEach(store.notebooks) { notebook in
                            NotebookCard(
                                notebook: notebook,
                                isSelected: false,
                                onTap: { onSelectNotebook(notebook) },
                                onRename: { startRenaming(notebook) },
                                onDelete: { confirmDelete(notebook) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(item: $editingNotebook) { notebook in
            RenameSheet(
                notebook: notebook,
                newName: $newName,
                onSave: { saveRename(notebook) },
                onCancel: { editingNotebook = nil }
            )
        }
        .alert("Delete Notebook?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let notebook = notebookToDelete {
                    store.delete(notebook)
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func createNewNotebook() {
        let notebook = store.createNotebook(name: "Notebook \(store.notebooks.count + 1)")
        onSelectNotebook(notebook)
    }

    private func startRenaming(_ notebook: Notebook) {
        newName = notebook.name
        editingNotebook = notebook
    }

    private func saveRename(_ notebook: Notebook) {
        store.rename(notebook, to: newName)
        editingNotebook = nil
    }

    private func confirmDelete(_ notebook: Notebook) {
        notebookToDelete = notebook
        showingDeleteConfirm = true
    }
}

struct NotebookCard: View {
    let notebook: Notebook
    let isSelected: Bool
    let onTap: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .aspectRatio(3.0/4.0, contentMode: .fit)

                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(4)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.3))
                }

                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 3)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(notebook.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(formatDate(notebook.modifiedAt))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Menu {
                    Button(action: onRename) {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = notebook.generateThumbnail()
            DispatchQueue.main.async {
                self.thumbnail = image
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct RenameSheet: View {
    let notebook: Notebook
    @Binding var newName: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                TextField("Notebook Name", text: $newName)
            }
            .navigationTitle("Rename Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(newName.isEmpty)
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}
