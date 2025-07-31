//
//  WorkflowViewModelTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Nathaniel Hamming on 2020-03-13.
//  Copyright © 2020 Tidepool Project. All rights reserved.
//

import XCTest
import Combine
import LoopKit
import InsulinDeliveryServiceKit
import BluetoothCommonKit
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

class WorkflowViewModelTests: XCTestCase {

    private var pump: TestInsulinDeliveryPump!
    private var pumpManager: InsulinDeliveryPumpManager!
    private var isPumpConnected: Bool = false
    private var isPumpAuthenticated: Bool = false
    private var viewModel: WorkflowViewModel!
    private var mockNavigator: MockNavigator!
    private var mockKeychainManager: MockKeychainManager!
    private var securityManagerTestingDelegate = SecurityManagerTestingDelegate()
    
    override func setUp() {
        mockNavigator = MockNavigator()
        mockKeychainManager = MockKeychainManager()
        let bluetoothManager = BluetoothManager(peripheralConfiguration: .insulinDeliveryServiceConfiguration, servicesToDiscover: [InsulinDeliveryCharacteristicUUID.service.cbUUID], restoreOptions: nil)
        bluetoothManager.peripheralManager = PeripheralManager()
        let bolusManager = BolusManager()
        let pumpHistoryEventManager = PumpHistoryEventManager()
        securityManagerTestingDelegate.sharedKeyData = Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f")!
        let securityManager = SecurityManager()
        securityManager.delegate = securityManagerTestingDelegate
        let acControlPoint = ACControlPointDataHandler(securityManager: securityManager, maxRequestSize: 19)
        let acData = ACDataDataHandler(securityManager: securityManager, maxRequestSize: 19)
        pump = TestInsulinDeliveryPump(bluetoothManager: bluetoothManager,
                                       bolusManager: bolusManager,
                                       basalManager: BasalManager(),
                                       pumpHistoryEventManager: pumpHistoryEventManager,
                                       securityManager: securityManager,
                                       acControlPoint: acControlPoint,
                                       acData: acData,
                                       state: IDPumpState(),
                                       isConnectedHandler: { self.isPumpConnected },
                                       isAuthenticatedHandler: { self.isPumpAuthenticated })
        pump.setupUUIDToHandleMap()

        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState, pump: pump)
        mockNavigator.screenStack = []
        viewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                      navigator: mockNavigator,
                                      workflowStepCompletionHandler: {
            guard let nextScreen = self.mockNavigator.currentScreen.setupNext(workflowType: .replacement) else { return }
            self.mockNavigator.currentScreen = nextScreen
        })
    }

    func testInitialization() {
        XCTAssertFalse(viewModel.hasDetectedDevices)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertNil(viewModel.selectedDeviceSerialNumber)
        XCTAssertFalse(viewModel.deviceSelected)
        XCTAssertEqual(viewModel.pumpSetupState, .advertising)
        XCTAssertEqual(viewModel.therapyState, .undetermined)
    }
        
    func testPumpDiscovered() {
        // connected device
        XCTAssertFalse(viewModel.hasDetectedDevices)
        isPumpConnected = true
        pump.setupDeviceInformation()
        waitOnMain()

        XCTAssertTrue(viewModel.hasDetectedDevices)
        isPumpConnected = false
        pump.state.deviceInformation = nil
        waitOnMain()

        // discovered device
        let device = Device(id: UUID(),
                            name: "Pump XYZ",
                            serialNumber: "12345678",
                            imageName: "pump-simulator",
                            remainingLifetime: nil)
        pump.delegate?.pump(pump,
                            didDiscoverPumpWithName: device.name,
                            identifier: device.id,
                            serialNumber: device.serialNumber)
        waitOnMain()
        
        XCTAssertTrue(viewModel.hasDetectedDevices)
        XCTAssertNil(viewModel.selectedDeviceSerialNumber)
        XCTAssertFalse(viewModel.deviceSelected)
        XCTAssertEqual(viewModel.pumpSetupState, PumpSetupState.advertising)
        XCTAssertFalse(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.devices.count, 1)
        if !viewModel.devices.isEmpty {
            XCTAssertEqual(viewModel.devices[0].name, device.name)
            XCTAssertEqual(viewModel.devices[0].id, device.id)
            XCTAssertEqual(viewModel.devices[0].imageName, device.imageName)
            XCTAssertEqual(viewModel.devices[0].serialNumber, device.serialNumber)
        }
    }
    
    func testConnectToSelectedDevice() {
        let device = Device(id: UUID(),
                            name: "Pump XYZ",
                            serialNumber: "12345678",
                            imageName: "pump-simulator",
                            remainingLifetime: .days(100))
        pump.delegate?.pump(pump,
                            didDiscoverPumpWithName: device.name,
                            identifier: device.id,
                            serialNumber: device.serialNumber)
        waitOnMain()

        mockNavigator.screenStack = [.primeReservoir]
        viewModel.pumpKeyEnterManuallySelected()
        XCTAssertEqual(mockNavigator.currentScreen, .selectPump)
        viewModel.selectedDeviceSerialNumber = device.serialNumber
        XCTAssertTrue(viewModel.deviceSelected)
        viewModel.enterPumpKeyForSelectedDevice()
        viewModel.pumpKeyEntry("1234")
        XCTAssertEqual(viewModel.pumpSetupState, PumpSetupState.connecting)
    }
    
    func testConnectToPumpWithSerialNumber() {
        let device = Device(id: UUID(),
                            name: "Pump XYZ",
                            serialNumber: "12345678",
                            imageName: "pump-simulator",
                            remainingLifetime: .days(100))
        pump.delegate?.pump(pump,
                            didDiscoverPumpWithName: device.name,
                            identifier: device.id,
                            serialNumber: device.serialNumber)
        waitOnMain()
                
        let serialNumber = "12345678"
        viewModel.connectToPump(withSerialNumber: serialNumber)
        XCTAssertEqual(viewModel.pumpSetupState, PumpSetupState.connecting)
    }

    func testPumpConnectionStateDidChange() {
        mockNavigator.screenStack = [.connectToPump]
        viewModel.pumpSetupState = .connecting
        let serialNumber = "12345678"
        let device = Device(id: UUID(),
                            name: "Pump XYZ",
                            serialNumber: serialNumber,
                            imageName: "pump-simulator",
                            remainingLifetime: .days(100))
        viewModel.deviceList = [serialNumber: device]

        XCTAssertFalse(viewModel.pumpHasBeenAuthenticated)
        isPumpConnected = true
        pumpManager.pumpConnectionStatusChanged(pump)
        waitOnMain()
        XCTAssertFalse(viewModel.pumpHasBeenAuthenticated)
        XCTAssertFalse(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.pumpSetupState, .authenticating)
    }

    func testPumpDidCompleteAuthentication() {
        mockNavigator.screenStack = [.connectToPump]
        viewModel.pumpSetupState = .authenticating
        let serialNumber = "12345678"
        let device = Device(id: UUID(),
                            name: "Pump XYZ",
                            serialNumber: serialNumber,
                            imageName: "pump-simulator",
                            remainingLifetime: .days(100))
        viewModel.deviceList = [serialNumber: device]

        XCTAssertFalse(viewModel.pumpHasBeenAuthenticated)
        isPumpAuthenticated = true
        pumpManager.pumpDidCompleteAuthentication(pump)
        waitOnMain()
        XCTAssertTrue(viewModel.pumpHasBeenAuthenticated)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.pumpSetupState, .authenticated)
    }

    func testPumpAuthenticationFailed() {
        mockNavigator.screenStack = [.connectToPump]
        viewModel.pumpSetupState = .authenticating
        let serialNumber = "12345678"
        let device = Device(id: UUID(),
                            name: "Pump XYZ",
                            serialNumber: serialNumber,
                            imageName: "pump-simulator",
                            remainingLifetime: .days(100))
        viewModel.deviceList = [serialNumber: device]

        XCTAssertFalse(viewModel.pumpHasBeenAuthenticated)
        pumpManager.pumpDidCompleteAuthentication(pump, error: .authenticationFailed)
        waitOnMain()
        XCTAssertFalse(viewModel.pumpHasBeenAuthenticated)
        XCTAssertFalse(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.pumpSetupState, .authenticationFailed)
    }

    func testPumpAlreadyPaired() {
        mockNavigator.screenStack = [.connectToPump]
        viewModel.pumpSetupState = .authenticating
        let serialNumber = "12345678"
        let device = Device(id: UUID(),
                            name: "Pump XYZ",
                            serialNumber: serialNumber,
                            imageName: "pump-simulator",
                            remainingLifetime: .days(100))
        viewModel.deviceList = [serialNumber: device]

        XCTAssertFalse(viewModel.pumpHasBeenAuthenticated)
        pumpManager.pumpDidCompleteAuthentication(pump, error: .deviceAlreadyPaired)
        waitOnMain()
        XCTAssertFalse(viewModel.pumpHasBeenAuthenticated)
        XCTAssertFalse(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.pumpSetupState, .pumpAlreadyPaired)
    }

    func testIsWorkflowCompleted() {
        mockNavigator.screenStack = [.attachPump]
        pump.setupDeviceInformation()
        pump.deviceInformation?.therapyControlState = .stop
        pump.deviceInformation?.pumpOperationalState = .ready
        XCTAssertFalse(viewModel.isWorkflowCompleted)

        viewModel.pumpSetupState = .startingTherapy
        XCTAssertFalse(viewModel.isWorkflowCompleted)

        pump.deviceInformation?.therapyControlState = .run
        XCTAssertTrue(viewModel.isWorkflowCompleted)

        viewModel.pumpSetupState = .primingPump
        XCTAssertFalse(viewModel.isWorkflowCompleted)
    }

    func testReceivedReservoirIssue() throws {
        var trash = [AnyCancellable]()
        var receivedReservoirIssue = false
        XCTAssertFalse(viewModel.receivedReservoirIssue)
        viewModel.$receivedReservoirIssue.sink {
            receivedReservoirIssue = $0
        }
        .store(in: &trash)
        viewModel.pumpEncounteredReservoirIssue()
        XCTAssertTrue(receivedReservoirIssue)
        XCTAssertTrue(viewModel.receivedReservoirIssue)
    }
}

extension XCTestCase {
    func waitOnMain() {
        let exp = expectation(description: "waitOnMain")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }
}
