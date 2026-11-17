import SwiftUI

struct SourceList: View {
    @Environment(Library.self) private var library

    var body: some View {
        List(library.sources) { source in
            NavigationLink(value: source) {
                LabeledContent(source.title, value: source.count.formatted())
            }
        }
        .navigationTitle("Choose Photos")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { DeleteButton() }
        }
        .onAppear { library.loadSources() }
    }
}
