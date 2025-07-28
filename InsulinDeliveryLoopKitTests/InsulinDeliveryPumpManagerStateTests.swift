//
//  InsulinDeliveryPumpManagerStateTests.swift
//  InsulinDeliveryLoopKitTests
//
//  Created by Nathaniel Hamming on 2020-05-29.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import XCTest
import LoopKit
@testable import InsulinDeliveryLoopKit

class InsulinDeliveryPumpManagerStateTests: XCTestCase {
    private var simulatedDate: Date = ISO8601DateFormatter().date(from: "2020-05-29T00:00:00Z")!
    private var dateSimulationOffset: TimeInterval = 0
    private var basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1)])!
    private var deviceInformation: DeviceInformation!
    private var pumpState: IDPumpState!

    override func setUp() {
        deviceInformation = DeviceInformation(identifier: UUID(), serialNumber: "12345678")
        pumpState = pumpState(deviceInformation: deviceInformation)
    }

    private func dateGenerator() -> Date {
        return self.simulatedDate + dateSimulationOffset
    }
    
    func testInitialization() {
        let state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule,
                                         maxBolusUnits: 10.0,
                                         pumpState: pumpState,
                                         dateGenerator: dateGenerator)
        pumpState.configuration.bolusMaximum = 10.0
        
        XCTAssertEqual(state.basalRateSchedule, basalRateSchedule)
        XCTAssertNil(state.lastStatusDate)
        XCTAssertNil(state.pumpActivatedAt)
        XCTAssertNil(state.suspendState)
        XCTAssertEqual(state.timeZone, TimeZone.currentFixed)
        XCTAssertNil(state.totalInsulinDelivery)
        XCTAssertEqual(state.pumpState, pumpState)
        XCTAssertTrue(state.finalizedDoses.isEmpty)
        XCTAssertTrue(state.unfinalizedBoluses.isEmpty)
        XCTAssertNil(state.unfinalizedTempBasal)
        XCTAssertTrue(state.isSuspended)
        XCTAssertNil(state.activeTransition)
        XCTAssertFalse(state.onboardingCompleted)
        XCTAssertEqual(state.replacementWorkflowState.milestoneProgress, [])
        XCTAssertNil(state.replacementWorkflowState.pumpSetupState)
        XCTAssertNil(state.replacementWorkflowState.selectedComponents)
        XCTAssertEqual(InsulinDeliveryPumpManagerState.NotificationSettingsState(), state.notificationSettingsState)
        XCTAssertNil(state.replacementWorkflowState.lastReplacementDates)
        XCTAssertEqual([], state.onboardingVideosWatched)
    }

    func testSuspendedAt() {
        let now = Date()
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule,
                                         maxBolusUnits: 10.0,
                                         pumpState: pumpState,
                                         dateGenerator: dateGenerator)
        state.suspendState = .suspended(now)
        XCTAssertEqual(state.suspendedAt, now)
        state.suspendState = .resumed(now)
        XCTAssertNil(state.suspendedAt)

        // if the pump reports unknown updates to the therapy control state, set suspend state accordingly
        state.pumpState.deviceInformation?.pumpOperationalState = .ready
        state.pumpState.deviceInformation?.therapyControlState = .stop
        switch state.suspendState {
        case .suspended(_):
            XCTAssert(true)
        default:
            XCTAssert(false)
        }
        XCTAssertNotNil(state.suspendedAt)
        state.pumpState.deviceInformation?.therapyControlState = .run
        switch state.suspendState {
        case .resumed(_):
            XCTAssert(true)
        default:
            XCTAssert(false)
        }
        XCTAssertNil(state.suspendedAt)
    }

    func testRawValue() throws {
        let expectedVersion = 1
        let expectedLastStatusDate = Date()
        let expectedPumpActivatedAt = Date()
        let expectedTotalInsulinDelivery  = 10.5
        let bolusID: BolusID = 1
        let bolus = UnfinalizedDose(bolusAmount: 5.5,
                                    startTime: Date(),
                                    scheduledCertainty: .certain)
        let expectedUnfinalizedBoluses = [bolusID: bolus]
        let expectedUnfinalizedTempBasal = UnfinalizedDose(tempBasalRate: 1.5,
                                                     startTime: Date(),
                                                     duration: TimeInterval.minutes(15),
                                                     scheduledCertainty: .certain)
        let expectedFinalizedDoses = [bolus, expectedUnfinalizedTempBasal]
        let expectedlastReplacementDates = ComponentDates(infusionAssembly: Date.distantPast, reservoir: Date.distantFuture, pumpBase: Date.distantPast)
        let expectedReplacementWorkflowState = InsulinDeliveryPumpManagerState.ReplacementWorkflowState(milestoneProgress: [1, 2, 3],
                                                                                             pumpSetupState: .primingReservoir,
                                                                                             selectedComponents: .reservoir,
                                                                                             wasWorkflowCanceled: false,
                                                                                             componentsNeedingReplacement: [.reservoir: .forced],
                                                                                             lastReplacementDates: expectedlastReplacementDates)

        let expectedNotificationsSettingsState = InsulinDeliveryPumpManagerState.NotificationSettingsState()
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule,
                                         maxBolusUnits: 10.0,
                                         pumpState: pumpState,
                                         dateGenerator: dateGenerator)
        pumpState.configuration.bolusMaximum = 10.0

        let expectedPendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .bolus(2.0), date: Date())

        let now = Date()

        state.lastStatusDate = expectedLastStatusDate
        state.pumpActivatedAt = expectedPumpActivatedAt
        state.totalInsulinDelivery = expectedTotalInsulinDelivery
        state.finalizedDoses = expectedFinalizedDoses
        state.unfinalizedBoluses = expectedUnfinalizedBoluses
        state.unfinalizedTempBasal = expectedUnfinalizedTempBasal
        state.replacementWorkflowState = expectedReplacementWorkflowState
        state.notificationSettingsState = expectedNotificationsSettingsState
        state.replacementWorkflowState.lastReplacementDates = expectedlastReplacementDates
        state.unfinalizedSuspendDetected = true
        state.pendingInsulinDeliveryCommand = expectedPendingInsulinDeliveryCommand
        state.onboardingVideosWatched = ["foo"]
        state.lastPumpTime = now

        let serialNumber = "1234"
        let remainingLifetime = TimeInterval.hours(3)
        state.previousPumpRemainingLifetime[serialNumber] = remainingLifetime

        let rawValue = state.rawValue
        XCTAssertEqual(BasalRateSchedule(rawValue: try XCTUnwrap(rawValue["basalRateSchedule"] as? BasalRateSchedule.RawValue)), basalRateSchedule)
        XCTAssertEqual(pumpState(rawValue: try XCTUnwrap(rawValue["pumpState"] as? pumpState.RawValue)), pumpState)
        XCTAssertEqual(try XCTUnwrap(rawValue["lastStatusDate"] as? Date), expectedLastStatusDate)
        XCTAssertEqual(try XCTUnwrap(rawValue["pumpActivatedAt"] as? Date), expectedPumpActivatedAt)
        XCTAssertNil(rawValue["suspendState"] as? SuspendState.RawValue)
        XCTAssertEqual(try XCTUnwrap(rawValue["totalInsulinDelivery"] as? Double), expectedTotalInsulinDelivery)
        XCTAssertFalse(try XCTUnwrap(rawValue["onboardingCompleted"] as? Bool))
        XCTAssertEqual(InsulinDeliveryPumpManagerState.ReplacementWorkflowState(rawValue: try XCTUnwrap(rawValue["replacementWorkflowState"] as? InsulinDeliveryPumpManagerState.ReplacementWorkflowState.RawValue)), expectedReplacementWorkflowState)
        XCTAssertEqual(InsulinDeliveryPumpManagerState.NotificationSettingsState(rawValue: try XCTUnwrap(rawValue["notificationSettingsState"] as? InsulinDeliveryPumpManagerState.NotificationSettingsState.RawValue)), expectedNotificationsSettingsState)
        XCTAssertTrue(try XCTUnwrap(rawValue["unfinalizedSuspendDetected"] as? Bool))
        XCTAssertEqual(try XCTUnwrap(rawValue["lastPumpTime"] as? Date), now)

        let rawFinalizedDoses = rawValue["finalizedDoses"] as! [UnfinalizedDose.RawValue]
        let finalizedDoses = rawFinalizedDoses.compactMap( { UnfinalizedDose(rawValue: $0) } )
        for index in 0..<expectedFinalizedDoses.count {
            XCTAssertEqual(finalizedDoses[index].units, expectedFinalizedDoses[index].units)
            XCTAssertEqual(finalizedDoses[index].duration, expectedFinalizedDoses[index].duration)
            XCTAssertEqual(finalizedDoses[index].startTime, expectedFinalizedDoses[index].startTime)
            XCTAssertEqual(finalizedDoses[index].scheduledCertainty, expectedFinalizedDoses[index].scheduledCertainty)
            XCTAssertEqual(finalizedDoses[index].doseType, expectedFinalizedDoses[index].doseType)
        }

        let rawUnfinalizedBoluses = rawValue["unfinalizedBoluses"] as! Data
        let unfinalizedBoluses = try! PropertyListDecoder().decode([BolusID: UnfinalizedDose].self, from: rawUnfinalizedBoluses)
        XCTAssertFalse(unfinalizedBoluses.isEmpty)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.units, bolus.units)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.duration, bolus.duration)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.startTime, bolus.startTime)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.scheduledCertainty, bolus.scheduledCertainty)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.doseType, bolus.doseType)
        
        let unfinalizedTempBasal = UnfinalizedDose(rawValue: try XCTUnwrap(rawValue["unfinalizedTempBasal"] as? UnfinalizedDose.RawValue))
        XCTAssertEqual(unfinalizedTempBasal?.units, expectedUnfinalizedTempBasal.units)
        XCTAssertEqual(unfinalizedTempBasal?.duration, expectedUnfinalizedTempBasal.duration)
        XCTAssertEqual(unfinalizedTempBasal?.startTime, expectedUnfinalizedTempBasal.startTime)
        XCTAssertEqual(unfinalizedTempBasal?.scheduledCertainty, expectedUnfinalizedTempBasal.scheduledCertainty)
        XCTAssertEqual(unfinalizedTempBasal?.doseType, expectedUnfinalizedTempBasal.doseType)
        XCTAssertEqual(unfinalizedTempBasal?.endTime, expectedUnfinalizedTempBasal.endTime)
        XCTAssertEqual(unfinalizedTempBasal?.rate, expectedUnfinalizedTempBasal.rate)
   
        XCTAssertEqual(try XCTUnwrap(rawValue["version"] as? Int), expectedVersion)

        XCTAssertEqual(PendingInsulinDeliveryCommand(rawValue: try XCTUnwrap(rawValue["pendingInsulinDeliveryCommand"] as? PendingInsulinDeliveryCommand.RawValue)), expectedPendingInsulinDeliveryCommand)
        
        XCTAssertEqual(rawValue["onboardingVideosWatched"] as? [String], ["foo"])

        let rawPreviousPumpRemainingLifetime = rawValue["previousPumpRemainingLifetime"] as! Data
        let previousPumpRemainingLifetime = try! PropertyListDecoder().decode([String: TimeInterval].self, from: rawPreviousPumpRemainingLifetime)
        XCTAssertEqual(previousPumpRemainingLifetime[serialNumber], remainingLifetime)
    }
    
    func testRestoreFromRawValueValid() {
        let expectedLastStatusDate = Date()
        let expectedPumpActivatedAt = Date()
        let expectedlastReplacementDates = ComponentDates(infusionAssembly: .distantPast, reservoir: .distantPast, pumpBase: .distantPast)
        let expectedTotalInsulinDelivery  = 10.5
        let bolusID: BolusID = 3
        let bolus = UnfinalizedDose(bolusAmount: 5.5,
                                    startTime: Date(),
                                    scheduledCertainty: .certain)
        let expectedUnfinalizedBoluses = [bolusID: bolus]
        let expectedUnfinalizedTempBasal = UnfinalizedDose(tempBasalRate: 1.5,
                                                     startTime: Date(),
                                                     duration: TimeInterval.minutes(15),
                                                     scheduledCertainty: .certain)
        let expectedFinalizedDoses = [bolus, expectedUnfinalizedTempBasal]
        var expectedState = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule,
                                                 maxBolusUnits: 10.0,
                                                 pumpState: pumpState,
                                                 dateGenerator: dateGenerator)

        let expectedReplacementWorkflowState = InsulinDeliveryPumpManagerState.ReplacementWorkflowState(milestoneProgress: [1, 2, 3],
                                                                                             pumpSetupState: .primingReservoir,
                                                                                             selectedComponents: .reservoir,
                                                                                             wasWorkflowCanceled: false,
                                                                                             componentsNeedingReplacement: [.reservoir: .forced],
                                                                                             lastReplacementDates: expectedlastReplacementDates)
        let expectedNotificationsSettingsState = InsulinDeliveryPumpManagerState.NotificationSettingsState()

        let expectedPendingInsulinDeliveryCommand = PendingInsulinDeliveryCommand(type: .bolus(2.0), date: Date())

        expectedState.lastStatusDate = expectedLastStatusDate
        expectedState.pumpActivatedAt = expectedPumpActivatedAt
        expectedState.totalInsulinDelivery = expectedTotalInsulinDelivery
        expectedState.finalizedDoses = expectedFinalizedDoses
        expectedState.unfinalizedBoluses = expectedUnfinalizedBoluses
        expectedState.unfinalizedTempBasal = expectedUnfinalizedTempBasal
        expectedState.onboardingCompleted = true
        expectedState.replacementWorkflowState = expectedReplacementWorkflowState
        expectedState.notificationSettingsState = expectedNotificationsSettingsState
        expectedState.replacementWorkflowState.lastReplacementDates = expectedlastReplacementDates
        expectedState.unfinalizedSuspendDetected = false
        expectedState.pendingInsulinDeliveryCommand = expectedPendingInsulinDeliveryCommand
        expectedState.onboardingVideosWatched = ["foo"]
        expectedState.lastPumpTime = Date()
        expectedState.previousPumpRemainingLifetime["1234"] = .hours(4)
        let rawValue = expectedState.rawValue
        
        let state = InsulinDeliveryPumpManagerState(rawValue: rawValue)!
        XCTAssertEqual(state.basalRateSchedule, expectedState.basalRateSchedule)
        XCTAssertEqual(state.pumpState, expectedState.pumpState)
        XCTAssertEqual(state.lastStatusDate, expectedState.lastStatusDate)
        XCTAssertEqual(state.pumpActivatedAt, expectedState.pumpActivatedAt)
        XCTAssertEqual(state.timeZone, expectedState.timeZone)
        XCTAssertEqual(state.totalInsulinDelivery, expectedState.totalInsulinDelivery)
        XCTAssertTrue(state.onboardingCompleted)
        XCTAssertEqual(state.replacementWorkflowState, expectedState.replacementWorkflowState)
        XCTAssertEqual(state.notificationSettingsState, expectedState.notificationSettingsState)
        XCTAssertEqual(state.replacementWorkflowState.lastReplacementDates, expectedlastReplacementDates)
        XCTAssertEqual(state.unfinalizedSuspendDetected, false)
        XCTAssertEqual(state.pendingInsulinDeliveryCommand, expectedState.pendingInsulinDeliveryCommand)
        XCTAssertEqual(state.lastPumpTime, expectedState.lastPumpTime)
        XCTAssertEqual(state.previousPumpRemainingLifetime, expectedState.previousPumpRemainingLifetime)

        let finalizedDoses = state.finalizedDoses
        for index in 0..<expectedFinalizedDoses.count {
            XCTAssertEqual(finalizedDoses[index].units, expectedFinalizedDoses[index].units)
            XCTAssertEqual(finalizedDoses[index].duration, expectedFinalizedDoses[index].duration)
            XCTAssertEqual(finalizedDoses[index].startTime, expectedFinalizedDoses[index].startTime)
            XCTAssertEqual(finalizedDoses[index].scheduledCertainty, expectedFinalizedDoses[index].scheduledCertainty)
            XCTAssertEqual(finalizedDoses[index].doseType, expectedFinalizedDoses[index].doseType)
        }
        
        let unfinalizedBoluses = state.unfinalizedBoluses
        XCTAssertFalse(unfinalizedBoluses.isEmpty)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.units, bolus.units)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.duration, bolus.duration)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.startTime, bolus.startTime)
        XCTAssertEqual(unfinalizedBoluses[bolusID]?.scheduledCertainty, bolus.scheduledCertainty)
        
        let unfinalizedTempBasal = state.unfinalizedTempBasal
        XCTAssertEqual(unfinalizedTempBasal?.units, expectedUnfinalizedTempBasal.units)
        XCTAssertEqual(unfinalizedTempBasal?.duration, expectedUnfinalizedTempBasal.duration)
        XCTAssertEqual(unfinalizedTempBasal?.startTime, expectedUnfinalizedTempBasal.startTime)
        XCTAssertEqual(unfinalizedTempBasal?.scheduledCertainty, expectedUnfinalizedTempBasal.scheduledCertainty)
        XCTAssertEqual(unfinalizedTempBasal?.doseType, expectedUnfinalizedTempBasal.doseType)
        XCTAssertEqual(unfinalizedTempBasal?.endTime, expectedUnfinalizedTempBasal.endTime)
        XCTAssertEqual(unfinalizedTempBasal?.rate, expectedUnfinalizedTempBasal.rate)
        
        XCTAssertEqual(state.onboardingVideosWatched, ["foo"])
    }
    
    func testRestoreFromRawValueInvalid() {
        let state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule,
                                         maxBolusUnits: 10.0,
                                         pumpState: pumpState,
                                         dateGenerator: dateGenerator)
        var rawValue = state.rawValue
        rawValue.removeValue(forKey: "pumpState")
        
        let invalidState = InsulinDeliveryPumpManagerState(rawValue: rawValue)
        XCTAssertNil(invalidState)
    }
}

