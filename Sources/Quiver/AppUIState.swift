import Foundation
import Combine

/// Selection state for the main window's sidebar. `nil` selects the General pane.
@MainActor
final class AppUIState: ObservableObject {
    @Published var selectedModuleID: String?
}
