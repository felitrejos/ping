#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct PingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PingLiveActivityWidget()
    }
}
#endif