class PumpManagerNotificationSettingsStateTests: XCTestCase {
    typealias NotificationSettingsState = InsulinDeliveryPumpManagerState.NotificationSettingsState
    var notificationSettingsState: NotificationSettingsState!
    var expectedInfusionReplacementReminderSettings: NotificationSetting!
    let expectedIsEnabled = true
    let expectedRepeatDays = 2
    let expectedTimeOfDay = NotificationSetting.TimeOfDay(hour: 14, minute: 0)

    override func setUpWithError() throws {
        expectedInfusionReplacementReminderSettings = try NotificationSetting(isEnabled: expectedIsEnabled, repeatDays: expectedRepeatDays, timeOfDay: expectedTimeOfDay)
        notificationSettingsState = NotificationSettingsState()
        notificationSettingsState.infusionReplacementReminder = expectedInfusionReplacementReminderSettings
        notificationSettingsState.expiryReminderRepeat = .dayBefore
    }
    
    func testInitDefault() throws {
        XCTAssertEqual(NotificationSetting(), NotificationSettingsState().infusionReplacementReminder)
        XCTAssertEqual(.never, NotificationSettingsState().expiryReminderRepeat)
        XCTAssertEqual(.never, NotificationSettingsState.ExpiryReminderRepeat.default)
    }

    func testInit() throws {
        XCTAssertEqual(expectedInfusionReplacementReminderSettings, notificationSettingsState.infusionReplacementReminder)
        XCTAssertEqual(.dayBefore, notificationSettingsState.expiryReminderRepeat)
    }

