import AVFoundation
import Photos
import SwiftUI

@main
struct SiftApp: App {
    @State private var library = Library()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active { library.save() }
        }
    }
}

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL

    var body: some View {
        switch library.status {
        case .authorized, .limited:
            NavigationStack {
                SourceList()
                    .navigationDestination(for: Source.self) { DeckView(source: $0) }
            }
            .alert("Couldn't Delete", isPresented: Binding(
                get: { library.deleteError != nil },
                set: { if !$0 { library.deleteError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(library.deleteError ?? "")
            }
        case .notDetermined:
            ProgressView()
                .task { await library.requestAccess() }
        default:
            ContentUnavailableView {
                Label("No Photo Access", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Allow access to your photos in Settings to start sorting.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct DeleteButton: View {
    @Environment(Library.self) private var library
    var reopen: Source?
    var prominent = false

    var body: some View {
        if library.pendingDeletes > 0 {
            let button = Button(role: .destructive) {
                Task { await library.commitDeletes(then: reopen) }
            } label: {
                Label("Delete \(library.pendingDeletes)", systemImage: "trash")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(library.isDeleting)
            if prominent {
                button.buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            } else {
                button.tint(.red)
            }
        }
    }
}
