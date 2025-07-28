//
//  SettingsViewModelTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Nathaniel Hamming on 2020-05-13.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import XCTest
import CoreBluetooth
import LoopAlgorithm
import LoopKit
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class SettingsViewModelTests: XCTestCase {

    private var viewModel: SettingsViewModel!
    private var pumpManager: InsulinDeliveryPumpManager!
    private var mockNavigator: MockNavigator!
    private var pumpIsConnected = true
    private var pump: InsulinDeliveryPump!
    private var pumpState: IDPumpState!
    private var basalRateSchedule: BasalRateSchedule!
    private var deviceInformation: DeviceInformation!

    private let identifier = UUID()
    private let serialNumber: String = "SerialNumber"
    private let firmwareRevision: String = "FirmwareRevision"
    private let hardwareRevision: String = "HardwareRevision"
    private let batteryLevel: Int = 50

    private var mockKeychainManager: MockKeychainManager!

    override func setUp() {
        mockNavigator = MockNavigator()
        mockKeychainManager = MockKeychainManager()
        deviceInformation = DeviceInformation(identifier: identifier,
                                              serialNumber: serialNumber,
                                              firmwareRevision: firmwareRevision,
                                              hardwareRevision: hardwareRevision,
                                              batteryLevel: batteryLevel)
        let uuidToHandleMap: [CBUUID: UInt16] = [DeviceInfoCharacteristicUUID.firmwareRevisionString.cbUUID: 1,
                                                 DeviceInfoCharacteristicUUID.hardwareRevisionString.cbUUID: 2,
                                                 BatteryCharacteristicUUID.batteryLevel.cbUUID: 3,
                                                 InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID: 4,
                                                 InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID: 5]
        pumpState = IDPumpState(deviceInformation: deviceInformation, uuidToHandleMap: uuidToHandleMap)
        let securityManager = SecurityManager(securePersistentPumpAuthentication: { self.mockKeychainManager }, sharedKeyData: Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f")!)
        let bluetoothManager = BluetoothManager(restoreOptions: nil)
        bluetoothManager.peripheralManager = PeripheralManager()
        let acControlPoint = ACControlPoint(securityManager: securityManager, maxRequestSize: 19)
        let acData = ACData(securityManager: securityManager, maxRequestSize: 19)
        let bolusManager = BolusManager()
        let pumpHistoryEventManager = PumpHistoryEventManager()
        pump = pump(bluetoothManager: bluetoothManager,
                    bolusManager: bolusManager,
                    basalManager: BasalManager(),
                    pumpHistoryEventManager: pumpHistoryEventManager,
                    securityManager: securityManager,
                    acControlPoint: acControlPoint,
                    acData: acData,
                    state: pumpState,
                    isConnectedHandler: { self.pumpIsConnected })

        basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 0)])!
        pumpManager = InsulinDeliveryPumpManager(state: InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule, maxBolusUnits: 10.0, pumpState: pumpState), pump: pump)
        
        viewModel = SettingsViewModel(pumpManager: pumpManager,
                                      navigator: mockNavigator,
                                      completionHandler: { })
    }

    func testInitialization() {
        XCTAssertEqual(viewModel.deviceInformation, deviceInformation)
        XCTAssertEqual(viewModel.expiryWarningDuration, pumpManager.pumpConfiguration.expiryWarningDuration)
        XCTAssertEqual(viewModel.expiryReminderRepeat, .never)
    }
    
    func testUpdateDeviceInformation() {
        XCTAssertEqual(viewModel.deviceInformation?.serialNumber, serialNumber)

        let anotherSerialNumber = "AnotherSerialNumber"
        updateDeviceInformation(serialNumber: anotherSerialNumber)
        XCTAssertEqual(viewModel.deviceInformation?.serialNumber, anotherSerialNumber)

        updateDeviceInformation(firmwareRevision: nil)
        XCTAssertNil(viewModel.deviceInformation?.firmwareRevision)

        let anotherFirmwareRevision = "AnotherFirmwareRevision"
        updateDeviceInformation(firmwareRevision: anotherFirmwareRevision)
        XCTAssertEqual(viewModel.deviceInformation?.firmwareRevision, anotherFirmwareRevision)

        updateDeviceInformation(hardwareRevision: nil)
        XCTAssertNil(viewModel.deviceInformation?.hardwareRevision)

        let anotherHardwareRevision = "AnotherHardwareRevision"
        updateDeviceInformation(hardwareRevision: anotherHardwareRevision)
        XCTAssertEqual(viewModel.deviceInformation?.hardwareRevision, anotherHardwareRevision)

        updateDeviceInformation(batteryLevel: nil)
        XCTAssertNil(viewModel.deviceInformation?.batteryLevel)

        let anotherBatteryLevel = 99
        updateDeviceInformation(batteryLevel: anotherBatteryLevel)
        XCTAssertEqual(viewModel.deviceInformation?.batteryLevel, anotherBatteryLevel)
    }

    func testReplacePartsSelected() {
        viewModel.replacePartsSelected()
        XCTAssertEqual(mockNavigator.currentScreen, .replaceParts)
    }

    func testAllowedExpiryWarningDurations() {
        var expectedExpiryWarningDurations: [TimeInterval] = []
        for days in 4...30 {
            expectedExpiryWarningDurations.append(.days(days))
        }
        XCTAssertEqual(viewModel.allowedExpiryWarningDurations, expectedExpiryWarningDurations)
    }

    func testAllowedLowReservoirWarningThresholds() {
        let expectedExpiryWarningDurations = Array(stride(from: 5, through: 40, by: 5))
        XCTAssertEqual(viewModel.allowedLowReservoirWarningThresholdsInUnits, expectedExpiryWarningDurations)
    }

    func testInitInfusionAssemblyReplacementReminderSettings() {
        XCTAssertEqual(NotificationSetting(), viewModel.infusionAssemblyReplacementReminderSettings)
    }
    
    func testSaveInfusionAssemblyReplacementReminderSettings() throws {
        let testExpectation = XCTestExpectation()
        pumpManager.lastReplacementDates = ComponentDates(infusionAssembly: .distantPast, reservoir: .distantPast, pumpBase: .distantPast)
        let midnight = NotificationSetting.TimeOfDay(hour: 0, minute: 0)
        let setting = try NotificationSetting(isEnabled: true, repeatDays: 1, timeOfDay: midnight)
        viewModel.saveInfusionAssemblyReplacementReminderSettings(setting, { _ in
            testExpectation.fulfill()
        })

        wait(for: [testExpectation], timeout: 30)

        XCTAssertEqual(setting, viewModel.infusionAssemblyReplacementReminderSettings)
        XCTAssertEqual(setting, pumpManager.notificationSettingsState.infusionReplacementReminder)
    }

    func testInsulinStartSoundsLabel() {
        viewModel.insulinStartSoundsEnabled = true
        XCTAssertTrue(viewModel.insulinStartSoundsLabel.contains("Disable"))
        viewModel.transitioningInsulinStartSounds = true
        XCTAssertTrue(viewModel.insulinStartSoundsLabel.contains("Disabling"))
        viewModel.insulinStartSoundsEnabled = false
        XCTAssertTrue(viewModel.insulinStartSoundsLabel.contains("Enabling"))
        viewModel.transitioningInsulinStartSounds = false
        XCTAssertTrue(viewModel.insulinStartSoundsLabel.contains("Enable"))
    }

    func testIsInsulinDeliverySuspendedByUser() throws {
        XCTAssertEqual(viewModel.suspendedAt, pumpManager.suspendedAt)
        XCTAssertFalse(viewModel.isInsulinDeliverySuspendedByUser)
    }
     
    func testIsInsulinDeliverySuspendedByUserActuallySuspended() throws {
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule, maxBolusUnits: 10.0, pumpState: pumpState)
        state.suspendState = .suspended(Date.distantPast)
        pumpManager = InsulinDeliveryPumpManager(state: state, pump: pump)
        viewModel = SettingsViewModel(pumpManager: pumpManager,
                                      navigator: mockNavigator,
                                      completionHandler: { })
        XCTAssertTrue(viewModel.isInsulinDeliverySuspended)
        XCTAssertTrue(viewModel.isInsulinDeliverySuspendedByUser)
        XCTAssertEqual(viewModel.isInsulinDeliverySuspended, pumpManager.isSuspended)
    }
    
    func testIsInsulinDeliverySuspendedByUserWithComponentsNeedingReplacement() throws {
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule, maxBolusUnits: 10.0, pumpState: pumpState)
        state.replacementWorkflowState.componentsNeedingReplacement = [.infusionAssembly: .forced]
        state.suspendState = .suspended(Date.distantPast)
        pumpManager = InsulinDeliveryPumpManager(state: state, pump: pump)
        viewModel = SettingsViewModel(pumpManager: pumpManager,
                                          navigator: mockNavigator,
                                          completionHandler: { })
        XCTAssertTrue(viewModel.isInsulinDeliverySuspended)
        XCTAssertFalse(viewModel.isInsulinDeliverySuspendedByUser)
        XCTAssertEqual(viewModel.isInsulinDeliverySuspended, pumpManager.isSuspended)
    }
    
    func testInsulinDeliveryDisabled() throws {
        pumpManager.pump.state.deviceInformation?.pumpOperationalState = .ready
        XCTAssertFalse(viewModel.insulinDeliveryDisabled)
        viewModel.transitioningSuspendResumeInsulinDelivery = true
        XCTAssertTrue(viewModel.insulinDeliveryDisabled)
        viewModel.transitioningSuspendResumeInsulinDelivery = false
        XCTAssertFalse(viewModel.insulinDeliveryDisabled)
    }
    
    func testInsulinDeliveryDisabledWithComponentsNeedingReplacement() throws {
        pumpManager.pump.state.deviceInformation?.pumpOperationalState = .ready
        XCTAssertFalse(viewModel.insulinDeliveryDisabled)
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule, maxBolusUnits: 10.0, pumpState: pumpState)
        state.replacementWorkflowState.componentsNeedingReplacement = [.infusionAssembly: .forced]
        pumpManager = InsulinDeliveryPumpManager(state: state, pump: pump)
        viewModel = SettingsViewModel(pumpManager: pumpManager,
                                          navigator: mockNavigator,
                                          completionHandler: { })
        XCTAssertTrue(viewModel.insulinDeliveryDisabled)
    }
    
    func testSuspendResumeInsulinDeliveryLabel() {
        viewModel.suspendedAt = nil
        XCTAssertTrue(viewModel.suspendResumeInsulinDeliveryStatus.localizedLabel.contains("Suspend"))
        viewModel.transitioningSuspendResumeInsulinDelivery = true
        XCTAssertTrue(viewModel.suspendResumeInsulinDeliveryStatus.localizedLabel.contains("Suspending"))
        viewModel.suspendedAt = Date()
        XCTAssertTrue(viewModel.suspendResumeInsulinDeliveryStatus.localizedLabel.contains("Resuming"))
        viewModel.transitioningSuspendResumeInsulinDelivery = false
        XCTAssertTrue(viewModel.suspendResumeInsulinDeliveryStatus.localizedLabel.contains("Resume"))
    }

    func testSuspendResumeInsulinDeliverySelected() {
        // resume insulin delivery
        var testExpectation = XCTestExpectation(description: #function + "resume insulin delivery")
        viewModel.resumeInsulinDelivery(completion: { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        })
        waitOnMain()

        var response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.setTherapyControlState.rawValue)
        response.append(IDControlPointResponseCode.success.rawValue)
        response.append(pump.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        pump.manageInsulinDeliveryControlPointResponse(response)
        wait(for: [testExpectation], timeout: 30)

        XCTAssertFalse(viewModel.isInsulinDeliverySuspended)
        XCTAssertNil(viewModel.suspendedAtString)

        // suspend insulin delivery
        testExpectation = XCTestExpectation(description: #function + "suspend insulin delivery")
        XCTAssertFalse(viewModel.isInsulinDeliverySuspended)
        viewModel.suspendInsulinDelivery(reminderDelay: .minutes(30), completion: { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        })
        waitOnMain()

        response = Data(IDStatusReaderOpcode.getDeliveredInsulinResponse.rawValue)
        response.append(UInt32(0))
        response.append(UInt32(0))
        response.append(pump.insulinDeliveryStatusReader.e2eCounter)
        response = response.appendingCRC()
        pump.manageInsulinDeliveryStatusReaderResponse(response)
        
        response = Data(IDControlPointOpcode.responseCode.rawValue)
        response.append(IDControlPointOpcode.setTherapyControlState.rawValue)
        response.append(IDControlPointResponseCode.success.rawValue)
        response.append(pump.insulinDeliveryControlPoint.e2eCounter)
        response = response.appendingCRC()

        pump.manageInsulinDeliveryControlPointResponse(response)
        wait(for: [testExpectation], timeout: 30)

        XCTAssertTrue(viewModel.isInsulinDeliverySuspended)
        XCTAssertNotNil(viewModel.suspendedAtString)
    }

    func testIsMuteWarningsActive() {
        XCTAssertEqual(viewModel.isMuteWarningsActive, pumpManager.isMuteWarningsActive)
    }

    func testMuteWarningsEnabled() {
        XCTAssertEqual(viewModel.muteWarningsEnabled, pumpManager.muteWarningsEnabled)
    }

    func testMuteWarningsStartTime() {
        XCTAssertEqual(viewModel.muteWarningsStartTime, pumpManager.muteWarningsStartTime)
    }

    func testMuteWarningsEndTime() {
    XCTAssertEqual(viewModel.muteWarningsEndTime, pumpManager.muteWarningsEndTime)
    }

    func testMuteWarningsDailyFrequency() {
        XCTAssertEqual(viewModel.muteWarningsDailyFrequency, pumpManager.muteWarningsDailyFrequency)
    }

    func testUpdateState() {
        // suspend insulin delivery
        pumpManager.pump.state.deviceInformation?.pumpOperationalState = .ready
        pumpManager.pump.state.deviceInformation?.therapyControlState = .stop
        pumpManager.pumpDidUpdateState(pumpManager.pump)
        waitOnMain()

        XCTAssertEqual(viewModel.expiryWarningDuration, pumpManager.pumpConfiguration.expiryWarningDuration)
        XCTAssertEqual(viewModel.lowReservoirWarningThresholdInUnits, pumpManager.lowReservoirWarningThresholdInUnits)
        XCTAssertEqual(viewModel.insulinStartSoundsEnabled, pumpManager.insulinStartSoundsEnabled)
        XCTAssertEqual(viewModel.suspendedAt, pumpManager.suspendedAt)
        XCTAssertEqual(viewModel.muteWarningsEnabled, pumpManager.muteWarningsEnabled)
        XCTAssertEqual(viewModel.muteWarningsStartTime, pumpManager.muteWarningsStartTime)
        XCTAssertEqual(viewModel.muteWarningsEndTime, pumpManager.muteWarningsEndTime)
        XCTAssertEqual(viewModel.muteWarningsDailyFrequency, pumpManager.muteWarningsDailyFrequency)

        pumpManager.pump.state.configuration.expiryWarningDuration = .days(20)
        pumpManager.pump.state.configuration.reservoirLevelWarningThresholdInUnits = 10
        pumpManager.pump.state.configuration.startInsulinDeliverySoundEnabled = true
        pumpManager.pump.state.deviceInformation?.therapyControlState = .run
        pumpManager.pump.state.configuration.muteWarningsConfiguration.enabled = true
        pumpManager.pump.state.configuration.muteWarningsConfiguration.startTime = Date()
        pumpManager.pump.state.configuration.muteWarningsConfiguration.duration = .minutes(5)
        pumpManager.pump.state.configuration.muteWarningsConfiguration.repeatStatus = .once
        XCTAssertNotEqual(viewModel.expiryWarningDuration, pumpManager.pumpConfiguration.expiryWarningDuration)
        XCTAssertEqual(viewModel.lowReservoirWarningThresholdInUnits, pumpManager.lowReservoirWarningThresholdInUnits)
        XCTAssertNotEqual(viewModel.insulinStartSoundsEnabled, pumpManager.insulinStartSoundsEnabled)
        XCTAssertNotEqual(viewModel.muteWarningsEnabled, pumpManager.muteWarningsEnabled)
        XCTAssertNotEqual(viewModel.muteWarningsStartTime, pumpManager.muteWarningsStartTime)
        XCTAssertNotEqual(viewModel.muteWarningsEndTime, pumpManager.muteWarningsEndTime)
        XCTAssertNotEqual(viewModel.muteWarningsDailyFrequency, pumpManager.muteWarningsDailyFrequency)

        pumpManager.pumpDidUpdateState(pumpManager.pump)
        waitOnMain()

        XCTAssertEqual(viewModel.expiryWarningDuration, pumpManager.expirationReminderTimeBeforeExpiration)
        XCTAssertEqual(viewModel.lowReservoirWarningThresholdInUnits, pumpManager.lowReservoirWarningThresholdInUnits)
        XCTAssertEqual(viewModel.insulinStartSoundsEnabled, pumpManager.insulinStartSoundsEnabled)
        XCTAssertEqual(viewModel.isInsulinDeliverySuspended, pumpManager.isSuspended)
        XCTAssertEqual(viewModel.muteWarningsEnabled, pumpManager.muteWarningsEnabled)
        XCTAssertEqual(viewModel.muteWarningsStartTime, pumpManager.muteWarningsStartTime)
        XCTAssertEqual(viewModel.muteWarningsEndTime, pumpManager.muteWarningsEndTime)
        XCTAssertEqual(viewModel.muteWarningsDailyFrequency, pumpManager.muteWarningsDailyFrequency)
    }
    
    func testComponentsNeedingReplacementToResolveUpdates() throws {
        XCTAssertFalse(viewModel.wasInsulinDeliverySuspensionCausedByEMWR)
        XCTAssertEqual(.none, viewModel.componentsNeedingReplacementToResolve)
        XCTAssertTrue(viewModel.componentsNeedingReplacementToResolve.isEmpty)
        
        var state = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        state.replacementWorkflowState.addComponentsNeedingReplacement(for: .occlusionDetected)
        viewModel.pumpManagerDidUpdateState(self.pumpManager, state)
        XCTAssertEqual([.infusionAssembly: .forced, .reservoir: .forced], viewModel.componentsNeedingReplacementToResolve)
        XCTAssertTrue(viewModel.wasInsulinDeliverySuspensionCausedByEMWR)
    }
    
    func testComponentsNeedingReplacementDoesNotIncludeWarnings() throws {
        var state = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        state.replacementWorkflowState.addComponentsNeedingReplacement(for: .endOfReservoirTime)
        viewModel.pumpManagerDidUpdateState(self.pumpManager, state)
        XCTAssertEqual([.reservoir: .soon], viewModel.componentsNeedingReplacementToResolve)
        XCTAssertFalse(viewModel.wasInsulinDeliverySuspensionCausedByEMWR)
    }

    func testIsComponentReplacementNeededWorkflowCanceledHasNoEffect() throws {
        XCTAssertFalse(viewModel.wasInsulinDeliverySuspensionCausedByEMWR)
        pumpManager.replacementWorkflowState.wasWorkflowCanceled = true
        XCTAssertFalse(viewModel.wasInsulinDeliverySuspensionCausedByEMWR)
    }

    func testSignalLossDescriptiveText() throws {
        XCTAssertNil(viewModel.descriptiveText)
        pumpManager.pumpStatusHighlight = SignalLossPumpStatusHighlight()
        viewModel.pumpManager(pumpManager, didUpdate: pumpManager.status, oldStatus: pumpManager.status)
        XCTAssertEqual(viewModel.descriptiveText, viewModel.signalLossDescriptiveText)
    }
}

extension SettingsViewModelTests {
    func updateDeviceInformation(serialNumber: String? = nil,
                                 firmwareRevision: String? = nil,
                                 hardwareRevision: String? = nil,
                                 batteryLevel: Int? = nil) {
        let deviceInformation = DeviceInformation(identifier: identifier,
                                                  serialNumber: serialNumber ?? self.serialNumber,
                                                  firmwareRevision: firmwareRevision,
                                                  hardwareRevision: hardwareRevision,
                                                  batteryLevel: batteryLevel)
        pumpManager.pump.state.deviceInformation = deviceInformation
        viewModel.pumpDidUpdateState()
    }
}
