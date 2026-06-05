import SwiftUI

@main
struct penpalApp: App {
    @StateObject private var notebookStore = NotebookStore()
    @State private var selectedNotebook: Notebook?

    var body: some Scene {
        WindowGroup {
            Group {
                if let notebook = selectedNotebook {
                    ContentView(
                        notebook: notebook,
                        notebookStore: notebookStore,
                        onBack: {
                            notebookStore.loadNotebooks()
                            selectedNotebook = nil
                        }
                    )
                    .ignoresSafeArea()
                    .id(notebook.id)
                } else {
                    NotebookGalleryView(
                        store: notebookStore,
                        onSelectNotebook: { notebook in
                            selectedNotebook = notebook
                        }
                    )
                    .ignoresSafeArea()
                }
            }
            .onOpenURL { url in
                // Route to PKCE handler (code=) or App Remote handler (access_token=)
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let hasCode = components?.queryItems?.contains(where: { $0.name == "code" }) ?? false
                if hasCode {
                    Task { await SpotifyService.shared.handleCallback(url: url) }
                } else {
                    SpotifyService.shared.handleAppRemoteURL(url)
                }
            }
        }
    }
}