    func testNotificationSettingRawValue() throws {
        let rawValue = notificationSettingsState.rawValue
        XCTAssertEqual(expectedInfusionReplacementReminderSettings, NotificationSetting(rawValue: try XCTUnwrap(rawValue["infusionReplacement"] as? NotificationSetting.RawValue)))
    }
    
    func testRestoreFromRawValueValid() throws {
        let rawValue = notificationSettingsState.rawValue
        let state = try XCTUnwrap(NotificationSettingsState(rawValue: rawValue))
        XCTAssertEqual(expectedInfusionReplacementReminderSettings, state.infusionReplacementReminder)
        XCTAssertEqual(.dayBefore, state.expiryReminderRepeat)
    }
    
    func testRestoreFromRawValueMissing() throws {
        var rawValue = notificationSettingsState.rawValue
        rawValue.removeValue(forKey: "expiryReminderRepeat")
        rawValue.removeValue(forKey: "infusionReplacement")

        let state = NotificationSettingsState(rawValue: rawValue)
        XCTAssertEqual(NotificationSetting(), state?.infusionReplacementReminder)
        XCTAssertEqual(.never, state?.expiryReminderRepeat)
    }
}

class PumpManagerWorkflowSettingsStateTests: XCTestCase {
    typealias ComponentDates = InsulinDeliveryPumpManagerState.ReplacementWorkflowState.ComponentDates
    
