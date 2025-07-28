//
//  TimeView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct TimeView: View {

    @State private var currentDate = Date()

    let timeOffset: TimeInterval

    let timeZone: TimeZone

    private let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var timeToDisplay: Date {
        currentDate.addingTimeInterval(timeOffset)
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var timeZoneString: String {
        shortTimeFormatter.timeZone = timeZone
        return shortTimeFormatter.string(from: timeToDisplay)
    }

    var body: some View {
        Text(timeZoneString).onReceive(timer) { input in
            currentDate = input
        }
    }
}

struct TimeView_Previews: PreviewProvider {
    static var previews: some View {
        TimeView(timeOffset: 0, timeZone: .current)
    }
}
