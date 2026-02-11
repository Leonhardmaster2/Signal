import WidgetKit
import SwiftUI

@main
struct SignalWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        SignalRecordingLiveActivity()
    }
}
