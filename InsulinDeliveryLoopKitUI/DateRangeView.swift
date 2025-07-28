//
//  DateRangeView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct DateRangeView: View {
    
    @Environment(\.guidanceColors) var guidanceColors

    let title: String?
    let startDate: Date?
    let endDate: Date?
    
    private var isExpired: Bool {
        guard let endDate else {
            return false
        }
        
        return endDate < Date()
    }
    
    init(title: String? = nil, startDate: Date?, endDate: Date?) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                HStack {
                    Text(isExpired ? "\(Image(systemName: "exclamationmark.circle.fill"))\u{00A0}" : "") + Text(title)
                }
                .foregroundColor(titleColor)
            }

            Text("\(componentLifetimeText.dateRange)\u{0020}\u{0020}\(Image(systemName: "clock.fill"))\u{00A0}\(componentLifetimeText.time)")
            .font(.footnote)
            .foregroundColor(dateRangeColor)
        }
    }
    
    var titleColor: Color {
        isExpired ? guidanceColors.critical : .primary
    }
    
    var dateRangeColor: Color {
        isExpired ? Color(.systemGray) : .primary
    }
    
    var componentLifetimeText: (dateRange: String, time: String) {
        guard let startDate, let endDate else {
            return ("", "")
        }
        
        return (
            String(
                format: LocalizedString(
                    "From %1$@ to %2$@",
                    comment: "Format for component lifetime"
                ),
                startDate.formatted(date: .abbreviated, time: .omitted),
                endDate.formatted(date: .abbreviated, time: .omitted)
            ),
            endDate.formatted(date: .omitted, time: .shortened)
        )
    }
}

struct DateRangeView_Previews: PreviewProvider {
    static var previews: some View {
        DateRangeView(
            title: LocalizedString("Pump", comment: "Pump label"),
            startDate: Date().addingTimeInterval(-345600),
            endDate: Date().addingTimeInterval(259200)
        )
    }
}
