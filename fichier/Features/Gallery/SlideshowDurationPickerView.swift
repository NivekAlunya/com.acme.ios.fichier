//
//  SlideshowDurationPickerView.swift
//  fichier
//

import SwiftUI

/// Reusable picker view for configuring slideshow slide durations.
struct SlideshowDurationPickerView: View {
    @Binding var selection: Double

    var body: some View {
        Picker(.Strings.slideshowSectionSlideDuration, selection: $selection) {
            Text(.Strings.slideshowDurationTwoSeconds).tag(2.0)
            Text(.Strings.slideshowDurationThreeSeconds).tag(3.0)
            Text(.Strings.slideshowDurationFiveSeconds).tag(5.0)
            Text(.Strings.slideshowDurationTenSeconds).tag(10.0)
            Text(.Strings.slideshowDurationFifteenSeconds).tag(15.0)
            Text(.Strings.slideshowDurationThirtySeconds).tag(30.0)
        }
    }
}
