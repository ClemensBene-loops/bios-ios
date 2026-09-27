import SwiftUI
import WidgetKit

/// Widget extension of BIOS (at.bene.bios.widgets): the lock screen widgets
/// (rectangular, circular, inline) plus a small home screen widget, and the
/// Live Activity (off by default in the app: it would also sit in the
/// Dynamic Island next to Loop).
@main
struct BIOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BIOSStatusWidget()
        BIOSLiveActivity()
    }
}
