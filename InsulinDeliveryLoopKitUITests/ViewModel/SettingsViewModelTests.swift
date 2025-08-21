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
import InsulinDeliveryServiceKit
import BluetoothCommonKit
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

@MainActor
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
    private var securityManagerTestingDelegate = SecurityManagerTestingDelegate()

    private var mockKeychainManager: MockKeychainManager!

    override func setUp() {
        mockNavigator = MockNavigator()
        mockKeychainManager = MockKeychainManager()
        deviceInformation = DeviceInformation(identifier: identifier,
                                              serialNumber: serialNumber,
                                              firmwareRevision: firmwareRevision,
                                              hardwareRevision: hardwareRevision,
                                              batteryLevel: batteryLevel,
                                              reportedRemainingLifetime: InsulinDeliveryPumpManager.lifespan)
        let uuidToHandleMap: [CBUUID: UInt16] = [DeviceInfoCharacteristicUUID.firmwareRevisionString.cbUUID: 1,
                                                 DeviceInfoCharacteristicUUID.hardwareRevisionString.cbUUID: 2,
                                                 BatteryCharacteristicUUID.batteryLevel.cbUUID: 3,
                                                 InsulinDeliveryCharacteristicUUID.commandControlPoint.cbUUID: 4,
                                                 InsulinDeliveryCharacteristicUUID.statusReaderControlPoint.cbUUID: 5]
        pumpState = IDPumpState(deviceInformation: deviceInformation, uuidToHandleMap: uuidToHandleMap)
        securityManagerTestingDelegate.sharedKeyData = Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f")!
        let securityManager = SecurityManager()
        securityManager.delegate = securityManagerTestingDelegate
        
        let bluetoothManager = BluetoothManager(peripheralConfiguration: .insulinDeliveryServiceConfiguration, servicesToDiscover: [InsulinDeliveryCharacteristicUUID.service.cbUUID], restoreOptions: nil)
        bluetoothManager.peripheralManager = PeripheralManager()
        let acControlPoint = ACControlPointDataHandler(securityManager: securityManager, maxRequestSize: 19)
        let acData = ACDataDataHandler(securityManager: securityManager, maxRequestSize: 19)
        let bolusManager = BolusManager()
        let pumpHistoryEventManager = PumpHistoryEventManager()
        pump = InsulinDeliveryPump(bluetoothManager: bluetoothManager,
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

    func testAllowedExpiryWarningDurations() {
        var expectedExpiryWarningDurations: [TimeInterval] = []
        for days in 1...4 {
            expectedExpiryWarningDurations.append(.days(days))
        }
        XCTAssertEqual(viewModel.allowedExpiryWarningDurations, expectedExpiryWarningDurations)
    }

    func testAllowedLowReservoirWarningThresholds() {
        let expectedExpiryWarningDurations = Array(stride(from: 5, through: 40, by: 5))
        XCTAssertEqual(viewModel.allowedLowReservoirWarningThresholdsInUnits, expectedExpiryWarningDurations)
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
    
    func testIsInsulinDeliverySuspendedByUserWithPumpNeedingReplacement() throws {
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule, maxBolusUnits: 10.0, pumpState: pumpState)
        state.replacementWorkflowState.lastPumpReplacementDate = .distantPast
        state.replacementWorkflowState.doesPumpNeedsReplacement = true
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
    
    func testInsulinDeliveryDisabledWithPumpNeedingReplacement() throws {
        pumpManager.pump.state.deviceInformation?.pumpOperationalState = .ready
        XCTAssertFalse(viewModel.insulinDeliveryDisabled)
        var state = InsulinDeliveryPumpManagerState(basalRateSchedule: basalRateSchedule, maxBolusUnits: 10.0, pumpState: pumpState)
        state.replacementWorkflowState.lastPumpReplacementDate = .distantPast
        state.replacementWorkflowState.doesPumpNeedsReplacement = true
        state.suspendState = .suspended(Date.distantPast)
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

        var response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.setTherapyControlState.rawValue)
        response.append(IDCommandControlPointResponseCode.success.rawValue)
        response.append(pump.idCommand.e2eCounter)
        response = response.appendingCRC()

        pump.manageInsulinDeliveryCommandControlPointResponse(response)
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
        response.append(pump.idStatusReader.e2eCounter)
        response = response.appendingCRC()
        pump.manageInsulinDeliveryStatusReaderResponse(response)
        
        response = Data(IDCommandControlPointOpcode.responseCode.rawValue)
        response.append(IDCommandControlPointOpcode.setTherapyControlState.rawValue)
        response.append(IDCommandControlPointResponseCode.success.rawValue)
        response.append(pump.idCommand.e2eCounter)
        response = response.appendingCRC()

        pump.manageInsulinDeliveryCommandControlPointResponse(response)
        wait(for: [testExpectation], timeout: 30)

        XCTAssertTrue(viewModel.isInsulinDeliverySuspended)
        XCTAssertNotNil(viewModel.suspendedAtString)
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
                                 batteryLevel: Int? = nil,
                                 reportedRemainingLifetime: TimeInterval? = nil) {
        let deviceInformation = DeviceInformation(identifier: identifier,
                                                  serialNumber: serialNumber ?? self.serialNumber,
                                                  firmwareRevision: firmwareRevision,
                                                  hardwareRevision: hardwareRevision,
                                                  batteryLevel: batteryLevel,
                                                  reportedRemainingLifetime: reportedRemainingLifetime ?? InsulinDeliveryPumpManager.lifespan)
        pumpManager.pump.state.deviceInformation = deviceInformation
        viewModel.pumpDidUpdateState()
    }
}
