//
//  MuteWarningsSettingsEditViewModelTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Nathaniel Hamming on 2021-10-25.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import XCTest
@testable import InsulinDeliveryLoopKitUI

class MuteWarningsSettingsEditViewModelTests: XCTestCase {

    func testUpdateTimesToToday() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startTime = Date().addingTimeInterval(-.days(1))
        let endTime = Date().addingTimeInterval(-.days(1)+30) //end time should be different from the start time (that is tested below)
        let viewModel = MuteWarningsSettingsEditViewModel(enabled: false, startTime: startTime, endTime: endTime, dailyFrequency: false)
        viewModel.updateTimesToToday()
        XCTAssertNotEqual(viewModel.startTime, startTime)
        XCTAssertNotEqual(viewModel.endTime, endTime)
        XCTAssertEqual(Calendar.current.startOfDay(for: viewModel.startTime), startOfToday)
        XCTAssertEqual(Calendar.current.startOfDay(for: viewModel.endTime), startOfToday)
    }

    func testUpdateTimesToTodayEndTimeEqualsStartTime() {
        let now = Date()
        let startTime = now
        let endTime = now
        let viewModel = MuteWarningsSettingsEditViewModel(enabled: false, startTime: startTime, endTime: endTime, dailyFrequency: false)
        viewModel.updateTimesToToday()
        XCTAssertEqual(viewModel.startTime, now)
        XCTAssertEqual(viewModel.endTime, now.addingTimeInterval(.days(1)))
    }
}
