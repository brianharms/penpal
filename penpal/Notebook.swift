import Foundation
import PencilKit

/// Represents a single notebook/page in the app
struct Notebook: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var drawingData: Data  // PKDrawing encoded as Data
    var lastRespondedStrokeIndex: Int
    var userStrokeCount: Int

    init(name: String = "Untitled", drawing: PKDrawing = PKDrawing()) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.drawingData = drawing.dataRepresentation()
        self.lastRespondedStrokeIndex = 0
        self.userStrokeCount = 0
    }

    var drawing: PKDrawing {
        get {
            (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        }
        set {
            drawingData = newValue.dataRepresentation()
            modifiedAt = Date()
        }
    }

    /// Preview image for gallery (generated on-demand)
    func generateThumbnail(size: CGSize = CGSize(width: 200, height: 267)) -> UIImage? {
        let drawing = self.drawing
        guard !drawing.strokes.isEmpty else { return nil }

        let bounds = drawing.bounds
        let scale = min(size.width / bounds.width, size.height / bounds.height) * 0.8

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Dark background
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Draw the content centered
            let traitCollection = UITraitCollection(userInterfaceStyle: .light)
            traitCollection.performAsCurrent {
                let drawingImage = drawing.image(from: bounds, scale: scale)
                let x = (size.width - drawingImage.size.width) / 2
                let y = (size.height - drawingImage.size.height) / 2
                drawingImage.draw(at: CGPoint(x: x, y: y))
            }
        }
    }
}

/// Manages notebook persistence and listing
@MainActor
class NotebookStore: ObservableObject {
    @Published var notebooks: [Notebook] = []
    @Published var currentNotebook: Notebook?

    private let notebooksKey = "rite_notebooks"
    private let currentNotebookKey = "rite_current_notebook_id"

    init() {
        loadNotebooks()
    }

    /// Get the notebooks directory
    private func getNotebooksDirectory() -> URL? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsDir = paths.first else { return nil }
        let notebooksDir = documentsDir.appendingPathComponent("notebooks")

        // Create directory if needed
        if !FileManager.default.fileExists(atPath: notebooksDir.path) {
            try? FileManager.default.createDirectory(at: notebooksDir, withIntermediateDirectories: true)
        }

        return notebooksDir
    }

    /// Load all notebooks from disk
    func loadNotebooks() {
        guard let notebooksDir = getNotebooksDirectory() else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: notebooksDir, includingPropertiesForKeys: [.contentModificationDateKey])

            var loadedNotebooks: [Notebook] = []
            for file in files where file.pathExtension == "notebook" {
                if let data = try? Data(contentsOf: file),
                   let notebook = try? JSONDecoder().decode(Notebook.self, from: data) {
                    loadedNotebooks.append(notebook)
                }
            }

            // Sort by modified date (most recent first)
            notebooks = loadedNotebooks.sorted { $0.modifiedAt > $1.modifiedAt }

            // Load current notebook
            if let currentId = UserDefaults.standard.string(forKey: currentNotebookKey),
               let uuid = UUID(uuidString: currentId),
               let notebook = notebooks.first(where: { $0.id == uuid }) {
                currentNotebook = notebook
            } else if let first = notebooks.first {
                currentNotebook = first
            }

            print("Loaded \(notebooks.count) notebooks")

        } catch {
            print("Failed to load notebooks: \(error)")
        }
    }

    /// Save a notebook to disk
    func save(_ notebook: Notebook) {
        guard let notebooksDir = getNotebooksDirectory() else { return }

        let fileURL = notebooksDir.appendingPathComponent("\(notebook.id.uuidString).notebook")

        do {
            let data = try JSONEncoder().encode(notebook)
            try data.write(to: fileURL)

            // Update in-memory list
            if let index = notebooks.firstIndex(where: { $0.id == notebook.id }) {
                notebooks[index] = notebook
            } else {
                notebooks.insert(notebook, at: 0)
            }

            // Re-sort by modified date
            notebooks.sort { $0.modifiedAt > $1.modifiedAt }

            print("Saved notebook: \(notebook.name)")

        } catch {
            print("Failed to save notebook: \(error)")
        }
    }

    /// Create a new notebook
    func createNotebook(name: String = "New Notebook") -> Notebook {
        let notebook = Notebook(name: name)
        save(notebook)
        currentNotebook = notebook
        UserDefaults.standard.set(notebook.id.uuidString, forKey: currentNotebookKey)
        return notebook
    }

    /// Delete a notebook
    func delete(_ notebook: Notebook) {
        guard let notebooksDir = getNotebooksDirectory() else { return }

        let fileURL = notebooksDir.appendingPathComponent("\(notebook.id.uuidString).notebook")
        try? FileManager.default.removeItem(at: fileURL)

        notebooks.removeAll { $0.id == notebook.id }

        // If we deleted the current notebook, switch to another
        if currentNotebook?.id == notebook.id {
            currentNotebook = notebooks.first
            if let current = currentNotebook {
                UserDefaults.standard.set(current.id.uuidString, forKey: currentNotebookKey)
            }
        }
    }

    /// Switch to a different notebook
    func switchTo(_ notebook: Notebook) {
        currentNotebook = notebook
        UserDefaults.standard.set(notebook.id.uuidString, forKey: currentNotebookKey)
    }

    /// Update the current notebook with new drawing state
    func updateCurrentNotebook(drawing: PKDrawing, lastRespondedStrokeIndex: Int, userStrokeCount: Int) {
        guard var notebook = currentNotebook else { return }

        notebook.drawing = drawing
        notebook.lastRespondedStrokeIndex = lastRespondedStrokeIndex
        notebook.userStrokeCount = userStrokeCount

        save(notebook)
        currentNotebook = notebook
    }

    /// Rename a notebook
    func rename(_ notebook: Notebook, to newName: String) {
        guard var updatedNotebook = notebooks.first(where: { $0.id == notebook.id }) else { return }
        updatedNotebook.name = newName
        updatedNotebook.modifiedAt = Date()
        save(updatedNotebook)

        if currentNotebook?.id == notebook.id {
            currentNotebook = updatedNotebook
        }
    }
}
