//
//  ReservoirHUDViewModelTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Rick Pasetto on 3/25/22.
//  Copyright © 2022 Tidepool Project. All rights reserved.
//

import XCTest
import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class ReservoirHUDViewModelTests: XCTestCase {

    var viewModel: ReservoirHUDViewModel!
    
    override func setUpWithError() throws {
        viewModel = ReservoirHUDViewModel(userThreshold: Double(PumpConfiguration.defaultConfiguration.reservoirLevelWarningThresholdInUnits))
    }

    func testInit() throws {
        XCTAssertEqual(.full, viewModel.imageType)
        XCTAssertNil(viewModel.warningColor)
    }
    
    func testNoWarningAboveDefaultThreshold() throws {
        viewModel.reservoirLevel = 20.nextUp // U
        XCTAssertEqual(.open, viewModel.imageType)
        XCTAssertEqual(.normal, viewModel.warningColor)
    }

    func testWarningBelowDefaultThreshold() throws {
        viewModel.reservoirLevel = 20.nextDown // U
        XCTAssertEqual(.open, viewModel.imageType)
        XCTAssertEqual(.warning, viewModel.warningColor)
    }
    
    func testNoWarningAboveUserSetThreshold() throws {
        viewModel.reservoirLevel = 25.nextUp // U
        viewModel.userThreshold = 25 // U
        XCTAssertEqual(.open, viewModel.imageType)
        XCTAssertEqual(.normal, viewModel.warningColor)
    }

    func testWarningBelowUserSetThreshold() throws {
        viewModel.reservoirLevel = 25.nextDown // U
        viewModel.userThreshold = 25 // U
        XCTAssertEqual(.open, viewModel.imageType)
        XCTAssertEqual(.warning, viewModel.warningColor)
    }
    
    func testWarningBelowUserSetThresholdLowerThan10() throws {
        viewModel.reservoirLevel = 9 // U
        viewModel.userThreshold = 5 // U
        XCTAssertEqual(.open, viewModel.imageType)
        XCTAssertEqual(.warning, viewModel.warningColor)
    }
    
    func testErrorAtZero() throws {
        viewModel.reservoirLevel = 0 // U
        XCTAssertEqual(.open, viewModel.imageType)
        XCTAssertEqual(.error, viewModel.warningColor)
    }
    
    func testFullNormalAtAccuracyLimit() throws {
        viewModel.reservoirLevel = 50 // U
        XCTAssertEqual(.full, viewModel.imageType)
        XCTAssertEqual(.normal, viewModel.warningColor)
    }
    
    func testFullNormalAboveAccuracyLimit() throws {
        viewModel.reservoirLevel = 50.nextUp // U
        XCTAssertEqual(.full, viewModel.imageType)
        XCTAssertEqual(.normal, viewModel.warningColor)
    }
}