    var workflowState: InsulinDeliveryPumpManagerState.ReplacementWorkflowState!
    
    override func setUpWithError() throws {
        workflowState = InsulinDeliveryPumpManagerState.ReplacementWorkflowState(milestoneProgress: [1, 2, 3],
                                                                      pumpSetupState: .primingReservoir,
                                                                      selectedComponents: .reservoir,
                                                                      wasWorkflowCanceled: false,
                                                                      componentsNeedingReplacement: .none,
                                                                      lastReplacementDates: nil)
    }
    
    func testInit() throws {
        XCTAssertEqual([], InsulinDeliveryPumpManagerState.ReplacementWorkflowState().milestoneProgress)
        XCTAssertEqual(nil, InsulinDeliveryPumpManagerState.ReplacementWorkflowState().pumpSetupState)
        XCTAssertEqual(nil, InsulinDeliveryPumpManagerState.ReplacementWorkflowState().selectedComponents)
        XCTAssertEqual(false, InsulinDeliveryPumpManagerState.ReplacementWorkflowState().wasWorkflowCanceled)
        XCTAssertEqual(.none, InsulinDeliveryPumpManagerState.ReplacementWorkflowState().componentsNeedingReplacement)
        XCTAssertEqual(nil, InsulinDeliveryPumpManagerState.ReplacementWorkflowState().lastReplacementDates)
    }
    
