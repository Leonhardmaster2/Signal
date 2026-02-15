import WidgetKit
import SwiftUI

@main
struct TraceWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        TraceRecordingLiveActivity()
        TracePlaybackLiveActivity()
    }
}
