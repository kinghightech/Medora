//
//  MedoraWidgetBundle.swift
//  MedoraWidget
//
//  Widget extension entry point for the Medora home screen widget.
//

import WidgetKit
import SwiftUI

@main
struct MedoraWidgetBundle: WidgetBundle {
    var body: some Widget {
        LogSymptomWidget()
    }
}