    func testUpdating() throws {
        workflowState = workflowState.updatedWith(milestoneProgress: [1])
        XCTAssertEqual([1], workflowState.milestoneProgress)
        XCTAssertEqual(.primingReservoir, workflowState.pumpSetupState)
        XCTAssertEqual(.reservoir, workflowState.selectedComponents)
        XCTAssertEqual(false, workflowState.wasWorkflowCanceled)
        XCTAssertEqual(.none, workflowState.componentsNeedingReplacement)
        XCTAssertEqual(nil, workflowState.lastReplacementDates)

        workflowState = workflowState.updatedWith(milestoneProgress: [1, 2], pumpSetupState: .configured)
        XCTAssertEqual([1, 2], workflowState.milestoneProgress)
        XCTAssertEqual(.configured, workflowState.pumpSetupState)
        XCTAssertEqual(.reservoir, workflowState.selectedComponents)
        XCTAssertEqual(false, workflowState.wasWorkflowCanceled)
        XCTAssertEqual(.none, workflowState.componentsNeedingReplacement)
        XCTAssertEqual(nil, workflowState.lastReplacementDates)

        workflowState = workflowState.updatedWith(milestoneProgress: [1, 2], pumpSetupState: nil)
        XCTAssertEqual([1, 2], workflowState.milestoneProgress)
        XCTAssertEqual(.configured, workflowState.pumpSetupState)
        XCTAssertEqual(.reservoir, workflowState.selectedComponents)
        XCTAssertEqual(false, workflowState.wasWorkflowCanceled)
        XCTAssertEqual(.none, workflowState.componentsNeedingReplacement)
        XCTAssertEqual(nil, workflowState.lastReplacementDates)

        workflowState = workflowState.updatedWith(milestoneProgress: [1, 2], pumpSetupState: Optional<PumpSetupState>(nil))
        XCTAssertEqual([1, 2], workflowState.milestoneProgress)
        XCTAssertEqual(nil, workflowState.pumpSetupState)
        XCTAssertEqual(.reservoir, workflowState.selectedComponents)
        XCTAssertEqual(false, workflowState.wasWorkflowCanceled)
        XCTAssertEqual(.none, workflowState.componentsNeedingReplacement)
        XCTAssertEqual(nil, workflowState.lastReplacementDates)
    }
    
