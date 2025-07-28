//
//  VirtualInsulinDeliveryPumpSettingsViewModelTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Nathaniel Hamming on 2021-09-29.
//  Copyright © 2021 Tidepool Project. All rights reserved.
//

import XCTest
import LoopKit
import TidepoolSecurity
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class VirtualInsulinDeliveryPumpSettingsViewModelTests: XCTestCase {

    class MockDelegate: InsulinDeliveryPumpDelegate {
        var basalRateSchedule: BasalRateSchedule {
            BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
        }
        
        var tidepoolSecurity: TidepoolSecurity?
        
        var pumpTimeZone: TimeZone = .current

        var isInReplacementWorkflow: Bool = false

        func pumpDidCompleteAuthentication(_ pump: IDPumpComms, error: DeviceCommError?) { }
        
        func pump(_ pump: IDPumpComms, didDiscoverPumpWithName peripheralName: String?, identifier: UUID, serialNumber: String?) { }
        
        var lastDidReceiveAnnunciation: Annunciation?
        var lastDidReceiveAnnunciationExpectation: XCTestExpectation?
        func pump(_ pump: IDPumpComms, didReceiveAnnunciation annunciation: Annunciation) {
            lastDidReceiveAnnunciation = annunciation
            lastDidReceiveAnnunciationExpectation?.fulfill()
        }
        
        func pumpConnectionStatusChanged(_ pump: IDPumpComms) { }
        
        func pumpDidCompleteConfiguration(_ pump: IDPumpComms) { }
        
        func pumpDidCompleteTherapyUpdate(_ pump: IDPumpComms) { }
        
        func pumpDidUpdateState(_ pump: IDPumpComms) { }

        func pumpDidInitiateBolus(_ pump: IDPumpComms, bolusID: BolusID, insulinProgrammed: Double, startTime: Date) { }

        func pumpDidDeliverBolus(_ pump: IDPumpComms, bolusID: BolusID, insulinProgrammed: Double, insulinDelivered: Double, startTime: Date, duration: TimeInterval) { }

        func pumpTempBasalStarted(_ pump: IDPumpComms, at startTime: Date, rate: Double, duration: TimeInterval) { }

        func pumpTempBasalEnded(_ pump: IDPumpComms, duration: TimeInterval) { }

        func pumpDidSuspendInsulinDelivery(_ pump: IDPumpComms, suspendedAt: Date) { }

        func pumpDidDetectHistoricalAnnunciation(_ pump: IDPumpComms, annunciation: Annunciation, at date: Date?) { }

        func pumpDidSync(_ pump: IDPumpComms, pendingCommandCheckCompleted: Bool, at date: Date) { }
    }
    
    func testStoreUpdatedSettings() {
        let delegate = MockDelegate()
        let exp = expectation(description: #function)
        exp.assertForOverFulfill = false
        delegate.lastDidReceiveAnnunciationExpectation = exp
        let mockPump = VirtualInsulinDeliveryPump()
        mockPump.delegate = delegate
        let viewModel = MockPumpSettingsViewModel(mockPump: mockPump, annunciationTypeToIssueDelay: 0)
        viewModel.mockPump.deviceInformation = MockInsulinDeliveryPumpStatus.deviceInformation
        viewModel.reservoirString = "12"
        viewModel.stoppedNotificationDelay = InsulinDeliveryLoopKitUI.TimeInterval.minutes(1)
        viewModel.annunciationTypeToIssue = .batteryLow
        XCTAssertNotEqual(mockPump.deviceInformation?.reservoirLevel, viewModel.reservoirRemaining)
        XCTAssertNotEqual(mockPump.status.activeBolusDeliveryStatus.insulinProgrammed, 0.0)
        XCTAssertNotEqual(mockPump.stoppedNotificationDelay, viewModel.stoppedNotificationDelay)
        XCTAssertNil(delegate.lastDidReceiveAnnunciation)
        viewModel.commitUpdatedSettings()
        XCTAssertEqual(mockPump.deviceInformation?.reservoirLevel, viewModel.reservoirRemaining)
        XCTAssertEqual(mockPump.stoppedNotificationDelay, viewModel.stoppedNotificationDelay)
        wait(for: [exp], timeout: 30)
        XCTAssertEqual(.batteryLow, delegate.lastDidReceiveAnnunciation?.type)
    }

    func testUpdateState() {
        let mockPump = VirtualInsulinDeliveryPump(status: MockInsulinDeliveryPumpStatus.withoutBasalRateSchedule)
        let viewModel = MockPumpSettingsViewModel(mockPump: mockPump)

        mockPump.deviceInformation?.updateExpirationDate(remainingLifetime: 0)
        mockPump.deviceInformation?.reservoirLevel = 10
        mockPump.errorOnNextComms = .procedureNotApplicable
        mockPump.isConnected = false

        XCTAssertNotEqual(viewModel.errorOnNextComms.commError, mockPump.errorOnNextComms)
        XCTAssertNotEqual(viewModel.disconnectComms, !mockPump.isConnected)
        XCTAssertNotEqual(viewModel.reservoirRemaining, mockPump.deviceInformation?.reservoirLevel)

        viewModel.updateState()
        XCTAssertEqual(viewModel.errorOnNextComms.commError, mockPump.errorOnNextComms)
        XCTAssertEqual(viewModel.disconnectComms, !mockPump.isConnected)
        XCTAssertEqual(viewModel.reservoirRemaining, mockPump.deviceInformation?.reservoirLevel)
    }
}
