//
//  DateTests.swift
//  CoastalPumpKitTests
//
//  Created by Nathaniel Hamming on 2020-04-21.
//  Copyright © 2020 Tidepool Project. All rights reserved.
//

import XCTest
import CoreBluetooth
@testable import CoastalPumpKit

class DateTests: XCTestCase {
    func testGATTDateTime() {
        // these components are considered to be in UTC
        let year: UInt16 = 2023
        let month: UInt8 = 4
        let day: UInt8 = 21
        let hour: UInt8 = 10
        let minute: UInt8 = 30
        let second: UInt8 = 15
        var calendar = Calendar.current
        calendar.timeZone = .currentFixed
        
        // GATT Date Time is always in UTC
        let expectedHour = Int(hour) - Int(TimeInterval(seconds: TimeZone.currentFixed.secondsFromGMT()).hours)
        
        let dateComponents = DateComponents(year: Int(year),
                                            month: Int(month),
                                            day: Int(day),
                                            hour: Int(hour),
                                            minute: Int(minute),
                                            second: Int(second))
        
        let date = calendar.date(from: dateComponents)!
        let gattDateTime = date.gattDateTime()
        
        var index = 0
        XCTAssertEqual(gattDateTime[gattDateTime.startIndex.advanced(by: index)...].to(UInt16.self), year)
        index += 2
        XCTAssertEqual(gattDateTime[gattDateTime.startIndex.advanced(by: index)...].to(UInt8.self), month)
        index += 1
        XCTAssertEqual(gattDateTime[gattDateTime.startIndex.advanced(by: index)...].to(UInt8.self), day)
        index += 1
        XCTAssertEqual(gattDateTime[gattDateTime.startIndex.advanced(by: index)...].to(UInt8.self), UInt8(expectedHour))
        index += 1
        XCTAssertEqual(gattDateTime[gattDateTime.startIndex.advanced(by: index)...].to(UInt8.self), minute)
        index += 1
        XCTAssertEqual(gattDateTime[gattDateTime.startIndex.advanced(by: index)...].to(UInt8.self), second)
    }
    
    func testInitFromGATTDateTime() {
        let year: UInt16 = 2020
        let month: UInt8 = 4
        let invalidMonth: UInt8 = 0
        let day: UInt8 = 21
        let invalidDay: UInt8 = 0
        let hour: UInt8 = 10
        let invalidHour: UInt8 = 99
        let minute: UInt8 = 30
        let invalidMinute: UInt8 = 99
        let second: UInt8 = 15
        let invalidSecond: UInt8 = 99
        
        let timeZone = TimeZone.currentFixed
        
        var invalidGATTDateTimeMonth = Data(year)
        invalidGATTDateTimeMonth.append(invalidMonth)
        invalidGATTDateTimeMonth.append(day)
        invalidGATTDateTimeMonth.append(hour)
        invalidGATTDateTimeMonth.append(minute)
        invalidGATTDateTimeMonth.append(second)
        XCTAssertNil(Date(gattDateTime: invalidGATTDateTimeMonth, timeZone: timeZone))
        
        var invalidGATTDateTimeDay = Data(year)
        invalidGATTDateTimeDay.append(month)
        invalidGATTDateTimeDay.append(invalidDay)
        invalidGATTDateTimeDay.append(hour)
        invalidGATTDateTimeDay.append(minute)
        invalidGATTDateTimeDay.append(second)
        XCTAssertNil(Date(gattDateTime: invalidGATTDateTimeDay, timeZone: timeZone))
        
        var invalidGATTDateTimeHour = Data(year)
        invalidGATTDateTimeHour.append(month)
        invalidGATTDateTimeHour.append(day)
        invalidGATTDateTimeHour.append(invalidHour)
        invalidGATTDateTimeHour.append(minute)
        invalidGATTDateTimeHour.append(second)
        XCTAssertNil(Date(gattDateTime: invalidGATTDateTimeHour, timeZone: timeZone))
        
        var invalidGATTDateTimeMinute = Data(year)
        invalidGATTDateTimeMinute.append(month)
        invalidGATTDateTimeMinute.append(day)
        invalidGATTDateTimeMinute.append(hour)
        invalidGATTDateTimeMinute.append(invalidMinute)
        invalidGATTDateTimeMinute.append(second)
        XCTAssertNil(Date(gattDateTime: invalidGATTDateTimeMinute, timeZone: timeZone))
        
        var invalidGATTDateTimeSecond = Data(year)
        invalidGATTDateTimeSecond.append(month)
        invalidGATTDateTimeSecond.append(day)
        invalidGATTDateTimeSecond.append(hour)
        invalidGATTDateTimeSecond.append(minute)
        invalidGATTDateTimeSecond.append(invalidSecond)
        XCTAssertNil(Date(gattDateTime: invalidGATTDateTimeSecond, timeZone: timeZone))
        
        var gattDateTime = Data(year)
        gattDateTime.append(month)
        gattDateTime.append(day)
        gattDateTime.append(hour)
        gattDateTime.append(minute)
        gattDateTime.append(second)
        let date = Date(gattDateTime: gattDateTime, timeZone: timeZone)
        
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        XCTAssertNotNil(date)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date!), DateComponents(year: Int(year), month: Int(month), day: Int(day), hour: Int(hour), minute: Int(minute), second: Int(second)))
    }
}
