//
//  InsulinStatusViewModelTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Rick Pasetto on 4/19/22.
//  Copyright © 2022 Tidepool Project. All rights reserved.
//

import LoopKit
import XCTest
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class InsulinStatusViewModelTests: XCTestCase {
    var now: Date!
    var state: InsulinDeliveryPumpManagerState!
    var pumpState: IDPumpState!
    var mockPublisher: MockInsulinDeliveryPumpManagerStatePublisher!
    var viewModel: InsulinStatusViewModel!
    let defaultRate = 1.234
    var unfinalizedDose: UnfinalizedDose {
        UnfinalizedDose(tempBasalRate: 2.345, startTime: now, duration: 1, scheduledCertainty: .certain)
    }
    var deviceInformation: DeviceInformation!
    
    override func setUpWithError() throws {
        let schedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: defaultRate)], timeZone: nil)!
        now = Date()
        deviceInformation = DeviceInformation(identifier: UUID(), serialNumber: "serialNumber")
        pumpState = IDPumpState(deviceInformation: deviceInformation)
        state = InsulinDeliveryPumpManagerState(basalRateSchedule: schedule, maxBolusUnits: 0)
        state.suspendState = .resumed(now)
        state.pumpState = pumpState
        mockPublisher = MockInsulinDeliveryPumpManagerStatePublisher(state: state, pumpManager: nil, now: { self.now })
        viewModel = InsulinStatusViewModel(statePublisher: mockPublisher, now: self.now)
    }

    func testBasalDeliveryState() throws {
        XCTAssertEqual(.active(now), viewModel.basalDeliveryState)
        mockPublisher.status.basalDeliveryState = .suspended(now + .minutes(10))
        XCTAssertEqual(.suspended(now + .minutes(10)), viewModel.basalDeliveryState)
    }

    func testBasalDeliveryStateUnchangedDuringSuspendingOrResuming() throws {
        XCTAssertEqual(.active(now), viewModel.basalDeliveryState)
        mockPublisher.status.basalDeliveryState = .suspending
        XCTAssertEqual(.active(now), viewModel.basalDeliveryState)
        mockPublisher.status.basalDeliveryState = .suspended(now + .minutes(10))
        XCTAssertEqual(.suspended(now + .minutes(10)), viewModel.basalDeliveryState)
        mockPublisher.status.basalDeliveryState = .resuming
        XCTAssertEqual(.suspended(now + .minutes(10)), viewModel.basalDeliveryState)
        mockPublisher.status.basalDeliveryState = .active(now)
        XCTAssertEqual(.active(now), viewModel.basalDeliveryState)
    }

    func testBasalDeliveryRate() throws {
        XCTAssertEqual(defaultRate, viewModel.basalDeliveryRate)
        mockPublisher.state.suspendState = .suspended(now)
        XCTAssertNil(viewModel.basalDeliveryRate)
        mockPublisher.state.suspendState = .resumed(now)
        mockPublisher.state.unfinalizedTempBasal = unfinalizedDose
        XCTAssertEqual(2.345, viewModel.basalDeliveryRate)
        mockPublisher.state.suspendState = .suspended(now)
        XCTAssertNil(viewModel.basalDeliveryRate)
    }
    
    func testIsScheduledBasal() throws {
        XCTAssertTrue(viewModel.isScheduledBasal)
        mockPublisher.status.basalDeliveryState = .tempBasal(DoseEntry(unfinalizedDose, at: now))
        XCTAssertFalse(viewModel.isScheduledBasal)
        mockPublisher.status.basalDeliveryState = .active(now)
        XCTAssertTrue(viewModel.isScheduledBasal)
        mockPublisher.status.basalDeliveryState = .suspended(now)
        XCTAssertFalse(viewModel.isScheduledBasal)
    }
    
    func testIsInsulinSuspended() throws {
        XCTAssertFalse(viewModel.isInsulinSuspended)
        mockPublisher.status.basalDeliveryState = .tempBasal(DoseEntry(unfinalizedDose, at: now))
        XCTAssertFalse(viewModel.isInsulinSuspended)
        mockPublisher.status.basalDeliveryState = .suspended(now)
        XCTAssertTrue(viewModel.isInsulinSuspended)
        mockPublisher.status.basalDeliveryState = .active(now)
        XCTAssertFalse(viewModel.isInsulinSuspended)
    }
    
    func testReservoirLevelString() throws {
        XCTAssertEqual("", viewModel.reservoirLevelString)
        mockPublisher.state.pumpState.deviceInformation?.reservoirLevel = 125.1
        XCTAssertEqual("130", viewModel.reservoirLevelString)
        mockPublisher.state.pumpState.deviceInformation?.reservoirLevel = 123
        XCTAssertEqual("120", viewModel.reservoirLevelString)
        mockPublisher.state.pumpState.deviceInformation?.reservoirLevel = 48.1
        XCTAssertEqual("50", viewModel.reservoirLevelString)
        mockPublisher.state.pumpState.deviceInformation?.reservoirLevel = 48.nextDown
        XCTAssertEqual("48", viewModel.reservoirLevelString)
        mockPublisher.state.pumpState.deviceInformation?.reservoirLevel = 47.9
        XCTAssertEqual("47.9", viewModel.reservoirLevelString)
        mockPublisher.state.pumpState.deviceInformation?.reservoirLevel = 0
        XCTAssertEqual("0", viewModel.reservoirLevelString)
    }
    
    func testShouldShowStatusHighlight() throws {
        XCTAssertNil(viewModel.pumpStatusHighlight)
        
        // pump status highlight update
        pumpState.lastCommsDate = Date()
        mockPublisher.state.pumpState = pumpState
        let testStatusHighlight = PumpStatusHighlight(localizedMessage: "Foo", imageName: "bar", state: .normalPump)
        mockPublisher.pumpStatusHighlight = testStatusHighlight
        XCTAssertEqual(testStatusHighlight, viewModel.pumpStatusHighlight as? PumpStatusHighlight)
        
        // reset pump status highlight
        mockPublisher.status.basalDeliveryState = .suspended(Date())
        XCTAssertNil(viewModel.pumpStatusHighlight)
        
        // signal loss
        mockPublisher.status.basalDeliveryState = .active(Date())
        pumpState.lastCommsDate = Date() - .minutes(15)
        mockPublisher.state.pumpState = pumpState
        mockPublisher.pumpStatusHighlight = SignalLossPumpStatusHighlight()
        XCTAssert(viewModel.pumpStatusHighlight.isEqual(to: SignalLossPumpStatusHighlight()))
    }
}

extension String {
    static let nonBreakingSpace = "\u{00a0}"
}
