import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            DocumentImportView()
                .environmentObject(appState)
                .tabItem {
                    Label("导入", systemImage: "doc.badge.plus")
                }
                .tag(0)

            KnowledgeBaseListView()
                .tabItem {
                    Label("知识库", systemImage: "books.vertical")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
                .tag(2)

            MCPSettingsView()
                .tabItem {
                    Label("MCP", systemImage: "server.rack")
                }
                .tag(3)
        }
        .frame(minWidth: 900, minHeight: 600)
        .scaleEffect(appState.zoomLevel)
        .onReceive(appState.$shouldShowFilePicker.filter { $0 }) { _ in
            appState.shouldShowFilePicker = false
        }
    }
}

#Preview {
    ContentView()
}
