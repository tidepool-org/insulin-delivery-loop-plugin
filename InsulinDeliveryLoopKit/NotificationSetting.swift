//
//  NotificationSetting.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 2/16/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

public struct NotificationSetting: Codable, Equatable {
    static var `default`: NotificationSetting { NotificationSetting() }
    
    public var isEnabled: Bool
    public var repeatDays: Int
    public struct TimeOfDay: Codable, Equatable {
        let hour: Int
        let minute: Int
    }
    public var timeOfDay: TimeOfDay
    public enum Error: Swift.Error {
        case invalidTimeOfDay
    }
    
    public init() {
        try! self.init(isEnabled: false, repeatDays: 1, timeOfDay: TimeOfDay(hour: 12, minute: 0))
    }
    
    public init(isEnabled: Bool, repeatDays: Int, timeOfDay: TimeOfDay) throws {
        self.isEnabled = isEnabled
        self.repeatDays = repeatDays
        self.timeOfDay = timeOfDay
    }
}
 
extension NotificationSetting: RawRepresentable {
    private enum NotificationSettingKey: String {
        case isEnabled
        case repeatDays
        case timeOfDay
    }

    public typealias RawValue =  [String: Any]
    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        rawValue[NotificationSettingKey.isEnabled.rawValue] = isEnabled
        rawValue[NotificationSettingKey.repeatDays.rawValue] = repeatDays
        rawValue[NotificationSettingKey.timeOfDay.rawValue] = timeOfDay.rawValue
        return rawValue
    }
    
    public init?(rawValue: RawValue) {
        guard let isEnabled = rawValue[NotificationSettingKey.isEnabled.rawValue] as? Bool,
              let repeatDays = rawValue[NotificationSettingKey.repeatDays.rawValue] as? Int,
              let rawTimeOfDay = rawValue[NotificationSettingKey.timeOfDay.rawValue] as? RawValue,
              let timeOfDay = TimeOfDay(rawValue: rawTimeOfDay) else {
                  return nil
              }
        self.isEnabled = isEnabled
        self.repeatDays = repeatDays
        self.timeOfDay = timeOfDay
    }
}

extension NotificationSetting.TimeOfDay: RawRepresentable {
    private enum TimeOfDayKey: String {
        case hour
        case minute
    }

    public typealias RawValue =  [String: Any]
    public var rawValue: RawValue {
        var rawValue: RawValue = [:]
        rawValue[TimeOfDayKey.hour.rawValue] = hour
        rawValue[TimeOfDayKey.minute.rawValue] = minute
        return rawValue
    }
    
    public init?(rawValue: RawValue) {
        guard let hour = rawValue[TimeOfDayKey.hour.rawValue] as? Int,
              let minute = rawValue[TimeOfDayKey.minute.rawValue] as? Int else {
                  return nil
              }
        self.hour = hour
        self.minute = minute
    }
}

extension NotificationSetting.TimeOfDay {
    public var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }
    public func date(calendar: Calendar = Calendar.current) -> Date? {
        calendar.date(from: dateComponents)
    }
    public init?(from dateComponents: DateComponents) {
        guard let hour = dateComponents.hour, let minute = dateComponents.minute else {
            return nil
        }
        self.init(hour: hour, minute: minute)
    }
    public init(from date: Date, calendar: Calendar = Calendar.current) {
        self.init(from: calendar.dateComponents([.hour, .minute], from: date))!
    }
}
