//
//  InsulinDeliveryPumpManagerTests.swift
//  InsulinDeliveryLoopKitTests
//
//  Created by Nathaniel Hamming on 2020-05-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import XCTest
import LoopKit
import LoopAlgorithm
import CoreBluetooth
import BluetoothCommonKit
import InsulinDeliveryServiceKit
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class InsulinDeliveryPumpManagerTests: XCTestCase {
    private let expectationTimeout = 0.3

    private var issuedAlerts: [(alert: Alert, issuedDate: Date)] = []
    private var retractedAlerts: [(alertIdentifier: Alert.Identifier, retractedDate: Date)] = []
    private var newPumpEvents: [NewPumpEvent] = []
    private var pumpManager: InsulinDeliveryPumpManager!
    private var pump: TestInsulinDeliveryPump!
    private var pumpIsConnected: Bool = true
    private var pumpIsAuthenticated: Bool = true
    private var logEntryType: DeviceLogEntryType?
    private var logEntryMessages: [String] = []
    private var logEntryIdentifier: String?
    private var loggingExpectation: XCTestExpectation?
    private var alertExpectation: XCTestExpectation?
    private var lookupExpectation: XCTestExpectation?
    private var statusUpdateExpectation: XCTestExpectation?
    private var statusUpdates = [(status: PumpManagerStatus, oldStatus: PumpManagerStatus)]()
    private var newPumpEventsExpectation: XCTestExpectation?
    private var lastError: PumpManagerError?
    private var now: Date!
    private var pumpManagerWillDeactivateCalled = false
    internal var detectedSystemTimeOffset: TimeInterval = 0
    private var securityManagerTestingDelegate = SecurityManagerTestingDelegate()

    private let incompleteWorkflow = InsulinDeliveryPumpManagerState.ReplacementWorkflowState()
        .updatedWith(milestoneProgress: [1, 2],
                     pumpSetupState: .connecting,
                     wasWorkflowCanceled: false,
                     lastPumpReplacementDate: .distantPast)
    
    override func setUp() {
        issuedAlerts = []
        retractedAlerts = []
        newPumpEvents = []
        pumpIsConnected = true
        logEntryType = nil
        logEntryMessages = []
        logEntryIdentifier = nil
        loggingExpectation = nil
        alertExpectation = nil
        lookupExpectation = nil
        statusUpdateExpectation = nil
        newPumpEventsExpectation = nil
        lastError = nil
        statusUpdates = []
        now = Date()
        
        securityManagerTestingDelegate.sharedKeyData = Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f")!
        let securityManager = SecurityManager()
        securityManager.delegate = securityManagerTestingDelegate
        
        let bluetoothManager = BluetoothManager(peripheralConfiguration: .insulinDeliveryServiceConfiguration, servicesToDiscover: [InsulinDeliveryCharacteristicUUID.service.cbUUID], restoreOptions: nil)
        bluetoothManager.peripheralManager = PeripheralManager()
        let acControlPoint = ACControlPointDataHandler(securityManager: securityManager, maxRequestSize: 19)
        let acData = ACDataDataHandler(securityManager: securityManager, maxRequestSize: 19)
        let bolusManager = BolusManager()
        let pumpHistoryEventManager = PumpHistoryEventManager()

        var pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        pumpManagerState.pumpState.features = [.supportedE2EProtection]
        pump = TestInsulinDeliveryPump(bluetoothManager: bluetoothManager,
                                       bolusManager: bolusManager,
                                       basalManager: BasalManager(),
                                       pumpHistoryEventManager: pumpHistoryEventManager,
                                       securityManager: securityManager,
                                       acControlPoint: acControlPoint,
                                       acData: acData,
                                       state: pumpManagerState.pumpState,
                                       isConnectedHandler: { self.pumpIsConnected },
                                       isAuthenticatedHandler: { self.pumpIsAuthenticated })
        pump.setupUUIDToHandleMap()
        
        pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState, pump: pump, dateGenerator: { [weak self] in return self!.now })
        pumpManager.pumpManagerDelegate = self
        waitOnThread() // when the pump manager delegate is set, the delegate may be notified of a status update. wait until that is done before preceeding with tests
    }
    
    override func tearDown() {
        loggingExpectation = nil
        alertExpectation = nil
        lookupExpectation = nil
        statusUpdateExpectation = nil
        newPumpEventsExpectation = nil
    }
    
    func testEnsureCurrentPumpData() throws {
        completedOnboarding()
        pump.pumpDeliveryStatus = .success(nil)
        let exp = expectation(description: #function)
        newPumpEventsExpectation = expectation(description: "newPumpEvents." + #function)
        newPumpEventsExpectation?.assertForOverFulfill = false
        pumpManager.ensureCurrentPumpData { date in
            XCTAssertTrue(date! > self.now.addingTimeInterval(-1))
            exp.fulfill()
        }
        wait(for: [exp, newPumpEventsExpectation!], timeout: expectationTimeout)
        XCTAssertNil(lastError)
    }
    
    func testEnsureCurrentPumpDataReportsError() throws {
        completedOnboarding()
        pump.pumpDeliveryStatus = .failure(.authenticationFailed)
        let exp = expectation(description: #function)
        newPumpEventsExpectation = expectation(description: "newPumpEvents." + #function)
        newPumpEventsExpectation?.isInverted = true
        pumpManager.ensureCurrentPumpData { _ in
            exp.fulfill()
        }
        wait(for: [exp, newPumpEventsExpectation!], timeout: expectationTimeout)
        XCTAssertNotNil(lastError)
    }

    func testEnsureCurrentPumpDataUpdatesStatusHighlight() throws {
        completedOnboarding()
        alertExpectation = expectation(description: #function)
        alertExpectation?.assertForOverFulfill = false
        let expected = AnnunciationType.occlusionDetected
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [alertExpectation!], timeout: expectationTimeout)

        pumpIsConnected = false
        let exp = expectation(description: #function)
        pumpManager.ensureCurrentPumpData { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: expectationTimeout)

        XCTAssert(pumpManager.pumpStatusHighlight.isEqual(to: expected.statusHighlight))
    }

    func testDeviceAlertIssue() {
        alertExpectation = expectation(description: #function)
        let annunciation = GeneralAnnunciation(type: .batteryLow, identifier: 1, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)

        wait(for: [alertExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(issuedAlerts.first?.alert, Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
    }

    func testDeviceAlertRemoval() {
        alertExpectation = expectation(description: #function)
        let annunciation = GeneralAnnunciation(type: .batteryLow, identifier: 1, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)

        wait(for: [alertExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(issuedAlerts.first?.alert, Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))

        alertExpectation = expectation(description: #function)
        let deviceAlert = Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier)
        pumpManager.retractAlert(identifier: deviceAlert.identifier)

        wait(for: [alertExpectation!], timeout: expectationTimeout)
        XCTAssertEqual([deviceAlert.identifier], retractedAlerts.map { $0.alertIdentifier })
    }

    func testAllowedExpiryWarningDurations() {
        var expectedAllowedDurations: [TimeInterval] = []
        for days in 1...4 {
            expectedAllowedDurations.append(.days(days))
        }
        XCTAssertEqual(pumpManager.allowedExpiryWarningDurations, expectedAllowedDurations)
    }

    func testUpdateExpiryWarningDuration() {
        pump.setupDeviceInformation()

        // Update expiration warning threshold to 15 days
        pumpManager.updateExpiryWarningDuration(.days(15))

        // Update reservoir reading below threshold
        alertExpectation = expectation(description: "expiration reminder alert fired")
        pump.state.deviceInformation!.updateExpirationDate(remainingLifetime: .days(14))
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        // Should issue alert
        let annunciation = PumpExpiresSoonAnnunciation(identifier: 0, timeRemaining: .days(14))
        XCTAssertEqual(issuedAlerts.first?.alert, Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
    }

    func testLowReservoirWarningThreshold() {
        XCTAssertEqual(pumpManager.lowReservoirWarningThresholdInUnits, pumpManager.pumpConfiguration.reservoirLevelWarningThresholdInUnits)
    }

    func testAllowedLowReservoirWarningThresholds() {
        let expectedAllowedThresholds = Array(stride(from: 5, through: 40, by: 5))
        XCTAssertEqual(pumpManager.allowedLowReservoirWarningThresholdsInUnits, expectedAllowedThresholds)
    }

    func testUpdateLowReservoirWarningThreshold() {
        let reservoirLowThreshold = 40

        pumpManager.updateLowReservoirWarningThreshold(reservoirLowThreshold)

        XCTAssertEqual(pumpManager.state.lowReservoirWarningThresholdInUnits, 40)
    }

    func testIsSuspended() {
        var pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        pumpManagerState.suspendState = .suspended(Date())
        pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState, pump: pump)
        XCTAssertTrue(pumpManager.isSuspended)
        pumpManagerState.suspendState = .resumed(Date())
        pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState, pump: pump)
        XCTAssertFalse(pumpManager.isSuspended)
    }

    func testIsSuspendedAt() {
        let now = Date()
        var pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        pumpManagerState.suspendState = .suspended(now)
        pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState, pump: pump)
        XCTAssertEqual(pumpManager.suspendedAt, now)
        pumpManagerState.suspendState = .resumed(Date())
        pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState, pump: pump)
        XCTAssertNil(pumpManager.suspendedAt)
    }

    func testSuspendInsulinDelivery() {
        let testExpectation = XCTestExpectation()
        pump.setupDeviceInformation()
        pumpManager.suspendDelivery(completion: { _ in
            testExpectation.fulfill()
        })

        pump.respondToSetTherapyControlState(therapyControlState: .stop)

        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertTrue(pumpManager.isSuspended)
    }

    func testSuspendInsulinDeliveryDuringBolusAndTempBasal() {
        var testExpectation = expectation(description: #function)
        pump.setupDeviceInformation()

        let bolusStartTime = Date()
        let bolusAmountProgrammed = 5.0
        let bolusID: BolusID = 1
        pumpManager.pumpDidInitiateBolus(pump, bolusID: bolusID, insulinProgrammed: bolusAmountProgrammed, startTime: bolusStartTime)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 2, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: expectationTimeout)

        testExpectation = expectation(description: #function)
        pumpManager.suspendDelivery() { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToGetDeliveredInsulin()
        pump.respondToSetTherapyControlState(therapyControlState: .stop)
        wait(for: [testExpectation], timeout: expectationTimeout)

        XCTAssertTrue(pumpManager.isSuspended)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses.count, 1)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.programmedUnits, bolusAmountProgrammed)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.startTime, bolusStartTime)
        XCTAssertNotNil(pumpManager.state.unfinalizedBoluses[bolusID]?.endTime)
        XCTAssertNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertEqual(pumpManager.state.finalizedDoses.count, 2)
        XCTAssertTrue(pumpManager.state.finalizedDoses.contains(where: {$0.doseType == .tempBasal}))
        XCTAssertTrue(pumpManager.state.finalizedDoses.contains(where: {$0.doseType == .suspend}))
    }

    func testInsulinSuspendedUnexpectedly() {
        let testExpectation = XCTestExpectation()
        pump.setupDeviceInformation()

        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 2, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: expectationTimeout)

        pump.setTherapyControlStateTo(.stop)
        waitOnThread()
        waitOnThread()

        XCTAssertTrue(pumpManager.isSuspended)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertEqual(pumpManager.state.unfinalizedSuspendDetected, true)
    }

    func testResumeInsulinDelivery() {
        let testExpectation = XCTestExpectation()
        pump.setupDeviceInformation()
        pumpManager.resumeDelivery(completion: { _ in
            testExpectation.fulfill()
        })

        pump.respondToSetTherapyControlState(therapyControlState: .run)

        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertFalse(pumpManager.isSuspended)
    }

    func testLoggingDeviceEvents() {
        loggingExpectation = XCTestExpectation(description: #function)
        pump.setupDeviceInformation()
        var eventMessage = "testing connection event"
        pumpManager.logConnectionEvent(eventMessage)
        wait(for: [loggingExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(logEntryType, .connection)
        XCTAssertEqual(logEntryMessages, ["testLoggingDeviceEvents(): \(eventMessage)"])
        XCTAssertEqual(logEntryIdentifier, pump.deviceInformation!.serialNumber)

        loggingExpectation = XCTestExpectation(description: #function)
        logEntryMessages = []
        eventMessage = "testing send event"
        pumpManager.logSendEvent(eventMessage)
        wait(for: [loggingExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(logEntryType, .send)
        XCTAssertEqual(logEntryMessages, ["testLoggingDeviceEvents(): \(eventMessage)"])
        XCTAssertEqual(logEntryIdentifier, pump.deviceInformation!.serialNumber)

        loggingExpectation = XCTestExpectation(description: #function)
        logEntryMessages = []
        eventMessage = "testing receive event"
        pumpManager.logReceiveEvent(eventMessage)
        wait(for: [loggingExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(logEntryType, .receive)
        XCTAssertEqual(logEntryMessages, ["testLoggingDeviceEvents(): \(eventMessage)"])
        XCTAssertEqual(logEntryIdentifier, pump.deviceInformation!.serialNumber)

        loggingExpectation = XCTestExpectation(description: #function)
        logEntryMessages = []
        eventMessage = "testing error event"
        pumpManager.logErrorEvent(eventMessage)
        wait(for: [loggingExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(logEntryType, .error)
        XCTAssertEqual(logEntryMessages, ["testLoggingDeviceEvents(): \(eventMessage)"])
        XCTAssertEqual(logEntryIdentifier, pump.deviceInformation!.serialNumber)

        loggingExpectation = XCTestExpectation(description: #function)
        logEntryMessages = []
        eventMessage = "testing delegate event"
        pumpManager.logDelegateEvent(eventMessage)
        wait(for: [loggingExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(logEntryType, .delegate)
        XCTAssertEqual(logEntryMessages, ["testLoggingDeviceEvents(): \(eventMessage)"])
        XCTAssertEqual(logEntryIdentifier, pump.deviceInformation!.serialNumber)

        loggingExpectation = XCTestExpectation(description: #function)
        logEntryMessages = []
        eventMessage = "testing delegate response event"
        pumpManager.logDelegateResponseEvent(eventMessage)
        wait(for: [loggingExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(logEntryType, .delegateResponse)
        XCTAssertEqual(logEntryMessages, ["testLoggingDeviceEvents(): \(eventMessage)"])
        XCTAssertEqual(logEntryIdentifier, pump.deviceInformation!.serialNumber)
    }

    func testInsulinSuspensionReminder() {
        var testExpectation = XCTestExpectation()
        pump.setupDeviceInformation()
        pumpManager.suspendDelivery(reminderDelay: .minutes(5)) { _ in
            testExpectation.fulfill()
        }
        pump.respondToSetTherapyControlState(therapyControlState: .stop)

        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertTrue(pumpManager.isSuspended)

        alertExpectation = expectation(description: #function)
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        XCTAssertTrue(issuedAlerts.contains { $0.alert.identifier == pumpManager.insulinSuspensionReminderAlertIdentifier }, "Unexpected issuedAlerts: \(issuedAlerts.map({"\($0.alert.identifier) \($0.alert.trigger)"}))")

        // acknowledging insulin suspended alert triggers another insulin suspended alert if the pump is still suspended
        testExpectation = XCTestExpectation()
        pumpManager.acknowledgeAlert(alertIdentifier: pumpManager.insulinSuspensionReminderAlertIdentifier.alertIdentifier, completion: { _ in
            testExpectation.fulfill()
        })
        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertTrue(issuedAlerts.contains { $0.alert.identifier == pumpManager.insulinSuspensionReminderAlertIdentifier }, "Unexpected issuedAlerts: \(issuedAlerts.map({"\($0.alert.identifier) \($0.alert.trigger)"}))")

        // resume insulin delivery to retract suspend alert
        testExpectation = XCTestExpectation()
        pumpManager.resumeDelivery() { _ in
            testExpectation.fulfill()
        }

        pump.respondToSetTherapyControlState(therapyControlState: .run)

        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertFalse(pumpManager.isSuspended)

        alertExpectation = expectation(description: #function)
        alertExpectation?.expectedFulfillmentCount = 2
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        XCTAssertTrue(retractedAlerts.contains { $0.alertIdentifier == pumpManager.insulinSuspensionReminderAlertIdentifier })
    }
    
    func testPumpExpirationReminderDaily() {
        pumpManager.expiryReminderRepeat = .daily
        let w25Annunciation = PumpExpiresSoonAnnunciation(identifier: 1, timeRemaining: 0)
        // acknowledging insulin suspended alert triggers another insulin suspended alert if the pump is still suspended
        let testExpectation = expectation(description: #function)
        alertExpectation = expectation(description: #function)
        pumpManager.acknowledgeAlert(alertIdentifier: w25Annunciation.alertIdentifier, completion: { _ in
            testExpectation.fulfill()
        })
        wait(for: [testExpectation, alertExpectation!], timeout: expectationTimeout)
        XCTAssertTrue(issuedAlerts.contains { $0.alert.identifier == pumpManager.pumpExpirationReminderAlertIdentifier }, "Unexpected issuedAlerts: \(issuedAlerts.map({"\($0.alert.identifier) \($0.alert.trigger)"}))")
        XCTAssertTrue(issuedAlerts.contains { $0.alert.trigger == .repeating(repeatInterval: .days(1)) }, "Unexpected issuedAlerts: \(issuedAlerts.map({"\($0.alert.identifier) \($0.alert.trigger)"}))")
    }

    func testPumpExpirationReminderDayBefore() {
        let now = Date()
        pump.setupDeviceInformation()
        pump.deviceInformation?.updateExpirationDate(remainingLifetime: .days(15), reportedAt: now)
        pumpManager = InsulinDeliveryPumpManager(state: InsulinDeliveryPumpManagerState.forPreviewsAndTests, pump: pump, dateGenerator: { now })
        pumpManager.pumpManagerDelegate = self
        pumpManager.expiryReminderRepeat = .dayBefore
        let interval = pump.deviceInformation!.estimatedExpirationDate.timeIntervalSince(now) - .days(1)
        XCTAssertEqual(.days(14), interval)
        let w25Annunciation = PumpExpiresSoonAnnunciation(identifier: 1, timeRemaining: 0)
        // acknowledging insulin suspended alert triggers another insulin suspended alert if the pump is still suspended
        let testExpectation = expectation(description: #function)
        alertExpectation = expectation(description: #function)
        pumpManager.acknowledgeAlert(alertIdentifier: w25Annunciation.alertIdentifier, completion: { _ in
            testExpectation.fulfill()
        })
        wait(for: [testExpectation, alertExpectation!], timeout: expectationTimeout)
        XCTAssertTrue(issuedAlerts.contains { $0.alert.identifier == pumpManager.pumpExpirationReminderAlertIdentifier }, "Unexpected issuedAlerts: \(issuedAlerts.map({"\($0.alert.identifier) \($0.alert.trigger)"}))")
        XCTAssertTrue(issuedAlerts.contains { $0.alert.trigger == .delayed(interval: interval) }, "Unexpected issuedAlerts: \(issuedAlerts.map({"\($0.alert.identifier) \($0.alert.trigger)"}))")
    }

    func testPumpExpirationReminderNever() {
        pumpManager.expiryReminderRepeat = .never
        let w25Annunciation = PumpExpiresSoonAnnunciation(identifier: 1, timeRemaining: 0)
        // acknowledging insulin suspended alert triggers another insulin suspended alert if the pump is still suspended
        let testExpectation = expectation(description: #function)
        pumpManager.acknowledgeAlert(alertIdentifier: w25Annunciation.alertIdentifier, completion: { _ in
            testExpectation.fulfill()
        })
        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertFalse(issuedAlerts.contains { $0.alert.identifier == pumpManager.pumpExpirationReminderAlertIdentifier })
    }

    func testPumpExpirationReminderRetractedWhenWorkflowCompleted() {
        pumpManager.replacementWorkflowState = incompleteWorkflow
        XCTAssertEqual(pumpManager.replacementWorkflowState, incompleteWorkflow)
        alertExpectation = expectation(description: #function)
        completeReplacementWorkflow()
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        XCTAssertTrue(retractedAlerts.contains { $0.alertIdentifier == pumpManager.pumpExpirationReminderAlertIdentifier }, "Unexpected retractedAlerts: \(retractedAlerts)")
    }
    
    func testPumpStatusHighlightDefault() {
        pump.setupDeviceInformation()
        completedOnboarding()
        XCTAssertNil(pumpManager.pumpStatusHighlight)
    }
    
    private func setUpExpectations(_ function: String = #function) {
        waitOnThread() // wait for any pending actions to complete
        statusUpdates = [] // remove any previously received status updates
        alertExpectation = expectation(description: "alert." + function )
        lookupExpectation = expectation(description: "lookup." + function)
        // We may do multiple lookups because state is changing a few times, but we check that we only update
        // the status highlight once below.
        lookupExpectation?.assertForOverFulfill = false
        statusUpdateExpectation = expectation(description: "statusUpdates." + function)
    }
    
    func testPumpStatusHighlightShowsAnnunciation() throws {
        completedOnboarding()
        
        let expected = AnnunciationType.mechanicalIssue
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        setUpExpectations()
      
        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [statusUpdateExpectation!, alertExpectation!, lookupExpectation!], timeout: expectationTimeout)

        XCTAssertNotNil(pumpManager.pumpStatusHighlight)
        XCTAssertEqual(expected.statusHighlight, try XCTUnwrap(pumpManager.pumpStatusHighlight as? PumpStatusHighlight))
        XCTAssertEqual("No Insulin", try XCTUnwrap(pumpManager.pumpStatusHighlight as? PumpStatusHighlight).localizedMessage)
        XCTAssertEqual(1, statusUpdates.count)
        XCTAssertNil(pumpManager.pumpStatusBadge)
    }
    
    func testPumpStatusHighlightSignalLoss() throws {
        completedOnboarding()
        pump.pumpDeliveryStatus = .success(nil)
        pump.state.lastCommsDate = now
        let exp = expectation(description: #function)
        pumpManager.ensureCurrentPumpData { _ in exp.fulfill() }
        wait(for: [exp], timeout: expectationTimeout)

        XCTAssertNil(pumpManager.pumpStatusHighlight)

        pump.pumpDeliveryStatus = .failure(.unknown)
        now = now + .minutes(11)
        pumpIsConnected = false
        let exp2 = expectation(description: #function + "2")
        pumpManager.ensureCurrentPumpData { _ in exp2.fulfill() }
        wait(for: [exp2], timeout: expectationTimeout)
        
        XCTAssertEqual("Signal Loss", pumpManager.pumpStatusHighlight?.localizedMessage)
        
        pump.pumpDeliveryStatus = .success(nil)
        pump.state.lastCommsDate = now
        pumpIsConnected = true
        let exp3 = expectation(description: #function + "3")
        pumpManager.ensureCurrentPumpData { _ in exp3.fulfill() }
        wait(for: [exp3], timeout: expectationTimeout)
        
        XCTAssertNil(pumpManager.pumpStatusHighlight)
    }
    
    func testStatusHighlightPriorityOrder() throws {
        var state = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let now = Date()
        state.suspendState = .resumed(now)
        var latestAnnunciationType: AnnunciationType?
        state.onboardingCompleted = true
        state.pumpState.deviceInformation = DeviceInformation(identifier: UUID(), serialNumber: "1234", reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan)
        XCTAssertNil(InsulinDeliveryPumpManager.determinePumpStatusHighlight(state: state, latestAnnunciationType: latestAnnunciationType, isPumpConnected: pump.isConnected, now: { now }))

        // Test adding conditions in reverse to make sure priorities are correct
        state.suspendState = .suspended(now)
        XCTAssertEqual("Insulin Suspended", InsulinDeliveryPumpManager.determinePumpStatusHighlight(state: state, latestAnnunciationType: latestAnnunciationType, isPumpConnected: pump.isConnected, now: { now })?.localizedMessage)

        state.pumpState.lastCommsDate = now - .minutes(11)
        pumpIsConnected = false
        XCTAssertEqual("Signal Loss", InsulinDeliveryPumpManager.determinePumpStatusHighlight(state: state, latestAnnunciationType: nil, isPumpConnected: pump.isConnected, now: { now })?.localizedMessage)

        latestAnnunciationType = .batteryEmpty
        XCTAssertEqual("No Insulin", InsulinDeliveryPumpManager.determinePumpStatusHighlight(state: state, latestAnnunciationType: latestAnnunciationType, isPumpConnected: pump.isConnected, now: { now })?.localizedMessage)
        latestAnnunciationType = .occlusionDetected
        XCTAssertEqual("Occlusion", InsulinDeliveryPumpManager.determinePumpStatusHighlight(state: state, latestAnnunciationType: latestAnnunciationType, isPumpConnected: pump.isConnected, now: { now })?.localizedMessage)

        state.replacementWorkflowState = incompleteWorkflow
        XCTAssertEqual("Incomplete\nReplacement", InsulinDeliveryPumpManager.determinePumpStatusHighlight(state: state, latestAnnunciationType: latestAnnunciationType, isPumpConnected: pump.isConnected, now: { now })?.localizedMessage)

        state.onboardingCompleted = false
        XCTAssertEqual("Complete Setup", InsulinDeliveryPumpManager.determinePumpStatusHighlight(state: state, latestAnnunciationType: latestAnnunciationType, isPumpConnected: pump.isConnected, now: { now })?.localizedMessage)
    }
    
    func testW32ShowsBadge() throws {
        completedOnboarding()
        
        let expected = AnnunciationType.batteryLow
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        setUpExpectations()
        XCTAssertNil(pumpManager.insulinDeliveryPumpStatusBadge)

        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [statusUpdateExpectation!, alertExpectation!, lookupExpectation!], timeout: expectationTimeout)

        XCTAssertEqual(expected.statusBadge, pumpManager.insulinDeliveryPumpStatusBadge)
    }
    
    func testMultipleAnnunciationsPersistsBadge() throws {
        completedOnboarding()
        
        let expected = AnnunciationType.batteryLow
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        setUpExpectations()
        XCTAssertNil(pumpManager.insulinDeliveryPumpStatusBadge)

        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [statusUpdateExpectation!, alertExpectation!, lookupExpectation!], timeout: expectationTimeout)

        XCTAssertEqual(expected.statusBadge, pumpManager.insulinDeliveryPumpStatusBadge)

        setUpExpectations()
        statusUpdateExpectation?.isInverted = true
        pumpManager.issueAlert(Alert(with: GeneralAnnunciation(type: .reservoirLow, identifier: 1, status: .pending, auxiliaryData: Data()), managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [statusUpdateExpectation!, alertExpectation!, lookupExpectation!], timeout: expectationTimeout)

        XCTAssertEqual(expected.statusBadge, pumpManager.insulinDeliveryPumpStatusBadge)
    }
    
    func testReplacingComponentRetractsOutstandingAnnunciation() {
        completedOnboarding()
        let expected = AnnunciationType.occlusionDetected
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        setUpExpectations()
        statusUpdates = []
        
        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [statusUpdateExpectation!, alertExpectation!, lookupExpectation!], timeout: expectationTimeout)
        XCTAssertNotNil(pumpManager.pumpStatusHighlight)
        XCTAssertEqual(1, statusUpdates.count)
        
        // Ok, now reset and see if replacement clears the status highlight
        setUpExpectations()
        statusUpdates = []
        alertExpectation?.expectedFulfillmentCount = 2 // includes pump expiration reminder
        completeReplacementWorkflow()
        wait(for: [statusUpdateExpectation!, alertExpectation!, lookupExpectation!], timeout: expectationTimeout)

        XCTAssertNil(pumpManager.pumpStatusHighlight)
        XCTAssertEqual(1, statusUpdates.count)
        XCTAssertEqual(2, retractedAlerts.count)
    }
    
    func testReplacingComponentRetractsOutstandingAnnunciationWithNonAnnunciationAlert() {
        completedOnboarding()
        alertExpectation = expectation(description: "alert1." + #function)
        pumpManager.issueInsulinSuspensionReminderAlert(reminderDelay: 0)
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        
        let expected = AnnunciationType.occlusionDetected
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        setUpExpectations()
        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [statusUpdateExpectation!, alertExpectation!, lookupExpectation!], timeout: expectationTimeout)
        
        // Ok, now reset and see if replacement clears the status highlight
        setUpExpectations()
        alertExpectation?.expectedFulfillmentCount = 2 // includes pump expiration reminder
        completeReplacementWorkflow()
        wait(for: [alertExpectation!, statusUpdateExpectation!, lookupExpectation!], timeout: expectationTimeout)

        XCTAssertNil(pumpManager.pumpStatusHighlight)
        XCTAssertEqual(1, statusUpdates.count)
        XCTAssertEqual(2, retractedAlerts.count) // includes pump expiration reminder
    }

    func testPumpStatusHighlightInsulinSuspended() {
        struct Status: PumpDeliveryStatus {
            var therapyControlState: InsulinTherapyControlState
            var pumpOperationalState: PumpOperationalState
            var reservoirLevel: Double?
        }
        pump.suspendInsulinDeliveryResult = .success(Status(therapyControlState: .stop, pumpOperationalState: .ready, reservoirLevel: 100))
        completedOnboarding()
        setUpExpectations()
        statusUpdateExpectation?.assertForOverFulfill = false
        // No alert is expected
        alertExpectation?.isInverted = true
        let suspendExpectation = expectation(description: "suspend." + #function)
        
        pumpManager.suspendDelivery { _ in
            suspendExpectation.fulfill()
        }
        
        wait(for: [suspendExpectation, alertExpectation!, lookupExpectation!, statusUpdateExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.imageName, "pause.circle.fill")
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.localizedMessage, "Insulin Suspended")
    }

    func testPumpStatusHighlightInsulinSuspendedWorkflowIncomplete() {
        struct Status: PumpDeliveryStatus {
            var therapyControlState: InsulinTherapyControlState
            var pumpOperationalState: PumpOperationalState
            var reservoirLevel: Double?
        }
        pump.suspendInsulinDeliveryResult = .success(Status(therapyControlState: .pause, pumpOperationalState: .ready, reservoirLevel: 100))
        completedOnboarding()
        pumpManager.replacementWorkflowState = incompleteWorkflow
        setUpExpectations()
        statusUpdateExpectation?.assertForOverFulfill = false
        // No alert is expected
        alertExpectation?.isInverted = true
        let suspendExpectation = expectation(description: "suspend." + #function)
        
        pumpManager.suspendDelivery { _ in
            suspendExpectation.fulfill()
        }
        
        wait(for: [suspendExpectation, alertExpectation!, lookupExpectation!, statusUpdateExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.imageName, "exclamationmark.circle.fill")
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.localizedMessage, "Incomplete\nReplacement")
    }
    
    func testPumpStatusHighlightInsulinSuspendedReplacementComponentsNeeded() {
        struct Status: PumpDeliveryStatus {
            var therapyControlState: InsulinTherapyControlState
            var pumpOperationalState: PumpOperationalState
            var reservoirLevel: Double?
        }
        pump.suspendInsulinDeliveryResult = .success(Status(therapyControlState: .pause, pumpOperationalState: .ready, reservoirLevel: 100))
        completedOnboarding()
        setUpExpectations()
        statusUpdateExpectation?.assertForOverFulfill = false
        // No alert is expected
        alertExpectation?.isInverted = true
        let suspendExpectation = expectation(description: "suspend." + #function)
        
        pumpManager.suspendDelivery { _ in
            suspendExpectation.fulfill()
        }
        
        wait(for: [suspendExpectation, alertExpectation!, lookupExpectation!, statusUpdateExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.imageName, "pause.circle.fill")
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.localizedMessage, "Insulin Suspended")
    }

    func testPumpStatusHighlightWithIncompleteOnboarding() {
        pump.prepareForNewPump()
        waitOnThread()
        pump.setupDeviceInformation()

        setUpExpectations()
        // No alert is expected
        alertExpectation?.isInverted = true
        lookupExpectation?.isInverted = true
        statusUpdateExpectation?.assertForOverFulfill = false
        
        wait(for: [alertExpectation!, lookupExpectation!, statusUpdateExpectation!], timeout: expectationTimeout)

        XCTAssertEqual(pumpManager.pumpStatusHighlight?.imageName, "exclamationmark.circle.fill")
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.localizedMessage, "Complete Setup")
    }

    func testPumpStatusHighlightReplacementWorkflowIncomplete() {
        completedOnboarding()
        pumpManager.replacementWorkflowState = incompleteWorkflow
        
        setUpExpectations()
        // No alert is expected
        alertExpectation?.isInverted = true
        lookupExpectation?.isInverted = true

        wait(for: [alertExpectation!, lookupExpectation!, statusUpdateExpectation!], timeout: expectationTimeout)

        XCTAssertEqual(pumpManager.pumpStatusHighlight?.imageName, "exclamationmark.circle.fill")
        XCTAssertEqual(pumpManager.pumpStatusHighlight?.localizedMessage, "Incomplete\nReplacement")
        XCTAssertEqual(1, statusUpdates.count)
    }

    func testStartPrimingReservoir() {
        let testExpectation = XCTestExpectation(description: #function)

        pump.setupDeviceInformation()
        pumpManager.startPriming() { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        pump.respondToStartPriming()

        wait(for: [testExpectation], timeout: expectationTimeout)
    }

    func testStopPrimingReservoir() {
        let testExpectation = XCTestExpectation(description: #function)

        pump.setupDeviceInformation()
        pumpManager.stopPriming() { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        pump.respondToStopPriming()

        wait(for: [testExpectation], timeout: expectationTimeout)
    }

    func recordAnnunciation(_ annunciationType: AnnunciationType) {
        alertExpectation = expectation(description: #function)
        pumpManager.pump(pump, didReceiveAnnunciation: GeneralAnnunciation(type: annunciationType, identifier: 1, status: .pending, auxiliaryData: Data()))
        wait(for: [alertExpectation!], timeout: expectationTimeout)
    }

    func testReservoirLowHandling() {
        pump.setupDeviceInformation()
        pump.state.deviceInformation!.reservoirLevel = 35

        // Update low reservoir threshold to 30U
        pumpManager.updateLowReservoirWarningThreshold(30)

        // Update reservoir reading below threshold
        alertExpectation = expectation(description: "reservoir update below threshold")
        pump.state.deviceInformation!.reservoirLevel = 25
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        // Should issue alert
        let annunciation = LowReservoirAnnunciation(identifier: 0, currentReservoirWarningLevel: 30)
        XCTAssertEqual(issuedAlerts.first?.alert, Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
    }
    
    func testReplacementWorkflowCompletedFromIncompleteWorkflow() {
        pumpManager.replacementWorkflowState = incompleteWorkflow
        XCTAssertEqual(pumpManager.replacementWorkflowState, incompleteWorkflow)
        XCTAssertTrue(pumpManager.replacementWorkflowState.isWorkflowIncomplete)
        completeReplacementWorkflow()

        XCTAssertNotEqual(pumpManager.replacementWorkflowState, incompleteWorkflow)
        XCTAssertFalse(pumpManager.replacementWorkflowState.isWorkflowIncomplete)
        XCTAssertEqual(pumpManager.replacementWorkflowState.lastPumpReplacementDate, now)
    }
        
    func testUpdateReplacementWorkflowState() {
        recordAnnunciation(.reservoirEmpty)
        let milestoneProgress = [1, 2]
        let pumpSetupState = PumpSetupState.connecting
        let expectedReplacementWorkflowState = InsulinDeliveryPumpManagerState.ReplacementWorkflowState(milestoneProgress: milestoneProgress, pumpSetupState: pumpSetupState, wasWorkflowCanceled: false, lastPumpReplacementDate: nil, doesPumpNeedsReplacement: true)
        
        pumpManager.updateReplacementWorkflowState(milestoneProgress: milestoneProgress, pumpSetupState: pumpSetupState)
        XCTAssertEqual(pumpManager.replacementWorkflowState, expectedReplacementWorkflowState)
    }

    func testUpdateReplacementWorkflowCanceled() {
        pumpManager.replacementWorkflowState = incompleteWorkflow
        recordAnnunciation(.reservoirEmpty)
        pumpManager.replacementWorkflowCanceled()
        XCTAssertTrue(pumpManager.replacementWorkflowState.wasWorkflowCanceled)
        XCTAssertEqual(pumpManager.replacementWorkflowState.milestoneProgress, [])
        XCTAssertNil(pumpManager.replacementWorkflowState.pumpSetupState)
    }

    func testBolusCanceledAnnunciation() {
        let testExpectation = expectation(description: #function)
        
        // enact bolus
        pump.setupDeviceInformation()
        let bolusAmount: Double = 1
        pumpManager.enactBolus(decisionId: nil, units: bolusAmount, activationType: .manualRecommendationAccepted) { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        let bolusID: BolusID = 123
        pump.respondToSetBolusWithSuccess(bolusID: bolusID)

        wait(for: [testExpectation], timeout: expectationTimeout)

        // check that bolus is running
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.wasCanceled, false)

        alertExpectation = expectation(description: #function)
        pump.sendBolusCancelledAnnunciation(bolusID: bolusID, programmedAmount: bolusAmount, deliveredAmount: bolusAmount/2)
        waitOnThread()

        // check that bolus delivery has been canceled
        XCTAssertNotNil(pumpManager.state.unfinalizedBoluses[bolusID])
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses.count, 1)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.wasCanceled, true)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.doseType, .bolus)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.units, bolusAmount/2)
    
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        
        // And it should have issued an alert
        XCTAssertEqual(try issuedAlerts.first.map { try $0.alert.identifier.alertIdentifier.annunciationComponents().type }, BolusCanceledAnnunciation.type)
    }

    func testBolusCanceledAnnunciationUserGenerated() {
        let testExpectation = expectation(description: #function)
        alertExpectation = expectation(description: #function)
        
        // enact bolus
        pump.setupDeviceInformation()
        let bolusAmount: Double = 1
        pumpManager.enactBolus(decisionId: nil, units: bolusAmount, activationType: .manualRecommendationAccepted) { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        let bolusID: BolusID = 123
        pump.respondToSetBolusWithSuccess(bolusID: bolusID)

        wait(for: [testExpectation], timeout: expectationTimeout)

        // check that bolus is running
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.wasCanceled, false)
        
        // cancel it normally
        let testExpectation2 = expectation(description: "\(#function) cancel bolus")
        pumpManager.cancelBolus(completion: {_ in testExpectation2.fulfill() })

        pump.sendBolusCancelledAnnunciation(bolusID: bolusID, programmedAmount: bolusAmount, deliveredAmount: bolusAmount/2)

        wait(for: [testExpectation2], timeout: expectationTimeout)

        // check that bolus delivery has been canceled
        XCTAssertNotNil(pumpManager.state.unfinalizedBoluses[bolusID])
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses.count, 1)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.doseType, .bolus)
    
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        
        // And it should have NOT issued an alert
        XCTAssertTrue(issuedAlerts.isEmpty)
        // But we do report a retracted alert such that it is present in the alert store
        XCTAssertTrue(!retractedAlerts.isEmpty)
    }

    func testTempBasalCanceledAnnunciation() {
        let testExpectation = expectation(description: #function)
        alertExpectation = expectation(description: #function)
        let rate: Double = 4
        pump.startDeliveringInsulin()
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: rate, for: .minutes(30)) { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: expectationTimeout)

        pumpManager.pump(pump, didReceiveAnnunciation: GeneralAnnunciation(type: .tempBasalCanceled, identifier: 1, status: .pending, auxiliaryData: Data()))
        wait(for: [alertExpectation!], timeout: expectationTimeout)
        // We do not issue an alert for W-36
        XCTAssertTrue(issuedAlerts.isEmpty)
        // But we do report a retracted alert such that it is present in the alert store
        XCTAssertTrue(!retractedAlerts.isEmpty)
    }

    func testPumpNotConfiguredAnnunciationWorkflowComplete() {
        alertExpectation = expectation(description: #function)
        let annunciation = GeneralAnnunciation(type: .reservoirEmpty, identifier: 1, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)
        XCTAssertFalse(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        wait(for: [self.alertExpectation!], timeout: expectationTimeout)
        
        XCTAssertFalse(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        XCTAssertEqual(issuedAlerts.first?.alert, Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
    }

    func testPrimingIssueAnnunciationWorkflowComplete() {
        alertExpectation = expectation(description: #function)
        let annunciation = GeneralAnnunciation(type: .primingIssue, identifier: 1, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)
        XCTAssertFalse(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        wait(for: [self.alertExpectation!], timeout: expectationTimeout)
        
        XCTAssertFalse(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        XCTAssertEqual(issuedAlerts.first?.alert, Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
    }

    func testReservoirIssueAnnunciationWorkflowIncomplete() {
        let expectation = expectation(description: #function)
        class Observer: InsulinDeliveryPumpObserver {
            var receivedReservorIssue = false
            let exp: XCTestExpectation
            init(exp: XCTestExpectation) {
                self.exp = exp
            }
            func pumpEncounteredReservoirIssue() {
                receivedReservorIssue = true
                exp.fulfill()
            }
        }
        let observer = Observer(exp: expectation)
        pumpManager.addPumpObserver(observer, queue: .main)
        pumpManager.replacementWorkflowState = incompleteWorkflow

        let annunciation = GeneralAnnunciation(type: .reservoirIssue, identifier: 1, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)
        XCTAssertTrue(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        waitOnThread()
        wait(for: [expectation], timeout: expectationTimeout)

        XCTAssertTrue(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        XCTAssertTrue(issuedAlerts.isEmpty)
        XCTAssertTrue(observer.receivedReservorIssue)
        XCTAssertTrue(pump.confirmedAnnunciations.contains { $0 as? GeneralAnnunciation == annunciation })
        XCTAssertTrue(pump.confirmedAnnunciations.contains { $0.type == .reservoirIssue })

        pumpManager.removePumpObserver(observer)
    }
    
    func testAcknowledgeAlertConfirmsAnnunciation() {
        pump.confirmAnnunciationResult = .success
        recordAnnunciation(.reservoirEmpty)
        let annunciation = GeneralAnnunciation(type: AnnunciationType.reservoirEmpty, identifier: 1, status: .pending, auxiliaryData: Data())
        XCTAssertTrue(pump.confirmedAnnunciations.isEmpty)
        let exp = expectation(description: #function)
        pumpManager.acknowledgeAlert(alertIdentifier: annunciation.alertIdentifier) {
            XCTAssertNil($0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: expectationTimeout)
        XCTAssertEqual([.reservoirEmpty], pump.confirmedAnnunciations.map { $0.type } )
    }

    func testPrimingIssueAnnunciationAutoConfirmsWorkflowIncomplete() {
        let replacementWorkflowState = incompleteWorkflow
        pumpManager.replacementWorkflowState = replacementWorkflowState

        let annunciation = GeneralAnnunciation(type: .primingIssue, identifier: 1, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)
        XCTAssertTrue(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        waitOnThread()
        
        XCTAssertTrue(pumpManager.state.replacementWorkflowState.isWorkflowIncomplete)
        XCTAssertTrue(issuedAlerts.isEmpty)
    }

    func testEnactTempBasal() {
        let testExpectation = XCTestExpectation(description: #function)
        let rate: Double = 4
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: rate, for: .minutes(30)) { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }
        pump.respondToTempBasalAdjustmentWithSuccess()

        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertEqual(pumpManager.state.unfinalizedTempBasal?.rate, rate)
    }

    func testPumpDidUpdateStateInsulinDeliveryStoppedUnexpectedly() {
        // if there is a temp basal running and insulin delivery stops out of comms, the temp basal is cancelled when comms return
        var testExpectation = XCTestExpectation(description: #function)

        pump.setupDeviceInformation()
        pumpManager.resumeDelivery() { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        pump.respondToSetTherapyControlState(therapyControlState: .run)
        wait(for: [testExpectation], timeout: expectationTimeout)

        testExpectation = XCTestExpectation(description: #function)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 4, for: .minutes(30)) { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: expectationTimeout)

        // mock therapy
        pump.setTherapyControlStateTo(.stop)

        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)
    }

    func testOnlyReport1InsulinSuspendedNewPumpEvent() {
        var testExpectation = XCTestExpectation(description: #function)

        pump.setupDeviceInformation()
        pumpManager.resumeDelivery() { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        pump.respondToSetTherapyControlState(therapyControlState: .run)
        wait(for: [testExpectation], timeout: expectationTimeout)
        waitOnThread()
        XCTAssertEqual(newPumpEvents.count, 1)
        XCTAssertEqual(newPumpEvents[0].type, .resume)

        testExpectation = XCTestExpectation(description: #function)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 4, for: .minutes(30)) { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: expectationTimeout)
        waitOnThread()
        XCTAssertEqual(newPumpEvents.count, 1)
        XCTAssertEqual(newPumpEvents[0].type, .tempBasal)

        testExpectation = XCTestExpectation(description: #function)
        pumpManager.suspendDelivery() { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        // mock therapy
        pump.respondToGetDeliveredInsulin()
        pump.setTherapyControlStateTo(.stop)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)

        pump.respondToSetTherapyControlState(therapyControlState: .stop)
        wait(for: [testExpectation], timeout: expectationTimeout)
        XCTAssertNil(pumpManager.state.unfinalizedTempBasal)

        waitOnThread()
        XCTAssertEqual(newPumpEvents.count, 2)
        XCTAssertTrue(newPumpEvents.contains { $0.type == .tempBasal && $0.dose?.endDate != nil })
        XCTAssertTrue(newPumpEvents.contains { $0.type == .suspend})
    }

    func testFinalizeAndStoreDoses() {
        let now = Date()
        let bolus1StartTime = now.addingTimeInterval(-.minutes(1.5))
        let bolus1Duration = TimeInterval.seconds(30)
        let bolus1AmountProgrammed = 5.0
        let bolus1AmountDelivered = 3.0
        let bolus2StartTime = now.addingTimeInterval(-.minutes(0.5))
        let bolus2AmountProgrammed = 2.0
        let bolus1ID: BolusID = 1
        let bolus2ID: BolusID = 2

        pumpManager.pumpDidInitiateBolus(pump, bolusID: bolus1ID, insulinProgrammed: bolus1AmountProgrammed, startTime: bolus1StartTime)
        XCTAssertEqual(pumpManager.state.finalizedDoses.count, 0)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses.count, 1)
        XCTAssertNotNil(pumpManager.state.unfinalizedBoluses[bolus1ID])
        var bolus = pumpManager.state.unfinalizedBoluses[bolus1ID]!
        XCTAssertEqual(bolus.units, bolus1AmountProgrammed)
        XCTAssertNil(bolus.programmedUnits)
        XCTAssertEqual(bolus.startTime, bolus1StartTime)

        pumpManager.pumpDidInitiateBolus(pump, bolusID: bolus2ID, insulinProgrammed: bolus2AmountProgrammed, startTime: bolus2StartTime)
        XCTAssertEqual(pumpManager.state.finalizedDoses.count, 0)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses.count, 2)
        XCTAssertNotNil(pumpManager.state.unfinalizedBoluses[bolus1ID])
        XCTAssertNotNil(pumpManager.state.unfinalizedBoluses[bolus2ID])
        bolus = pumpManager.state.unfinalizedBoluses[bolus2ID]!
        XCTAssertEqual(bolus.units, bolus2AmountProgrammed)
        XCTAssertNil(bolus.programmedUnits)
        XCTAssertEqual(bolus.startTime, bolus2StartTime)

        pumpManager.pumpDidDeliverBolus(pump, bolusID: bolus1ID, insulinProgrammed: bolus1AmountProgrammed, insulinDelivered: bolus1AmountDelivered, startTime: bolus1StartTime, duration: bolus1Duration)

        XCTAssertEqual(pumpManager.state.finalizedDoses.count, 1)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses.count, 1)
        XCTAssertNil(pumpManager.state.unfinalizedBoluses[bolus1ID])
        XCTAssertNotNil(pumpManager.state.unfinalizedBoluses[bolus2ID])
        bolus = pumpManager.state.finalizedDoses[0]
        XCTAssertEqual(bolus.programmedUnits, bolus1AmountProgrammed)
        XCTAssertEqual(bolus.units, bolus1AmountDelivered)
        XCTAssertEqual(bolus.startTime, bolus1StartTime)
        XCTAssertEqual(bolus.duration, bolus1Duration)

        waitOnThread()
        XCTAssertFalse(newPumpEvents.isEmpty)
        XCTAssertEqual(newPumpEvents.count, 2)
        XCTAssertTrue(newPumpEvents[0].dose?.deliveredUnits == nil ? newPumpEvents[0].dose!.isMutable == true : newPumpEvents[0].dose!.isMutable == false)
        XCTAssertTrue(newPumpEvents[1].dose?.deliveredUnits == nil ? newPumpEvents[1].dose!.isMutable == true : newPumpEvents[1].dose!.isMutable == false)
        XCTAssertEqual(newPumpEvents[0].type, .bolus)
        XCTAssertEqual(newPumpEvents[1].type, .bolus)
    }

    func testFinalizeAllCachedDosesWhenPumpBaseIsReplaced() {
        let now = Date()
        let bolus1StartTime = now.addingTimeInterval(-.minutes(1.5))
        let bolus1AmountProgrammed = 5.0
        let bolus2StartTime = now.addingTimeInterval(-.minutes(0.5))
        let bolus2AmountProgrammed = 2.0
        let bolus1ID: BolusID = 1
        let bolus2ID: BolusID = 2

        pumpManager.pumpDidInitiateBolus(pump, bolusID: bolus1ID, insulinProgrammed: bolus1AmountProgrammed, startTime: bolus1StartTime)
        pumpManager.pumpDidInitiateBolus(pump, bolusID: bolus2ID, insulinProgrammed: bolus2AmountProgrammed, startTime: bolus2StartTime)
        let testExpectation = expectation(description: #function)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 1.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)

        XCTAssertFalse(pumpManager.state.finalizedDoses.contains(where: { $0.doseType == .tempBasal }))
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses.count, 2)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)

        pumpManager.updateReplacementWorkflowState(milestoneProgress: [], pumpSetupState: nil)
        pumpManager.replacementWorkflowCompleted() // do not wait for threaded actions to occur here

        XCTAssertTrue(pumpManager.state.unfinalizedBoluses.isEmpty)
        XCTAssertNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertEqual(pumpManager.state.finalizedDoses.count, 3)

        waitOnThread()
        XCTAssertFalse(newPumpEvents.isEmpty)
        XCTAssertEqual(newPumpEvents.count, 3)
        XCTAssertEqual(newPumpEvents.filter({ $0.type == .bolus }).count, 2)
        let boluses = newPumpEvents.filter({ $0.type == .bolus })
        XCTAssertEqual(boluses.first?.dose?.isMutable, false)
        XCTAssertEqual(boluses.last?.dose?.isMutable, false)
        XCTAssertEqual(newPumpEvents.filter({ $0.type == .tempBasal}).count, 1)
        let tempBasal = newPumpEvents.filter({ $0.type == .tempBasal })
        XCTAssertEqual(tempBasal.first?.dose?.isMutable, false)
    }

    func testEnactBolus() {
        let testExpectation = XCTestExpectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { error in
            if error != nil {
                XCTAssert(false)
            } else {
                testExpectation.fulfill()
            }
        }

        pump.respondToSetBolusWithSuccess(bolusID: 1)
        wait(for: [testExpectation], timeout: expectationTimeout)
    }

    func testEnactBolusDisconnected() {
        let testExpectation = XCTestExpectation(description: #function)
        pumpIsConnected = false
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { error in
            if case .connection(let nestedError) = error,
               let pumpError = nestedError as? InsulinDeliveryPumpManagerError,
               case .commError(let commError) = pumpError
            {
                XCTAssertEqual(commError, .disconnected)
                testExpectation.fulfill()
            } else {
                XCTAssert(false)
            }
        }
        wait(for: [testExpectation], timeout: expectationTimeout)
    }

    func testEnactBolusInvalidBolusVolume() {
        let testExpectation = XCTestExpectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: 0, activationType: .manualRecommendationAccepted) { error in
            if case .configuration(let nestedError) = error,
               let pumpError = nestedError as? InsulinDeliveryPumpManagerError,
               case .invalidBolusVolume = pumpError
            {
                XCTAssert(true)
                testExpectation.fulfill()
            } else {
                XCTAssert(false)
            }
        }
        wait(for: [testExpectation], timeout: expectationTimeout)
    }

    func testEnactBolusAlreadyInProgress() {
        let testExpectation = XCTestExpectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { _ in }
        pumpManager.enactBolus(decisionId: nil, units: 3, activationType: .manualRecommendationAccepted) { error in
            if case .deviceState(let nestedError) = error,
               let pumpError = nestedError as? InsulinDeliveryPumpManagerError,
               case .hasActiveCommand = pumpError
            {
                XCTAssert(true)
                testExpectation.fulfill()
            } else {
                XCTAssert(false)
            }
        }
    }

    func testEnactBolusInsulinSuspended() {
        pump.setupDeviceInformation(therapyControlState: .run, pumpOperationalState: .ready)
        var testExpectation = expectation(description: #function)
        pumpManager.suspendDelivery() { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToSetTherapyControlState(therapyControlState: .stop)
        wait(for: [testExpectation], timeout: 30)

        testExpectation = expectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { error in
            if case .deviceState(let nestedError) = error,
               let pumpError = nestedError as? InsulinDeliveryPumpManagerError,
               case .insulinDeliverySuspended = pumpError
            {
                XCTAssert(true)
                testExpectation.fulfill()
            } else {
                XCTAssert(false)
            }
        }
        wait(for: [testExpectation], timeout: 30)
    }

    func testAutoConfirmTempBasalCanceledAnnunciation() {
        let annunciation = GeneralAnnunciation(type: .tempBasalCanceled, identifier: 123, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)
        XCTAssertTrue(pump.idCommand.lockedRequestQueue.value.contains(where: { IDCommandControlPointOpcode(rawValue: $0.request[$0.request.startIndex...].to(IDCommandControlPointOpcode.RawValue.self)) ==  .confirmAnnunciation}))
    }

    func testIssueCanceledBolusAnnunciationWithNoBolusID() {
        let bolusID: BolusID = 123
        let bolusDeliveryStatus = BolusDeliveryStatus(id: bolusID, progressState: .canceled, type: .fast, insulinProgrammed: 2, insulinDelivered: 1, startTime: Date(), endTime: Date())
        let annunciation = BolusCanceledAnnunciation(identifier: bolusID, bolusDeliveryStatus: bolusDeliveryStatus)
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)

        alertExpectation = expectation(description: #function)
        wait(for: [self.alertExpectation!], timeout: expectationTimeout)
        XCTAssertTrue(issuedAlerts.contains(where: { try! $0.alert.annunciationType() == AnnunciationType.bolusCanceled}))
    }

    func testTempBasalEnded() {
        let testExpectation = expectation(description: #function)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 1.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)

        let duration = TimeInterval.minutes(10)
        pumpManager.pumpTempBasalEnded(pump, duration: duration)
        XCTAssertNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertEqual(pumpManager.state.finalizedDoses.count, 1)
        XCTAssertTrue(pumpManager.state.finalizedDoses.contains(where: { $0.doseType == .tempBasal }))
        waitOnThread()
        XCTAssertEqual(newPumpEvents.count, 1)
        XCTAssertEqual(newPumpEvents.first?.dose?.type, .tempBasal)
    }
    
    func testAutoConfirmStopWarningW41Annunciation() {
        let annunciation = GeneralAnnunciation(type: .endOfPumpLifetime, identifier: 123, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation)
        XCTAssertTrue(pump.idCommand.lockedRequestQueue.value.contains(where: { IDCommandControlPointOpcode(rawValue: $0.request[$0.request.startIndex...].to(IDCommandControlPointOpcode.RawValue.self)) ==  .confirmAnnunciation}))
    }

    func testIssueAnnunciationAvoidDuplicate() {
        alertExpectation = expectation(description: #function)
        let annunciation1 = GeneralAnnunciation(type: .occlusionDetected, identifier: 123, status: .pending, auxiliaryData: Data())
        let annunciation2 = GeneralAnnunciation(type: .occlusionDetected, identifier: 1234, status: .pending, auxiliaryData: Data())
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation1)
        wait(for: [self.alertExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(issuedAlerts.count, 1)
        XCTAssertTrue(issuedAlerts.contains(where: { $0.alert.identifier.alertIdentifier == annunciation1.alertIdentifier }))

        // duplicate annunciation received
        alertExpectation = expectation(description: #function)
        alertExpectation?.isInverted = true
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation1)
        wait(for: [self.alertExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(issuedAlerts.count, 1)
        XCTAssertTrue(issuedAlerts.contains(where: { $0.alert.identifier.alertIdentifier == annunciation1.alertIdentifier }))

        // different annunciation received
        alertExpectation = expectation(description: #function)
        pumpManager.pump(pump, didReceiveAnnunciation: annunciation2)
        wait(for: [self.alertExpectation!], timeout: expectationTimeout)
        XCTAssertEqual(issuedAlerts.count, 2)
        XCTAssertTrue(issuedAlerts.contains(where: { $0.alert.identifier.alertIdentifier == annunciation1.alertIdentifier }))
        XCTAssertTrue(issuedAlerts.contains(where: { $0.alert.identifier.alertIdentifier == annunciation2.alertIdentifier }))
    }

    func testPumpDidSuspendInsulinDelivery() {
        pump.setupDeviceInformation()
        pump.setTherapyControlStateTo(.stop)
        waitOnThread()

        XCTAssertEqual(pumpManager.state.unfinalizedSuspendDetected, true)

        let now = Date()
        pumpManager.pumpDidSuspendInsulinDelivery(pump, suspendedAt: now)
        XCTAssertNil(pumpManager.state.unfinalizedSuspendDetected)
        XCTAssertEqual(pumpManager.state.finalizedDoses.count, 1)
        XCTAssertEqual(pumpManager.state.finalizedDoses.first?.doseType, .suspend)
        XCTAssertEqual(pumpManager.state.finalizedDoses.first?.startTime, now)
    }

    func testLastSync() {
        let now = Date()
        completedOnboarding()
        pumpManager.pumpDidSync(pump, at: now)
        XCTAssertEqual(pumpManager.lastSync, now)

        pumpIsConnected = true
        let testExpectation = expectation(description: #function)
        pumpManager.suspendDelivery(completion: { error in
            if let pumpManagerError = error as? PumpManagerError,
               case .uncertainDelivery = pumpManagerError
            {
                testExpectation.fulfill()
            } else {
                XCTAssert(false)
            }
        })
        waitOnThread()
        pump.prepareForNewPump() // reports disconnect to all pending procedures causing a pending insulin delivery command
        wait(for: [testExpectation], timeout: 30)
        XCTAssertNotNil(pumpManager.state.pendingInsulinDeliveryCommand)
        XCTAssertEqual(pumpManager.lastSync, now)

        // reporting no status changes clears pending insulin delivery commands
        pump.state.setupCompleted = true
        let statusChangedFlags = IDStatusChangedFlag.allZeros
        var statusChangedData = Data(statusChangedFlags.rawValue)
        statusChangedData = TestE2EProtection().appendingE2EProtection(statusChangedData)
        pump.manageInsulinDeliveryStatusChangedData(statusChangedData)

        XCTAssertNotEqual(pumpManager.lastSync, now)
        XCTAssertNil(pumpManager.state.pendingInsulinDeliveryCommand)
        XCTAssertTrue(pumpManager.lastSync! > Date().addingTimeInterval(-1))
    }

    func testDeliveryIsUncertain() {
        XCTAssertFalse(pumpManager.status.deliveryIsUncertain)

        let testExpectation = expectation(description: #function)
        pumpManager.suspendDelivery(completion: { error in
            if let pumpManagerError = error as? PumpManagerError,
               case .uncertainDelivery = pumpManagerError
            {
                testExpectation.fulfill()
            } else {
                XCTAssert(false)
            }
        })
        waitOnThread()
        pump.prepareForNewPump() // reports disconnect to all pending procedures causing a pending insulin delivery command
        wait(for: [testExpectation], timeout: 30)
        XCTAssertNotNil(pumpManager.state.pendingInsulinDeliveryCommand)
        XCTAssertTrue(pumpManager.status.deliveryIsUncertain)
    }

    func testIsInReplacementWorkflow() {
        completedOnboarding()
        XCTAssertFalse(pumpManager.isInReplacementWorkflow)
        pumpManager.updateReplacementWorkflowState(milestoneProgress: [1], pumpSetupState: .authenticated)
        XCTAssertTrue(pumpManager.isInReplacementWorkflow)
    }

    func testPumpDidDetectHistoricalAnnunciation() {
        let now = Date()
        let bolusDeliveryStatus = BolusDeliveryStatus(id: 1, progressState: .canceled, type: .fast, insulinProgrammed: 2, insulinDelivered: 1, startTime: now.addingTimeInterval(-5), endTime: now)
        let annunciation = BolusCanceledAnnunciation(identifier: 123, bolusDeliveryStatus: bolusDeliveryStatus)
        let identifier = Alert.Identifier(managerIdentifier: pumpManager.pluginIdentifier, alertIdentifier: annunciation.alertIdentifier)

        alertExpectation = expectation(description: #function)
        alertExpectation?.expectedFulfillmentCount = 2
        pumpManager.pumpDidDetectHistoricalAnnunciation(pump, annunciation: annunciation, at: now)
        wait(for: [alertExpectation!], timeout: 30)
        XCTAssertEqual(retractedAlerts.first?.alertIdentifier, identifier)
        XCTAssertEqual(retractedAlerts.first?.retractedDate, now)
    }

    func testPumpDidDetectHistoricalAnnunciationAwaitingConfiguration() {
        // warnings (e.g., bolus cancelled annunciation) will not issue an alert
        let now = Date()
        let bolusDeliveryStatus = BolusDeliveryStatus(id: 1, progressState: .canceled, type: .fast, insulinProgrammed: 2, insulinDelivered: 1, startTime: now.addingTimeInterval(-5), endTime: now)
        let bolusCancelledAnnunciation = BolusCanceledAnnunciation(identifier: 123, bolusDeliveryStatus: bolusDeliveryStatus)
        pump.deviceInformation = DeviceInformation(identifier: UUID(), serialNumber: "12345678", pumpOperationalState: .waiting, reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan)

        alertExpectation = expectation(description: #function)
        alertExpectation?.expectedFulfillmentCount = 2
        pumpManager.pumpDidDetectHistoricalAnnunciation(pump, annunciation: bolusCancelledAnnunciation, at: now)
        wait(for: [alertExpectation!], timeout: 30)
        XCTAssertEqual(issuedAlerts.count, 0)

        let annunciation = GeneralAnnunciation(type: .reservoirEmpty, identifier: 123, status: .pending, auxiliaryData: Data())
        let annunciationIdentifier = Alert.Identifier(managerIdentifier: pumpManager.pluginIdentifier, alertIdentifier: annunciation.alertIdentifier)
        alertExpectation = expectation(description: #function)
        alertExpectation?.expectedFulfillmentCount = 2
        pumpManager.pumpDidDetectHistoricalAnnunciation(pump, annunciation: annunciation, at: now)
        wait(for: [alertExpectation!], timeout: 30)
        XCTAssertTrue(issuedAlerts.contains(where: { $0.alert.identifier == annunciationIdentifier }))
    }
    
    func testPumpDidDetectHistoricalAnnunciationBatteryErrorAlwaysRetracted() {
        let now = Date()
        let annunciation = GeneralAnnunciation(type: .batteryEmpty, identifier: 1, status: .pending, auxiliaryData: Data())
        let identifier = Alert.Identifier(managerIdentifier: pumpManager.pluginIdentifier, alertIdentifier: annunciation.alertIdentifier)

        alertExpectation = expectation(description: #function)
        alertExpectation?.expectedFulfillmentCount = 2
        pumpManager.pumpDidDetectHistoricalAnnunciation(pump, annunciation: annunciation, at: now)
        wait(for: [alertExpectation!], timeout: 30)
        XCTAssertEqual(retractedAlerts.first?.alertIdentifier, identifier)
        XCTAssertEqual(retractedAlerts.first?.retractedDate, now)
    }

    func testUncertainActiveTempBasal() {
        let testExpectation = expectation(description: #function)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 2, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)

        pumpIsConnected = false
        pumpManager.pumpConnectionStatusChanged(pump)
        XCTAssertEqual(pumpManager.state.unfinalizedTempBasal?.scheduledCertainty, .uncertain)

        pumpManager.pumpDidSync(pump)
        XCTAssertEqual(pumpManager.state.unfinalizedTempBasal?.scheduledCertainty, .certain)
    }
    
    func testPumpManagerDeleteRetractsAlerts() throws {
        let exp = expectation(description: #function)
        alertExpectation = expectation(description: "alert." + #function)
        alertExpectation?.assertForOverFulfill = false
        let expectedAlert = Alert(with: GeneralAnnunciation(type: .endOfPumpLifetime, identifier: 1, status: .pending, auxiliaryData: Data()), managerIdentifier: InsulinDeliveryPumpManager.managerIdentifier)
        pumpManager.issueAlert(expectedAlert)
        wait(for: [alertExpectation!], timeout: 30)

        XCTAssertEqual(expectedAlert, issuedAlerts.first?.alert)
        XCTAssertNil(retractedAlerts.first)
        
        alertExpectation = expectation(description: "alert2." + #function)
        alertExpectation?.assertForOverFulfill = false
        pumpManager.prepareForDeactivation { _ in
            exp.fulfill()
        }
        
        pump.respondToGetRemainingLifeTime()
        waitOnThread()
        
        pump.respondToInvalidateKey()
        waitOnThread()

        wait(for: [alertExpectation!, exp], timeout: 30)
                
        XCTAssertTrue(retractedAlerts.contains(where: { $0.alertIdentifier.alertIdentifier == expectedAlert.identifier.alertIdentifier }))
    }

    func testDoNotReportDosesOnPumpStateUpdate() {
        let testExpectation = expectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { error in
            XCTAssertNil(error)
            if error == nil {
                self.waitOnThread()
                testExpectation.fulfill()
            }
        }
        pump.respondToSetBolusWithSuccess(bolusID: 123)
        wait(for: [testExpectation], timeout: 30)

        // trigger a pump state update
        pump.setupDeviceInformation()
        newPumpEventsExpectation = expectation(description: #function)
        newPumpEventsExpectation?.isInverted = true
        wait(for: [newPumpEventsExpectation!], timeout: 1)
    }

    func testTrackBolusDelivery() {
        pump.setupDeviceInformation(therapyControlState: .run, pumpOperationalState: .ready)
        let bolusID: BolusID = 123
        let testExpectation = expectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToSetBolusWithSuccess(bolusID: bolusID)
        wait(for: [testExpectation], timeout: 30)

        let textExpectation1 = expectation(description: #function)
        var receivedBolusDeliveryStatus: BolusDeliveryStatus?
        pumpManager.updateBolusDeliveryDetails() { bolusDeliveryStatus in
            receivedBolusDeliveryStatus = bolusDeliveryStatus
            textExpectation1.fulfill()
        }

        var insulinDelivered: Double = 1
        pump.reportUpdatedBolusDelivery(bolusID: bolusID, insulinDelivered: insulinDelivered)
        wait(for: [textExpectation1], timeout: 30)
        XCTAssertEqual(receivedBolusDeliveryStatus?.insulinDelivered, insulinDelivered)
        XCTAssertEqual(receivedBolusDeliveryStatus?.progressState, .inProgress)

        let textExpectation2 = expectation(description: #function)
        pumpManager.updateBolusDeliveryDetails() { bolusDeliveryStatus in
            receivedBolusDeliveryStatus = bolusDeliveryStatus
            textExpectation2.fulfill()
        }
        insulinDelivered = 1.5
        pump.reportUpdatedBolusDelivery(bolusID: bolusID, insulinDelivered: insulinDelivered)
        wait(for: [textExpectation2], timeout: 30)
        XCTAssertEqual(receivedBolusDeliveryStatus?.insulinDelivered, insulinDelivered)
        XCTAssertEqual(receivedBolusDeliveryStatus?.progressState, .inProgress)

        // cancel bolus and tracking of delivery by stopping insulin delivery
        let textExpectation3 = expectation(description: #function)
        pumpManager.updateBolusDeliveryDetails() { bolusDeliveryStatus in
            receivedBolusDeliveryStatus = bolusDeliveryStatus
            textExpectation3.fulfill()
        }
        pump.sendInsulinDeliveryStatusData(therapyControlState: .stop, pumpOperationalState: .waiting)
        wait(for: [textExpectation3], timeout: 30)
        XCTAssertEqual(receivedBolusDeliveryStatus?.insulinDelivered, insulinDelivered)
        XCTAssertEqual(receivedBolusDeliveryStatus?.progressState, .canceled)
        XCTAssertEqual(pumpManager.state.unfinalizedBoluses[bolusID]?.wasCanceled, true)
    }

    func testSetPumpTime() {
        let newTimeZone = TimeZone(secondsFromGMT: 0)!
        var testExpectation = expectation(description: #function)
        pumpManager.setPumpTime(using: newTimeZone) { error in
            XCTAssertNil(error)
            XCTAssertEqual(self.pumpManager.state.timeZone, newTimeZone)
            testExpectation.fulfill()
        }

        pump.respondToSetTime()
        wait(for: [testExpectation], timeout: 30)

        testExpectation = expectation(description: #function)
        pumpManager.setPumpTime(using: .currentFixed) { error in
            XCTAssertEqual(error as? DeviceCommError, DeviceCommError.procedureNotCompleted)
            XCTAssertEqual(self.pumpManager.state.timeZone, newTimeZone)
            testExpectation.fulfill()
        }

        pump.respondToSetTime(responseCode: .operationFailed)
        wait(for: [testExpectation], timeout: 30)
    }

    func testCheckForPumpClockDrift() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date()
        let testExpectation = expectation(description: #function)
        pumpManager.setPumpTime(now, using: timeZone) { _ in
            XCTAssertEqual(self.pumpManager.state.timeZone, timeZone)
            testExpectation.fulfill()
        }
        pump.respondToSetTime()
        wait(for: [testExpectation], timeout: 30)

        // no clock drift
        pumpManager.checkForPumpClockDrift()
        pump.respondToGetTime(now, using: timeZone)
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("Got pump time") }))
        XCTAssertFalse(logEntryMessages.contains(where: { $0.contains("Pump clock drift detected.") }))

        // clock drift but also system time offset detected so time does not sync
        detectedSystemTimeOffset = .minutes(2)
        logEntryMessages.removeAll()
        pumpManager.checkForPumpClockDrift()
        pump.respondToGetTime(now.addingTimeInterval(.minutes(-2)), using: timeZone)
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("Got pump time") }))
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("Pump clock drift detected.") }))
        XCTAssertFalse(logEntryMessages.contains(where: { $0.contains("setPumpTime") }))

        // clock drift
        detectedSystemTimeOffset = 0
        logEntryMessages.removeAll()
        pumpManager.checkForPumpClockDrift()
        pump.respondToGetTime(now.addingTimeInterval(.minutes(-2)), using: timeZone)
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.expectedFulfillmentCount = 7
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("Got pump time") }))
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("Pump clock drift detected.") }))
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("setPumpTime") }))
    }

    func testCheckForTimeOffsetChange() {
        let currentSecondsFromGMT = TimeZone.current.secondsFromGMT()
        let timeZone = TimeZone(secondsFromGMT: currentSecondsFromGMT-(60*60))!
        let now = Date()
        let testExpectation = expectation(description: #function)
        pumpManager.setPumpTime(now, using: timeZone) { _ in
            XCTAssertEqual(self.pumpManager.state.timeZone, timeZone)
            testExpectation.fulfill()
        }
        pump.respondToSetTime()
        wait(for: [testExpectation], timeout: 30)

        pumpManager.checkForTimeOffsetChange()

        XCTAssertTrue(pumpManager.isClockOffset)
        pumpManager.checkForTimeOffsetChange()
        waitOnThread()

        alertExpectation = expectation(description: #function)
        alertExpectation?.assertForOverFulfill = false
        wait(for: [alertExpectation!], timeout: 30)
        XCTAssertTrue(issuedAlerts.contains (where: { $0.alert.identifier == pumpManager.timeZoneChangedAlertIdentifier }))
    }
    
    func testUpdateFromTempBasalToScheduleBasal() {
        let testExpectation = expectation(description: #function)
        let basalDeliveredBefore = 1
        let basalDeliveredAfter = 2
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 1.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)
        
        // mimic switching to active temp basal rate
        pump.issueActiveBasalRateChanged()
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredBefore)
        pump.respondToGetActiveBasalRate(scheduleBasalRate: 2.4, tempBasalRate: 1.0, tempBasalDuration: .minutes(30))
        waitOnThread()
        
        // mimic returning to scheduled basal rate
        pump.issueActiveBasalRateChanged()
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredAfter)
        pump.respondToGetActiveBasalRate(scheduleBasalRate: 2.4)
        
        XCTAssertNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertFalse(pumpManager.state.finalizedDoses.isEmpty)
        XCTAssertEqual(pumpManager.state.finalizedDoses.first?.units, Double(basalDeliveredAfter - basalDeliveredBefore))
    }
    
    func testSuspendInsulinDeliveryDuringTempBasal() {
        var testExpectation = expectation(description: #function)
        let basalDeliveredBefore = 1
        let basalDeliveredAfter = 2
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 1.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)

        // mimic switching to active temp basal rate
        pump.issueActiveBasalRateChanged()
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredBefore)
        pump.respondToGetActiveBasalRate(scheduleBasalRate: 2.4, tempBasalRate: 1.0, tempBasalDuration: .minutes(30))
        
        testExpectation = expectation(description: #function)
        pumpManager.suspendDelivery() { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredAfter)
        pump.respondToSetTherapyControlState(responseCode: .success, therapyControlState: .stop)
        wait(for: [testExpectation], timeout: 30)
        
        XCTAssertNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertFalse(pumpManager.state.finalizedDoses.isEmpty)
        XCTAssertEqual(pumpManager.state.finalizedDoses.first?.units, Double(basalDeliveredAfter - basalDeliveredBefore))
    }
    
    func testCancelTempBasal() {
        var testExpectation = expectation(description: #function)
        let basalDeliveredBefore = 1
        let basalDeliveredAfter = 2
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 1.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)

        // mimic switching to active temp basal rate
        pump.issueActiveBasalRateChanged()
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredBefore)
        pump.respondToGetActiveBasalRate(scheduleBasalRate: 2.4, tempBasalRate: 1.0, tempBasalDuration: .minutes(30))
        
        testExpectation = expectation(description: #function)
        pumpManager.cancelTempBasal() { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredAfter)
        pump.respondToCancelTempBasal()
        wait(for: [testExpectation], timeout: 30)
        
        XCTAssertNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertFalse(pumpManager.state.finalizedDoses.isEmpty)
        XCTAssertEqual(pumpManager.state.finalizedDoses.first?.units, Double(basalDeliveredAfter - basalDeliveredBefore))
    }
    
    func testSetTempBasalAdjustmentReplaceExisting() {
        var testExpectation = expectation(description: #function)
        let basalDeliveredBefore = 1
        let basalDeliveredAfter = 2
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 1.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)

        // mimic switching to active temp basal rate
        pump.issueActiveBasalRateChanged()
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredBefore)
        pump.respondToGetActiveBasalRate(scheduleBasalRate: 2.4, tempBasalRate: 1.0, tempBasalDuration: .minutes(30))
        
        testExpectation = expectation(description: #function)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 2.0, for: .minutes(30)) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToGetDeliveredInsulin(basalDelivered: basalDeliveredAfter)
        pump.respondToTempBasalAdjustmentWithSuccess()
        wait(for: [testExpectation], timeout: 30)
        
        XCTAssertNotNil(pumpManager.state.unfinalizedTempBasal)
        XCTAssertFalse(pumpManager.state.finalizedDoses.isEmpty)
        XCTAssertEqual(pumpManager.state.finalizedDoses.first?.units, Double(basalDeliveredAfter - basalDeliveredBefore))
    }
}

// MARK: pumpManagerStateObserverTests
extension InsulinDeliveryPumpManagerTests {

    class StateObserver: InsulinDeliveryPumpManagerStateObserver {
        weak var exp: XCTestExpectation?
        var state: InsulinDeliveryPumpManagerState?
        func pumpManagerDidUpdateState(_ pumpManager: InsulinDeliveryPumpManager, _ state: InsulinDeliveryPumpManagerState) {
            self.state = state
            exp?.fulfill()
        }
        init(_ exp: XCTestExpectation? = nil) {
            self.exp = exp
        }
    }

    func testPumpManagerStateObserverAddingObserverNoUpdate() throws {
        let exp = expectation(description: #function)
        let observer = StateObserver(exp)
        pumpManager.addPumpManagerStateObserver(observer, queue: .main)
        exp.isInverted = true
        wait(for: [exp], timeout: expectationTimeout)
        XCTAssertNil(observer.state)
    }
    
    func testPumpManagerStateObserverUpdates() throws {
        let exp = expectation(description: #function)
        let observer = StateObserver(exp)
        pumpManager.addPumpManagerStateObserver(observer, queue: .main)
        completedOnboarding()
        wait(for: [exp], timeout: expectationTimeout)
        XCTAssertEqual(true, observer.state?.onboardingCompleted)
    }
    
    func testPumpManagerStateObserverAddingRemovingObserverNoUpdate() throws {
        let exp = expectation(description: #function)
        exp.isInverted = true
        let observer = StateObserver(exp)
        pumpManager.addPumpManagerStateObserver(observer, queue: .main)
        wait(for: [exp], timeout: expectationTimeout)
        XCTAssertNil(observer.state)
        let exp2 = expectation(description: #function + "2")
        exp2.isInverted = true
        observer.exp = exp2
        pumpManager.removePumpManagerStateObserver(observer)
        completedOnboarding()
        wait(for: [exp2], timeout: expectationTimeout)
        XCTAssertNil(observer.state)
    }

}

// MARK: pumpManagerStatusObserverTests
extension InsulinDeliveryPumpManagerTests {

    class StatusObserver: PumpManagerStatusObserver {
        weak var exp: XCTestExpectation?
        var status: PumpManagerStatus?
        var oldStatus: PumpManagerStatus?
        func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
            self.status = status
            self.oldStatus = oldStatus
            exp?.fulfill()
        }
        init(_ exp: XCTestExpectation? = nil) {
            self.exp = exp
        }
    }

    func testPumpManagerStatusObserverAddingObserverNoUpdate() throws {
        let exp = expectation(description: #function)
        let observer = StatusObserver(exp)
        pumpManager.addStatusObserver(observer, queue: .main)
        exp.isInverted = true
        wait(for: [exp], timeout: expectationTimeout)
        XCTAssertNil(observer.status)
        XCTAssertNil(observer.oldStatus)
    }
    
    func testPumpManagerStatusObserverUpdates() throws {
        completedOnboarding()
        let exp = expectation(description: #function)
        let observer = StatusObserver(exp)
        pumpManager.addStatusObserver(observer, queue: .main)
        let expected = AnnunciationType.occlusionDetected
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        pump.setTherapyControlStateTo(.stop)
        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [exp], timeout: expectationTimeout)
        XCTAssertNotNil(observer.status)
    }
    
    func testPumpManagerStatusObserverUpdatesInsulinSuspended() throws {
        let exp = expectation(description: #function)
        exp.expectedFulfillmentCount = 3
        let observer = StatusObserver(exp)
        pumpManager.addStatusObserver(observer, queue: .main)
        let expected = AnnunciationType.occlusionDetected
        let annunciation = GeneralAnnunciation(type: expected, identifier: 1, status: .pending, auxiliaryData: Data())
        let exp2 = XCTestExpectation(description: "suspend." + #function)
        pump.suspendInsulinDeliveryResult = .success(nil)
        pumpManager.suspendDelivery { _ in exp2.fulfill() }
        wait(for: [exp2], timeout: expectationTimeout)
        alertExpectation = expectation(description: "alert." + #function)
        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        wait(for: [alertExpectation!, exp], timeout: expectationTimeout)
        XCTAssertNotNil(observer.status)
        XCTAssertEqual(observer.status?.basalDeliveryState, .pumpInoperable)
    }

    func testStatusUpdateForDifferentDevices() {
        statusUpdates = []
        pump.deviceInformation = DeviceInformation(identifier: UUID(), serialNumber: "test1234", reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan)
        statusUpdateExpectation = expectation(description: #function)
        statusUpdateExpectation?.expectedFulfillmentCount = 2
        statusUpdateExpectation?.assertForOverFulfill = false
        wait(for: [statusUpdateExpectation!], timeout: 30)
        XCTAssertNotNil(statusUpdates.last?.status.device)
        XCTAssertNotNil(statusUpdates.last?.oldStatus.device)
        XCTAssertNotEqual(statusUpdates.last?.status.device, statusUpdates.last?.oldStatus.device)
    }

    func testStatusUpdateForDifferentBasalDeliveryState() {
        statusUpdates = []
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 2.0, for: .minutes(30), completion: { _ in })
        statusUpdateExpectation = expectation(description: #function)
        statusUpdateExpectation?.expectedFulfillmentCount = 2
        statusUpdateExpectation?.assertForOverFulfill = false
        wait(for: [statusUpdateExpectation!], timeout: 30)
        XCTAssertNotNil(statusUpdates.last?.status.basalDeliveryState)
        XCTAssertNotNil(statusUpdates.last?.oldStatus.basalDeliveryState)
        XCTAssertNotEqual(statusUpdates.last?.status.basalDeliveryState, statusUpdates.last?.oldStatus.basalDeliveryState)
    }

    func testStatusUpdateForDifferentBolusState() {
        pumpManager.enactBolus(decisionId: nil, units: 1, activationType: .manualRecommendationAccepted, completion: { _ in })
        statusUpdateExpectation = expectation(description: #function)
        statusUpdateExpectation?.expectedFulfillmentCount = 2
        statusUpdateExpectation?.assertForOverFulfill = false
        wait(for: [statusUpdateExpectation!], timeout: 30)
        XCTAssertNotNil(statusUpdates.last?.status.bolusState)
        XCTAssertNotNil(statusUpdates.last?.oldStatus.bolusState)
        XCTAssertNotEqual(statusUpdates.last?.status.bolusState, statusUpdates.last?.oldStatus.bolusState)
    }

    func testStatusUpdateForDifferentDeliveryIsUncertain() {
        pumpManager.enactBolus(decisionId: nil, units: 1, activationType: .manualRecommendationAccepted, completion: { _ in })
        pump.handleCBError(CBError(.peripheralDisconnected))
        statusUpdateExpectation = expectation(description: #function)
        statusUpdateExpectation?.expectedFulfillmentCount = 2
        statusUpdateExpectation?.assertForOverFulfill = false
        wait(for: [statusUpdateExpectation!], timeout: 30)
        XCTAssertEqual(statusUpdates.last?.status.deliveryIsUncertain, true)
        XCTAssertEqual(statusUpdates.last?.oldStatus.deliveryIsUncertain, false)
        XCTAssertNotEqual(statusUpdates.last?.status.deliveryIsUncertain, statusUpdates.last?.oldStatus.deliveryIsUncertain)
    }

    func testStoreCurrentPumpRemainingLifetime() {
        pumpManager.storeCurrentPumpRemainingLifetime()
        XCTAssertFalse(pumpManager.state.previousPumpRemainingLifetime.isEmpty)
        XCTAssertNotNil(pumpManager.state.previousPumpRemainingLifetime[pump.deviceInformation?.serialNumber ?? ""])
    }
}

// MARK: Logging Tests
extension InsulinDeliveryPumpManagerTests {
    func testLoggingPrepareForDeactivation() {
        pumpManager.prepareForDeactivation() { _ in }
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertFalse(logEntryMessages.filter({ $0.contains("prepareForDeactivation") }).isEmpty)
        XCTAssertFalse(logEntryMessages.filter({ $0.contains("getRemainingLifetime") }).isEmpty)
    }

    func testLoggingResolvedUncertainBolus() {
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { error in
            if  let pumpManagerError = error,
                case .uncertainDelivery = pumpManagerError
            {
                XCTAssert(true)
            } else {
                XCTAssert(false)
            }
        }
        waitOnThread()
        pump.prepareForNewPump() // reports disconnect to all pending procedures causing a pending insulin delivery command
        waitOnThread()

        pumpManager.pumpDidInitiateBolus(pump, bolusID: 123, insulinProgrammed: 2, startTime: Date())
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpDidInitiateBolus") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("Resolved pending enact bolus command") ?? false)
    }

    func testLoggingBolusDelivered() {
        pumpManager.pumpDidDeliverBolus(pump, bolusID: 123, insulinProgrammed: 2, insulinDelivered: 2, startTime: Date(), duration: 2)
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertFalse(logEntryMessages.filter({ $0.contains("pumpDidDeliverBolus")}).isEmpty)
        XCTAssertFalse(logEntryMessages.filter({$0.contains("Bolus has completed delivery")}).isEmpty)
    }

    func testLoggingResolvedUncertainCancelBolus() {
        var testExpectation = expectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: 2, activationType: .manualRecommendationAccepted) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        waitOnThread()
        pump.respondToSetBolusWithSuccess(bolusID: 123)
        wait(for: [testExpectation], timeout: 30)

        testExpectation = expectation(description: #function)
        pumpManager.cancelBolus() { result in
            switch result {
            case .success(_):
                XCTAssert(false)
            case .failure(let error):
                if case .uncertainDelivery = error {
                    testExpectation.fulfill()
                } else {
                    XCTAssert(false)
                }
            }
        }
        waitOnThread()
        pump.prepareForNewPump() // reports disconnect to all pending procedures causing a pending insulin delivery command
        wait(for: [testExpectation], timeout: 30)

        pumpManager.pumpDidDeliverBolus(pump, bolusID: 123, insulinProgrammed: 2, insulinDelivered: 2, startTime: Date(), duration: 2)
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpDidDeliverBolus") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("Resolved pending cancel bolus command") ?? false)
    }

    func testLoggingResolvedUncertainTempBasal() {
        let testExpectation = expectation(description: #function)
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 4, for: .minutes(30)) { error in
            if let pumpManagerError = error,
                case .uncertainDelivery = pumpManagerError
            {
                testExpectation.fulfill()
            } else {
                XCTAssert(false)
            }
        }
        waitOnThread()
        pump.prepareForNewPump() // reports disconnect to all pending procedures causing a pending insulin delivery command
        wait(for: [testExpectation], timeout: 30)

        pumpManager.pumpTempBasalStarted(pump, at: Date(), rate: 4, duration: .minutes(30))
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpTempBasalStarted") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("Resolved pending enact temp basal command") ?? false)
    }

    func testLoggingResolvedUncertainCancelTempBasal() {
        pumpManager.enactTempBasal(decisionId: nil, unitsPerHour: 4, for: .minutes(30)) { _ in}
        pump.respondToTempBasalAdjustmentWithSuccess()
        pumpManager.cancelTempBasal() { error in
            if let pumpManagerError = error,
                case .uncertainDelivery = pumpManagerError
            {
                XCTAssert(true)
            } else {
                XCTAssert(false)
            }
        }
        waitOnThread()
        pump.prepareForNewPump() // reports disconnect to all pending procedures causing a pending insulin delivery command
        waitOnThread()

        pumpManager.pumpTempBasalEnded(pump, duration: .minutes(10))
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.expectedFulfillmentCount = 2
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpTempBasalEnded") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("Temp basal completed") ?? false)
        XCTAssertTrue(logEntryMessages[logEntryMessages.count-2].contains("Resolved pending cancel temp basal command")) // second last message is the resolved message
    }

    func testLoggingResolvedUnfinalizedSuspend() {
        let testExpectation = expectation(description: #function)
        pump.setupDeviceInformation()
        pumpManager.resumeDelivery() { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToSetTherapyControlState(therapyControlState: .run)
        wait(for: [testExpectation], timeout: 30)

        pump.deviceInformation?.therapyControlState = .stop
        waitOnThread()

        pumpManager.pumpDidSuspendInsulinDelivery(pump, suspendedAt: Date())
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpDidSuspendInsulinDelivery") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("suspendedAt") ?? false)
    }

    func testLoggingHistoricalAnnunciation() {
        pumpManager.pumpDidDetectHistoricalAnnunciation(pump, annunciation: GeneralAnnunciation(type: .endOfPumpLifetime, identifier: 123, status: .pending, auxiliaryData: Data()), at: Date())
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.expectedFulfillmentCount = 2
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages[logEntryMessages.count-2].contains("pumpDidDetectHistoricalAnnunciation"))
        XCTAssertTrue(logEntryMessages[logEntryMessages.count-2].contains("Detected annunciation that was not reported"))
        XCTAssertTrue(logEntryMessages.last?.contains("reportRetractedAnnunciation") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("Reporting retracted annunciation") ?? false)
    }

    func testLoggingPumpDidSync() {
        pumpManager.pumpDidSync(pump)
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("pumpDidSync") }))
    }

    func testLoggingPumpConnectionStatusChanged() {
        pumpManager.pumpConnectionStatusChanged(pump)
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpConnectionStatusChanged") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("isPumpConnected") ?? false)
    }

    func testLoggingPumpDiscovered() {
        pumpManager.pump(pump, didDiscoverPumpWithName: nil, identifier: UUID(), serialNumber: nil)
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("didDiscoverPumpWithName") ?? false)
    }

    func testLoggingPumpDidCompleteAuthentication() {
        pumpManager.pumpDidCompleteAuthentication(pump, error: nil)
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpDidCompleteAuthentication") ?? false)
    }

    func testLoggingPumpDidCompleteAuthenticationWithError() {
        pumpManager.pumpDidCompleteAuthentication(pump, error: .authenticationFailed)
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpDidCompleteAuthentication") ?? false)
        XCTAssertTrue(logEntryMessages.last?.contains("\(DeviceCommError.authenticationFailed)") ?? false)
    }

    func testLoggingPumpDidCompleteConfiguration() {
        pumpManager.pumpDidCompleteConfiguration(pump)
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpDidCompleteConfiguration") ?? false)
    }

    func testLoggingPumpDidCompleteTherapyUpdate() {
        pumpManager.pumpDidCompleteTherapyUpdate(pump)
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("pumpDidCompleteTherapyUpdate") ?? false)
    }

    func testLoggingPumpDidReceiveAnnunciation() {
        pumpManager.pump(pump, didReceiveAnnunciation: GeneralAnnunciation(type: .endOfPumpLifetime, identifier: 123, status: .pending, auxiliaryData: Data()))
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("didReceiveAnnunciation") }))
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("\(AnnunciationType.endOfPumpLifetime)") }))
    }

    func testLoggingHandleBolusCancelledAnnunciation() {
        let bolusID: BolusID = 123
        let programmedAmount = 2.0
        let deliveredAmount = 1.0
        var testExpectation = expectation(description: #function)
        pumpManager.enactBolus(decisionId: nil, units: programmedAmount, activationType: .manualRecommendationAccepted) { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }
        pump.respondToSetBolusWithSuccess(bolusID: bolusID)
        wait(for: [testExpectation], timeout: 30)

        testExpectation = expectation(description: #function)
        pumpManager.cancelBolus() { result in
            switch result {
            case .success(_):
                testExpectation.fulfill()
            default:
                XCTAssert(false)
            }
        }
        pump.respondToCancelBolusWithSuccess(bolusID: bolusID)
        
        logEntryMessages = []
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        loggingExpectation?.expectedFulfillmentCount = 8
        
        pump.sendBolusCancelledAnnunciation(bolusID: bolusID, programmedAmount: programmedAmount, deliveredAmount: deliveredAmount)

        wait(for: [testExpectation, loggingExpectation!], timeout: 30)
        XCTAssertNotNil(logEntryMessages.first(where: { message in message.contains("BolusCanceledAnnunciation") }))
        XCTAssertNotNil(logEntryMessages.first(where: { message in message.contains("handleReceivedBolusCanceledAnnunciation") }))
        XCTAssertNotNil(logEntryMessages.first(where: { message in message.contains("Auto-confirming bolusCanceled, id \(bolusID)") }))
        XCTAssertNotNil(logEntryMessages.first(where: { message in message.contains("autoConfirmAnnunciation") }))
        XCTAssertNotNil(logEntryMessages.first(where: { message in message.contains("confirmAnnunciation") }))
        XCTAssertNotNil(logEntryMessages.first(where: { message in message.contains("reportRetractedAnnunciation") }))
    }

    func testLoggingIssueAlert() {
        let annunciation = GeneralAnnunciation(type: .endOfPumpLifetime, identifier: 123, status: .pending, auxiliaryData: Data())
        pumpManager.issueAlert(Alert(with: annunciation, managerIdentifier: pumpManager.pluginIdentifier))
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("issueAlert") ?? false)
    }

    func testLoggingRetractAlert() {
        let annunciation = GeneralAnnunciation(type: .endOfPumpLifetime, identifier: 123, status: .pending, auxiliaryData: Data())
        pumpManager.retractAlert(identifier: Alert.Identifier(managerIdentifier: pumpManager.pluginIdentifier, alertIdentifier: annunciation.alertIdentifier))
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("retractAlert") ?? false)
    }

    func testLoggingAcknowledgeAlert() {
        pumpManager.acknowledgeAlert(alertIdentifier: pumpManager.insulinSuspensionReminderAlertIdentifier.alertIdentifier) { _ in }
        loggingExpectation = expectation(description: #function)
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.last?.contains("acknowledgeAlert") ?? false)
    }

    func testLoggingPrepareForNewPump() {
        loggingExpectation = expectation(description: #function)
        loggingExpectation?.assertForOverFulfill = false
        pumpManager.prepareForNewPump()
        wait(for: [loggingExpectation!], timeout: 30)
        XCTAssertTrue(logEntryMessages.contains(where: { $0.contains("prepareForNewPump") }))
    }
}

extension InsulinDeliveryPumpManagerTests {
    func waitOnThread() {
        let exp = expectation(description: "waitOnThread")
        pumpManager.delegateQueue.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: expectationTimeout)
    }
    
    func completedOnboarding() {
        pumpManager.markOnboardingCompleted()
        waitOnThread() // allow threaded updates to occur
    }
    
    func completeReplacementWorkflow() {
        pumpManager.replacementWorkflowCompleted()
        waitOnThread() // allow threaded updates to occur
    }
}

// MARK: PumpManagerDelegate
extension InsulinDeliveryPumpManagerTests: PumpManagerDelegate {
    var automatedTreatmentState: LoopKit.AutomatedTreatmentState? { nil }
    
    var automaticDosingEnabled: Bool { true }

    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) { }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) { }
    
    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool { return false }
    
    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        pumpManagerWillDeactivateCalled = true
    }
    
    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) { }

    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        lastError = error
    }
    
    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastReconciliation: Date?, replacePendingEvents: Bool, completion: @escaping (Error?) -> Void) {
        newPumpEvents.removeAll()
        newPumpEvents.append(contentsOf: events)
        newPumpEventsExpectation?.fulfill()
        completion(nil)
    }
    
    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (_ result: Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void) { }
    
    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) { }
    
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) { }
    
    func pumpManager(_ pumpManager: PumpManager, didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    
    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date { return Date() }
    
    func scheduleNotification(for manager: DeviceManager, identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) { }
    
    func clearNotification(for manager: DeviceManager, identifier: String) { }
    
    func removeNotificationRequests(for manager: DeviceManager, identifiers: [String]) { }
    
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        logEntryType = type
        logEntryMessages.append(message)
        logEntryIdentifier = deviceIdentifier
        completion?(nil)
        loggingExpectation?.fulfill()
    }
    
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        statusUpdates.append((status: status, oldStatus: oldStatus))
        statusUpdateExpectation?.fulfill()
    }
    
    func issueAlert(_ alert: Alert) {
        issuedAlerts.append((alert: alert, issuedDate: now))
        alertExpectation?.fulfill()
    }
    
    func retractAlert(identifier: Alert.Identifier) {
        retractedAlerts.append((alertIdentifier: identifier, retractedDate: now))
        alertExpectation?.fulfill()
    }

    func doesIssuedAlertExist(identifier: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(issuedAlerts.contains(where: { $0.alert.identifier == identifier })))
        alertExpectation?.fulfill()
    }

    func recordRetractedAlert(_ alert: Alert, at date: Date) {
        retractedAlerts.append((alert.identifier, date))
        alertExpectation?.fulfill()
    }

    func recordIssued(alert: Alert, at date: Date, completion: ((Result<Void, Error>) -> Void)?) {
        issuedAlerts.append((alert, date))
        alertExpectation?.fulfill()
        completion?(.success)
    }

    func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void) {
        
        let alerts = issuedAlerts.filter { (alert: Alert, issuedDate: Date) in
            return !retractedAlerts.contains(where: { (alertIdentifier: Alert.Identifier, retractedDate: Date) in
                return alert.identifier == alertIdentifier
            })
        }
        
        completion(.success(alerts.map { PersistedAlert(alert: $0.alert, issuedDate: $0.issuedDate, retractedDate: nil, acknowledgedDate: nil) }))
        lookupExpectation?.fulfill()
    }

    // For now, this does exactly the same as above...
    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String, completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void) {
        
        let alerts = issuedAlerts.filter { (alert: Alert, issuedDate: Date) in
            return !retractedAlerts.contains(where: { (alertIdentifier: Alert.Identifier, retractedDate: Date) in
                return alert.identifier == alertIdentifier
            })
        }
        
        completion(.success(alerts.map { PersistedAlert(alert: $0.alert, issuedDate: $0.issuedDate, retractedDate: nil, acknowledgedDate: nil) }))
        lookupExpectation?.fulfill()
    }
}

class TestE2EProtection: E2EProtection {
    var e2eDelegate: (any BluetoothCommonKit.E2EProtectionDelegate)?
    
    var e2eCounter: UInt8 = 1
}
