import WidgetKit
import SwiftUI

@main
struct AAPSWidgetBundle: WidgetBundle {
    var body: some Widget {
        GlucoseWidget()
        if #available(iOS 16.1, *) {
            GlucoseLiveActivity()
        }
    }
}
