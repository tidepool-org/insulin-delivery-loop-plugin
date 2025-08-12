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
import InsulinDeliveryServiceKit
import BluetoothCommonKit
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class VirtualInsulinDeliveryPumpSettingsViewModelTests: XCTestCase {

    class MockDelegate: InsulinDeliveryPumpDelegate {
        var supportedBasalRates: [Double] = Array((10...2000).map { Double($0) / Double(100) })
        
        var supportedBolusVolumes: [Double] = Array((10...350).map { Double($0) / Double(10) })
        
        var supportedMaximumBolusVolumes: [Double] = Array((10...350).map { Double($0) / Double(10) })
        
        var maximumBasalScheduleEntryCount: Int = 24
        
        var minimumBasalScheduleEntryDuration: TimeInterval = TimeInterval.minutes(30)
        
        var pumpReservoirCapacity: Double = 100
        
        var supportedMaximumBasalRateAmount: Double = 20.0
        
        var basalRateProfileTemplateNumber: UInt8 = 1
        
        var numberOfProfileTemplates: UInt8 = 1
        
        var estimatedBolusDeliveryRate: Double = 2.5 / TimeInterval.minutes(1)
        
        var reservoirAccuracyLimit: Double? = 50
        
        var supportedReservoirFillVolumes: [Int] = Array(stride(from: 80, through: 100, by: 10))
        
        var pulseSize: Double = 0.08
        
        var pulsesPerUnit: Double = 1/0.08
        
        var expectedLifespan: TimeInterval = TimeInterval.days(10)
        
        var maxAllowedPumpClockDrift: TimeInterval = .seconds(60)
        
        var basalProfile: [InsulinDeliveryServiceKit.BasalSegment] = [BasalSegment(index: 1, rate: 1, duration: .hours(24))]
        
//        var basalRateSchedule: BasalRateSchedule {
//            BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)])!
//        }
        
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
        let virtualPump = VirtualInsulinDeliveryPump()
        virtualPump.delegate = delegate
        let viewModel = MockPumpSettingsViewModel(virtualPump: virtualPump, annunciationTypeToIssueDelay: 0)
        viewModel.virtualPump.deviceInformation = MockInsulinDeliveryPumpStatus.deviceInformation
        viewModel.reservoirString = "12"
        viewModel.stoppedNotificationDelay = InsulinDeliveryLoopKitUI.TimeInterval.minutes(1)
        viewModel.annunciationTypeToIssue = .batteryLow
        XCTAssertNotEqual(virtualPump.deviceInformation?.reservoirLevel, viewModel.reservoirRemaining)
        XCTAssertEqual(virtualPump.status.activeBolusDeliveryStatus.insulinProgrammed, 0.0)
        XCTAssertNotEqual(virtualPump.stoppedNotificationDelay, viewModel.stoppedNotificationDelay)
        XCTAssertNil(delegate.lastDidReceiveAnnunciation)
        viewModel.commitUpdatedSettings()
        XCTAssertEqual(virtualPump.deviceInformation?.reservoirLevel, viewModel.reservoirRemaining)
        XCTAssertEqual(virtualPump.stoppedNotificationDelay, viewModel.stoppedNotificationDelay)
        wait(for: [exp], timeout: 30)
        XCTAssertEqual(.batteryLow, delegate.lastDidReceiveAnnunciation?.type)
    }

    func testUpdateState() {
        let virtualPump = VirtualInsulinDeliveryPump(status: MockInsulinDeliveryPumpStatus.withoutBasalProfile)
        let viewModel = MockPumpSettingsViewModel(virtualPump: virtualPump)

        virtualPump.deviceInformation?.updateExpirationDate(remainingLifetime: 0)
        virtualPump.deviceInformation?.reservoirLevel = 10
        virtualPump.errorOnNextComms = DeviceCommError.procedureNotApplicable
        virtualPump.isConnected = false

        XCTAssertNotEqual(viewModel.errorOnNextComms.commError, virtualPump.errorOnNextComms)
        XCTAssertNotEqual(viewModel.disconnectComms, !virtualPump.isConnected)
        XCTAssertNotEqual(viewModel.reservoirRemaining, virtualPump.deviceInformation?.reservoirLevel)

        viewModel.updateState()
        XCTAssertEqual(viewModel.errorOnNextComms.commError, virtualPump.errorOnNextComms)
        XCTAssertEqual(viewModel.disconnectComms, !virtualPump.isConnected)
        XCTAssertEqual(viewModel.reservoirRemaining, virtualPump.deviceInformation?.reservoirLevel)
    }
}
