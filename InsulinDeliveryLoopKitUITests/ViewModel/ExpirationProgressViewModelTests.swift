//
//  ExpirationProgressViewModelTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Rick Pasetto on 4/12/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import XCTest
import LoopKit
import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

fileprivate func noExpiredComponentsState( _ now: @escaping () -> Date) -> InsulinDeliveryPumpManagerState {
    return makeExpiredPumpState(timeLeft: nil, now)
}

fileprivate func makeExpiredPumpState(timeLeft: TimeInterval?, _ now: @escaping () -> Date) -> InsulinDeliveryPumpManagerState {
    var state = InsulinDeliveryPumpManagerState.forPreviewsAndTests
    let timeLeft = timeLeft ?? InsulinDeliveryPumpManager.lifespan
    state.replacementWorkflowState.lastPumpReplacementDate = now() - InsulinDeliveryPumpManager.lifespan + timeLeft
    state.pumpState.deviceInformation?.updateExpirationDate(remainingLifetime: timeLeft)
    return state
}

class ExpirationProgressViewModelTests: XCTestCase {
    
    var mockPublisher: MockInsulinDeliveryPumpManagerStatePublisher!
    var now: (() -> Date)!
    var viewModel: ExpirationProgressViewModel!
    
    override func setUpWithError() throws {
        now = { Date() }
        mockPublisher = MockInsulinDeliveryPumpManagerStatePublisher(state: InsulinDeliveryPumpManagerState.forPreviewsAndTests, now: now)
        viewModel = ExpirationProgressViewModel(statePublisher: mockPublisher, now: now)
    }

    override func tearDownWithError() throws { }
    
    func testNotExpired() throws {
        mockPublisher.state = noExpiredComponentsState(now)
        XCTAssertNil(viewModel.expirationProgress)
    }
    
    func testExpired() throws {
        mockPublisher.state = makeExpiredPumpState(timeLeft: 0.0, now)
        XCTAssertEqual(ComponentLifecycleProgress(percentComplete: 1.0, progressState: .critical), ComponentLifecycleProgress(viewModel.expirationProgress))
    }
    
    func testNearExpired() throws {
        mockPublisher.state = makeExpiredPumpState(timeLeft: .hours(1), now)
        XCTAssertEqual(.warning, ComponentLifecycleProgress(viewModel.expirationProgress)?.progressState)
        XCTAssertEqual(0.95, try XCTUnwrap(ComponentLifecycleProgress(viewModel.expirationProgress)).percentComplete, accuracy: 0.05)
    }
}

extension ComponentLifecycleProgress {
    init?(_ other: DeviceLifecycleProgress?) {
        guard let other = other else { return nil }
        self.init(percentComplete: other.percentComplete, progressState: other.progressState)
    }
}
