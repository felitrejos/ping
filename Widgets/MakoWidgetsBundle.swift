#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct MakoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MakoLiveActivityWidget()
    }
}
#endif
