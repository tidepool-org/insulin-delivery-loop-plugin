//
//  Date+DaysLater.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 2/20/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit

public extension Date {
    enum Error: LocalizedError {
        case problemCalculatingDaysLater(String)
        case badInputs(String)
        case problemCalculatingDaysLaterAtTime(String)
        
        public var errorDescription: String? {
            switch self {
            case .problemCalculatingDaysLater(let str),
                    .badInputs(let str),
                    .problemCalculatingDaysLaterAtTime(let str):
                return str
            }
        }
    }
    
    func next(daysLater: Int, at time: DateComponents? = nil) throws -> Date {
        guard let thisDateDaysLater = Calendar.current.date(byAdding: .day, value: daysLater, to: self, wrappingComponents: false) else {
            throw Error.problemCalculatingDaysLater("Could not calculate \(daysLater) days from \(description(with: .current))")
        }
        guard let time = time else {
            return thisDateDaysLater
        }
        guard let hour = time.hour, let minute = time.minute else {
            throw Error.badInputs("Hour or minute missing from \(time)")
        }
        guard let thisDateDaysLaterAtTime = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: thisDateDaysLater) else {
            throw Error.problemCalculatingDaysLaterAtTime("Could not calculate new date and time \(time) from \(thisDateDaysLater.description(with: .current))")
        }
        return thisDateDaysLaterAtTime
    }

}
