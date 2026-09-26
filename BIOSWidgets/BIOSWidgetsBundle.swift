import SwiftUI
import WidgetKit

/// Widget extension of BIOS (at.bene.bios.widgets). Only the Live Activity
/// for now; home screen widgets would be added to this bundle.
@main
struct BIOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BIOSLiveActivity()
    }
}
