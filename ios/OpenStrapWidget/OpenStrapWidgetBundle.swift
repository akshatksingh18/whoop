//
//  OpenStrapWidgetBundle.swift
//  OpenStrapWidget
//
//  Created by Abdul Sahil - garden on 12/06/26.
//

import WidgetKit
import SwiftUI

@main
struct OpenStrapWidgetBundle: WidgetBundle {
    var body: some Widget {
        #if !PERSONAL_SIDELOAD
        OpenStrapWidget()
        OpenStrapSleepWidget()
        OpenStrapOvernightWidget()
        OpenStrapBatteryWidget()
        #endif
        OpenStrapWidgetLiveActivity()
        #if !PERSONAL_SIDELOAD
        OpenStrapBreathingLiveActivity()
        #endif
    }
}
