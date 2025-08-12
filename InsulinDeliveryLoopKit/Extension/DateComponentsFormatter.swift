//
//  DateComponentsFormatter.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 4/22/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

extension DateComponentsFormatter {
    /// This is a formatter for use when displaying how long until expiration of something (e.g. a component) with only one unit.
    /// (e.g. "10 days", "3 hours", "5 minutes", etc.)
    static let expirationTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter
    }()
}
