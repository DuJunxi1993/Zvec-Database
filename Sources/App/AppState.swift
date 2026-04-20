import Foundation
import Combine

class AppState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var zoomLevel: Double = 1.0
    @Published var isFullScreen: Bool = false
    @Published var shouldShowFilePicker: Bool = false

    func jumpToTab(_ tab: Int) {
        selectedTab = tab
    }
}