    func testReplacingComponents() throws {
        let now = Date.distantFuture
        workflowState = workflowState.updatedWith(componentsNeedingReplacement: [.reservoir: .forced, .pumpBase: .forced, .infusionAssembly: .forced])
        workflowState = workflowState.updatedAfterReplacing(components: .all, { now })
        XCTAssertEqual([], workflowState.milestoneProgress)
        XCTAssertEqual(nil, workflowState.pumpSetupState)
        XCTAssertEqual(false, workflowState.wasWorkflowCanceled)
        XCTAssertEqual(.none, workflowState.componentsNeedingReplacement)
        XCTAssertEqual(ComponentDates(infusionAssembly: now, reservoir: now, pumpBase: now), workflowState.lastReplacementDates)
    }
    
    func testReplacingPartialComponents() throws {
        let lastReplacement = Date()
        let now = Date.distantFuture
        workflowState = workflowState.updatedWith(componentsNeedingReplacement: [.reservoir: .forced, .pumpBase: .forced, .infusionAssembly: .forced], lastReplacementDates: ComponentDates(infusionAssembly: lastReplacement, reservoir: lastReplacement, pumpBase: lastReplacement))
        workflowState = workflowState.updatedAfterReplacing(components: .infusionAssembly, { now })
        XCTAssertEqual([], workflowState.milestoneProgress)
        XCTAssertEqual(nil, workflowState.pumpSetupState)
        XCTAssertEqual(false, workflowState.wasWorkflowCanceled)
        XCTAssertEqual([.reservoir: .forced, .pumpBase: .forced], workflowState.componentsNeedingReplacement)
        XCTAssertEqual(ComponentDates(infusionAssembly: now, reservoir: lastReplacement, pumpBase: lastReplacement), workflowState.lastReplacementDates)
    }
    
    func testReplacingComponentsWithNoLastReplacementDates() throws {
        let now = Date.distantFuture
        workflowState = workflowState.updatedWith(componentsNeedingReplacement: [.reservoir: .forced])
        workflowState = workflowState.updatedAfterReplacing(components: .reservoir, { now })
        XCTAssertEqual([], workflowState.milestoneProgress)
        XCTAssertEqual(nil, workflowState.pumpSetupState)
        XCTAssertEqual(false, workflowState.wasWorkflowCanceled)
        XCTAssertEqual(.none, workflowState.componentsNeedingReplacement)
        XCTAssertEqual(ComponentDates(infusionAssembly: now, reservoir: now, pumpBase: now), workflowState.lastReplacementDates)
    }

    func testAddComponentsNeedingReplacement() throws {
        workflowState = workflowState.updatedWith(componentsNeedingReplacement: [.reservoir: .forced])
        workflowState.addComponentsNeedingReplacement(for: nil)
        XCTAssertEqual(workflowState.componentsNeedingReplacement, [.reservoir: .forced])
        workflowState.addComponentsNeedingReplacement(for: .occlusionDetected)
        XCTAssertEqual(workflowState.componentsNeedingReplacement, [.reservoir: .forced, .infusionAssembly: .forced])
    }
    
    func testRemoveComponentsNeedingReplacement() throws {
        workflowState = workflowState.updatedWith(componentsNeedingReplacement: [.infusionAssembly: .forced, .reservoir: .forced])
        workflowState.removeComponentsNeedingReplacement(for: nil)
        XCTAssertEqual(workflowState.componentsNeedingReplacement, [.infusionAssembly: .forced, .reservoir: .forced])
        workflowState.removeComponentsNeedingReplacement(for: .occlusionDetected)
        XCTAssertEqual(workflowState.componentsNeedingReplacement, .none)
    }
}
