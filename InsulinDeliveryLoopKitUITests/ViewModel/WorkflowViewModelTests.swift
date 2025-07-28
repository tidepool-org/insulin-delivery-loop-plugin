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
    
    override func setUp() {
        mockNavigator = MockNavigator()
        mockKeychainManager = MockKeychainManager()
        let bluetoothManager = BluetoothManager(restoreOptions: nil)
        bluetoothManager.peripheralManager = PeripheralManager()
        let bolusManager = BolusManager()
        let pumpHistoryEventManager = PumpHistoryEventManager()
        let securityManager = SecurityManager(securePersistentPumpAuthentication: { self.mockKeychainManager }, sharedKeyData: Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f")!)
        let acControlPoint = ACControlPoint(securityManager: securityManager, maxRequestSize: 19)
        let acData = ACData(securityManager: securityManager, maxRequestSize: 19)
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
    
    func testOtherDeviceDiscovered() {
        let device = Device(id: UUID(),
                            name: "Other device",
                            serialNumber: "1234567890",
                            imageName: "unknown-device",
                            remainingLifetime: .days(100))
        pump.delegate?.pump(pump,
                            didDiscoverPumpWithName: device.name,
                            identifier: device.id,
                            serialNumber: device.serialNumber)
        waitOnMain()
        
        XCTAssertTrue(viewModel.devices.isEmpty)
    }
    
    func testUnnamedDeviceDiscovered() {
        let device = Device(id: UUID(),
                            name: "Unknown Device",
                            serialNumber: "1234567890",
                            imageName: "unknown-device",
                            remainingLifetime: .days(100))
        pump.delegate?.pump(pump,
                            didDiscoverPumpWithName: device.name,
                            identifier: device.id,
                            serialNumber: device.serialNumber)
        waitOnMain()
        
        XCTAssertTrue(viewModel.devices.isEmpty)
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

        mockNavigator.screenStack = [.pumpBarcodeScanner]
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

        XCTAssertFalse(viewModel.pumpBaseHasBeenAuthenticated)
        isPumpConnected = true
        pumpManager.pumpConnectionStatusChanged(pump)
        waitOnMain()
        XCTAssertFalse(viewModel.pumpBaseHasBeenAuthenticated)
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

        XCTAssertFalse(viewModel.pumpBaseHasBeenAuthenticated)
        isPumpAuthenticated = true
        pumpManager.pumpDidCompleteAuthentication(pump)
        waitOnMain()
        XCTAssertTrue(viewModel.pumpBaseHasBeenAuthenticated)
        XCTAssertTrue(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.pumpSetupState, .authenticatedAwaitingDisconnect)
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

        XCTAssertFalse(viewModel.pumpBaseHasBeenAuthenticated)
        pumpManager.pumpDidCompleteAuthentication(pump, error: .authenticationFailed)
        waitOnMain()
        XCTAssertFalse(viewModel.pumpBaseHasBeenAuthenticated)
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

        XCTAssertFalse(viewModel.pumpBaseHasBeenAuthenticated)
        pumpManager.pumpDidCompleteAuthentication(pump, error: .pumpAlreadyPaired)
        waitOnMain()
        XCTAssertFalse(viewModel.pumpBaseHasBeenAuthenticated)
        XCTAssertFalse(viewModel.devices.isEmpty)
        XCTAssertEqual(viewModel.pumpSetupState, .pumpAlreadyPaired)
    }

    func testPartsDiscardedInfusionAssembly() {
        mockNavigator.screenStack = [.discardInfusionAssembly]
        viewModel.selectedComponents = .infusionAssembly
        viewModel.componentsDiscarded()
        XCTAssertEqual(viewModel.pumpSetupState, .reservoirPrimed)
    }

    func testPartsDiscardedReservoir() {
        mockNavigator.screenStack = [.discardReservoir]
        viewModel.selectedComponents = .reservoir
        viewModel.componentsDiscarded()
        XCTAssertEqual(viewModel.pumpSetupState, .connecting)
    }

    func testPartsDiscardedInfusionAssemblyAndReservoir() {
        mockNavigator.screenStack = [.discardInfusionAssemblyAndReservoir]
        viewModel.selectedComponents = .infusionAssemblyAndReservoir
        viewModel.componentsDiscarded()
        XCTAssertEqual(viewModel.pumpSetupState, .connecting)
    }

    func testPartsDiscardedReservoirAndPumpBase() {
        mockNavigator.screenStack = [.discardReservoirAndPumpBase]
        viewModel.selectedComponents = .reservoirAndPumpBase
        viewModel.componentsDiscarded()
        XCTAssertEqual(viewModel.pumpSetupState, .advertising)
    }

    func testPartsDiscardedAll() {
        mockNavigator.screenStack = [.discardAllComponents]
        viewModel.selectedComponents = .all
        viewModel.componentsDiscarded()
        XCTAssertEqual(viewModel.pumpSetupState, .advertising)
    }
    
    func testUpdateSelectedComponentsInfusionSet() {
        viewModel.updateSelectedComponents(.infusionAssembly)
        XCTAssertEqual(viewModel.selectedComponents, .infusionAssembly)
        viewModel.navigateToDiscardComponents()
        XCTAssertEqual(mockNavigator.currentScreen, .discardInfusionAssembly)
        XCTAssertEqual(viewModel.componentsNeedingReplacement, [.infusionAssembly: .forced])
        XCTAssertEqual(pumpManager.componentsNeedingReplacement, viewModel.componentsNeedingReplacement)
    }
    
    func testUpdateSelectedComponentsReservoir() {
        viewModel.updateSelectedComponents(.reservoir)
        XCTAssertEqual(viewModel.selectedComponents, .reservoir)
        viewModel.navigateToDiscardComponents()
        XCTAssertEqual(mockNavigator.currentScreen, .discardReservoir)
        XCTAssertEqual(viewModel.componentsNeedingReplacement, [.reservoir: .forced])
        XCTAssertEqual(pumpManager.componentsNeedingReplacement, viewModel.componentsNeedingReplacement)
    }
    
    func testUpdateSelectedComponentsAll() {
        viewModel.updateSelectedComponents(.all)
        XCTAssertEqual(viewModel.selectedComponents, .all)
        viewModel.navigateToDiscardComponents()
        XCTAssertEqual(mockNavigator.currentScreen, .discardAllComponents)
        XCTAssertEqual(viewModel.componentsNeedingReplacement, [.infusionAssembly: .forced, .reservoir: .forced, .pumpBase: .forced])
        XCTAssertEqual(pumpManager.componentsNeedingReplacement, viewModel.componentsNeedingReplacement)
    }
    
    func testValidReservoirLevel() {
        XCTAssertFalse(viewModel.validReservoirLevel(50))
        XCTAssertTrue(viewModel.validReservoirLevel(80))
        XCTAssertTrue(viewModel.validReservoirLevel(150))
        XCTAssertTrue(viewModel.validReservoirLevel(200))
        XCTAssertFalse(viewModel.validReservoirLevel(210))
    }

    func testPumpKeyEnterManuallySelected() {
        mockNavigator.screenStack = [.pumpBarcodeScanner]
        viewModel.pumpKeyEnterManuallySelected()
        XCTAssertEqual(mockNavigator.currentScreen, .selectPump)

        viewModel.switchToTakePhotoOfPumpBarcodeSelected()
        XCTAssertEqual(mockNavigator.currentScreen, .pumpBarcodeScanner)
    }

    func testPumpKeyEntry() {
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

        mockNavigator.screenStack = [.pumpKeyEntryManual]
        viewModel.selectedDeviceSerialNumber = device.serialNumber
        XCTAssertTrue(viewModel.deviceSelected)
        viewModel.pumpKeyEntry("1234")
        XCTAssertEqual(viewModel.pumpSetupState, PumpSetupState.connecting)
    }

    func testHasDeviceMatchingSerialNumber() {
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

        let matchingSerialNumber = "12345678"
        let notMatchingSerialNumber = "34567890"
        XCTAssertEqual(viewModel.deviceMatchingSerialNumber(matchingSerialNumber), device)
        XCTAssertNil(viewModel.deviceMatchingSerialNumber(notMatchingSerialNumber))
    }

    func testReservoirFilled() {
        // no pump connected
        mockNavigator.screenStack = [.fillReservoir]
        viewModel.reservoirFilled()
        waitOnMain()
        XCTAssertEqual(mockNavigator.currentScreen, .assemblePumpGuide)

        // pump connected
        mockNavigator.screenStack = [.fillReservoir]
        isPumpConnected = true
        pump.setupDeviceInformation()
        viewModel.reservoirFilled()
        waitOnMain()
        XCTAssertEqual(mockNavigator.currentScreen, .assemblePumpGuide)
    }

    func testPumpDidUpdateStatePriming() {
        mockNavigator.screenStack = [.primeReservoir]
        pump.setupDeviceInformation(therapyControlState: .stop, pumpOperationalState: .waiting)

        // priming reservoir started (from .configured)
        viewModel.pumpSetupState = .configured
        var testExpectation = XCTestExpectation(description: #function)
        viewModel.startPrimingCompletion = { testExpectation.fulfill() }
        pump.setOperationalStateTo(.priming)
        wait(for: [testExpectation], timeout: 2)
        XCTAssertEqual(viewModel.pumpSetupState, .primingReservoir)

        // priming reservoir stopped
        pump.setOperationalStateTo(.ready)
        waitOnMain()
        XCTAssertEqual(viewModel.pumpSetupState, .primingReservoirStopped)

        // priming reservoir started (from .primingReservoirStopped)
        testExpectation = XCTestExpectation(description: #function)
        viewModel.startPrimingCompletion = { testExpectation.fulfill() }
        pump.setOperationalStateTo(.priming)
        wait(for: [testExpectation], timeout: 2)
        XCTAssertEqual(viewModel.pumpSetupState, .primingReservoir)

        // priming resevoir completed
        pump.setOperationalStateTo(.waiting)
        viewModel.reservoirPrimingHasCompleted()
        waitOnMain()
        XCTAssertEqual(viewModel.pumpSetupState, .reservoirPrimed)

        // priming cannula started
        pump.setOperationalStateTo(.priming)
        waitOnMain()
        XCTAssertEqual(viewModel.pumpSetupState, .primingCannula)

        // cannula primed
        pump.setOperationalStateTo(.ready)
        waitOnMain()
        XCTAssertEqual(viewModel.pumpSetupState, .cannulaPrimed)
    }

    func testSelectPumpAgain() {
        mockNavigator.screenStack = [.fillReservoir, .assemblePumpGuide, .selectPump, .pumpKeyEntryManual, .connectToPump]
        viewModel.selectPumpAgain()
        waitOnMain()
        XCTAssertEqual(mockNavigator.currentScreen, .selectPump)
    }

    func testReplaceInfusionAssemblyAgain() {
        mockNavigator.screenStack = [.prepareInsertionDevice, .applyInfusionAssembly, .checkCannula]
        viewModel.replaceInfusionAssemblyAgain()
        waitOnMain()
        XCTAssertEqual(mockNavigator.currentScreen, .streamlinedInsertionDevice)
    }

    func testReplaceReservoirAgain() {
        mockNavigator.screenStack = [.fillReservoir, .fillReservoirSetupStart, .assemblePumpGuide, .connectToPump, .primeReservoir]
        mockNavigator.workflowType = .replacement
        viewModel.replaceReservoirAgain()
        waitOnMain()
        XCTAssertEqual(mockNavigator.currentScreen, .fillReservoir)

        mockNavigator.screenStack = [.fillReservoir, .fillReservoirSetupStart, .assemblePumpGuide, .connectToPump, .primeReservoir]
        mockNavigator.workflowType = .onboarding
        viewModel.replaceReservoirAgain()
        waitOnMain()
        XCTAssertEqual(mockNavigator.currentScreen, .fillReservoirSetupStart)
    }

    func testReservoirPrimingHasCompleted() {
        mockNavigator.screenStack = [.primeReservoir]
        viewModel.pumpSetupState = .primingReservoirIssue
        viewModel.reservoirPrimingHasCompleted()
        XCTAssertEqual(viewModel.pumpSetupState, .primingReservoirIssue)

        mockNavigator.screenStack = [.primeReservoir]
        viewModel.pumpSetupState = .primingReservoir
        viewModel.reservoirPrimingHasCompleted()
        XCTAssertEqual(viewModel.pumpSetupState, .reservoirPrimed)

        mockNavigator.screenStack = [.primeReservoir]
        viewModel.pumpSetupState = .primingReservoirStopped
        viewModel.reservoirPrimingHasCompleted()
        XCTAssertEqual(viewModel.pumpSetupState, .reservoirPrimed)
    }
    
    func testReplaceComponentsAgain() {
        viewModel.selectedComponents = [.pumpBase, .reservoir]
        mockNavigator.screenStack = [.discardReservoirAndPumpBase, .fillReservoir, .assemblePumpGuide, .connectToPump, .primeReservoir]
        viewModel.replaceComponentsAgain()
        waitOnMain()
        XCTAssertEqual(viewModel.pumpSetupState, .advertising)
        XCTAssertEqual(mockNavigator.currentScreen, .discardReservoirAndPumpBase)
    }

    func testRestartInfusionAssemblySetup() {
        viewModel.selectedComponents = .all
        mockNavigator.workflowType = .onboarding
        mockNavigator.screenStack = [.setupSystemComponents1, .setupSystemComponents2InfusionAssembly, .infusionAssemblySetupStart, .infusionAssemblySetupVideo, .infusionAssemblySteps1to3, .infusionAssemblyStep4, .infusionAssemblyStep5, .infusionAssemblyStep6, .infusionAssemblyStep7, .infusionAssemblyStep8, .infusionAssemblyStep9, .infusionAssemblyStep10, .infusionAssemblyStep11, .infusionAssemblyStep12, .infusionAssemblyStep13]
        
        viewModel.restartInfusionAssemblySetup()
        waitOnMain()
        XCTAssertEqual(mockNavigator.currentScreen, .infusionAssemblySteps1to3)
    }

    func testRepeatPumpSetupOnboarding() {
        viewModel.selectedComponents = .all
        mockNavigator.workflowType = .onboarding
        mockNavigator.screenStack = [.setupSystemComponents1, .setupSystemComponents2InfusionAssembly, .infusionAssemblySetupStart, .infusionAssemblySetupVideo, .infusionAssemblySteps1to3, .infusionAssemblyStep4, .infusionAssemblyStep5, .infusionAssemblyStep6, .infusionAssemblyStep7, .infusionAssemblyStep8, .infusionAssemblyStep9, .infusionAssemblyStep10, .infusionAssemblyStep11, .infusionAssemblyStep12, .infusionAssemblyStep13, .fillReservoirSetupStart, .fillReservoirSetupVideo, .fillReservoirSetupStep1, .fillReservoirSetupStep2, .fillReservoirSetupStep3, .fillReservoirSetupStep4, .fillReservoirSetupStep5, .fillReservoirSetupStep6, .fillReservoirSetupStep7, .fillReservoirSetupStep8, .setReservoirFillValue, .pumpBarcodeScanner, .connectToPump]

        viewModel.repeatPumpSetup()
        XCTAssertEqual(viewModel.pumpSetupState, .advertising)
        XCTAssertEqual(mockNavigator.currentScreen, .fillReservoirSetupStart)
        XCTAssertFalse(viewModel.isPumpConnected)
        XCTAssertTrue(viewModel.devices.isEmpty)
    }

    func testScreenToDiscardComponents() {
        viewModel.selectedComponents = [.infusionAssembly]
        var discardComponentScreen = viewModel.screenToDiscardComponents
        XCTAssertEqual(discardComponentScreen, .discardInfusionAssembly)

        viewModel.selectedComponents = [.reservoir]
        discardComponentScreen = viewModel.screenToDiscardComponents
        XCTAssertEqual(discardComponentScreen, .discardReservoir)

        viewModel.selectedComponents = [.infusionAssembly, .reservoir]
        discardComponentScreen = viewModel.screenToDiscardComponents
        XCTAssertEqual(discardComponentScreen, .discardInfusionAssemblyAndReservoir)

        viewModel.selectedComponents = [.reservoir, .pumpBase]
        discardComponentScreen = viewModel.screenToDiscardComponents
        XCTAssertEqual(discardComponentScreen, .discardReservoirAndPumpBase)

        viewModel.selectedComponents = [.infusionAssembly, .reservoir, .pumpBase]
        discardComponentScreen = viewModel.screenToDiscardComponents
        XCTAssertEqual(discardComponentScreen, .discardAllComponents)
    }

    func testSetReservoirLevelAndThenConfigurePump() {
        let testExpectation = expectation(description: #function)
        isPumpConnected = true

        viewModel.setReservoirLevel() { error in
            XCTAssertNil(error)
            testExpectation.fulfill()
        }

        pump.respondToSetReservoirLevel()
        pump.respondToResetReservoirInsulinOperationTime()
        pump.respondToWriteBasalRate()
        pump.respondToActivateProfileTemplate()
        waitOnMain()
        pump.respondToSetTime()
        waitOnMain()
        pump.respondToConfigurePump()
        
        wait(for: [testExpectation], timeout: 30)
        XCTAssertEqual(viewModel.pumpSetupState, .configured)
    }

    func testSetReservoirLevelFailed() {
        let testExpectation = expectation(description: #function)
        isPumpConnected = true

        viewModel.setReservoirLevel() { error in
            XCTAssertEqual(error as! DeviceCommError, .procedureNotCompleted)
            testExpectation.fulfill()
        }

        pump.respondToSetReservoirLevel(responseCode: .procedureNotCompleted)
        wait(for: [testExpectation], timeout: 30)
        XCTAssertEqual(viewModel.pumpSetupState, .authenticated)
    }

    func testSetReservoirLevelFailedCanStopInsulinDelivery() {
        let testExpectation = expectation(description: #function)
        isPumpConnected = true
        pump.setupDeviceInformation()
        viewModel.setReservoirLevel() { error in
            XCTAssertNil(error)
            if error == nil {
                testExpectation.fulfill()
            }
        }

        pump.respondToSetReservoirLevel(responseCode: .procedureNotApplicable)
        waitOnMain()
        
        pump.respondToSetTherapyControlState(therapyControlState: .stop)
        waitOnMain()

        pump.respondToSetReservoirLevel()
        pump.respondToResetReservoirInsulinOperationTime()
        pump.respondToWriteBasalRate()
        pump.respondToActivateProfileTemplate()
        waitOnMain()

        pump.respondToSetTime()
        waitOnMain()
        
        wait(for: [testExpectation], timeout: 30)
        XCTAssertEqual(viewModel.pumpSetupState, .configured)
    }

    func testSetReservoirLevelFailedCannotStopInsulinDelivery() {
        let testExpectation = expectation(description: #function)
        isPumpConnected = true
        pump.setTherapyControlStateTo(.run)

        viewModel.setReservoirLevel() { error in
            XCTAssertEqual(error as! DeviceCommError, .procedureNotApplicable)
            testExpectation.fulfill()
        }

        pump.respondToSetReservoirLevel(responseCode: .procedureNotApplicable)
        waitOnMain()

        pump.respondToSetTherapyControlState(responseCode: .procedureNotCompleted)

        wait(for: [testExpectation], timeout: 30)
        XCTAssertEqual(viewModel.pumpSetupState, .authenticated)
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

        viewModel.pumpSetupState = .cannulaPrimed
        XCTAssertFalse(viewModel.isWorkflowCompleted)

        viewModel.selectedComponents = .infusionAssemblyAndReservoir
        XCTAssertTrue(viewModel.isWorkflowCompleted)

        viewModel.pumpSetupState = .reservoirPrimed
        XCTAssertFalse(viewModel.isWorkflowCompleted)

        viewModel.selectedComponents = .reservoirAndPumpBase
        XCTAssertTrue(viewModel.isWorkflowCompleted)
    }
    
    func testReceivedPumpNotConfigured() throws {
        var trash = [AnyCancellable]()
        var receivedPumpNotConfigured = false
        XCTAssertFalse(viewModel.receivedPumpNotConfigured)
        viewModel.$receivedPumpNotConfigured.sink {
            receivedPumpNotConfigured = $0
        }
        .store(in: &trash)
        viewModel.pumpNotConfigured()
        XCTAssertTrue(receivedPumpNotConfigured)
        XCTAssertTrue(viewModel.receivedPumpNotConfigured)
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
    
    func testRestartReservoirFill() throws {
        mockNavigator.screenStack = [.discardReservoirAndPumpBase, .fillReservoir, .assemblePumpGuide, .fillReservoirSetupStart, .primeReservoir]
        mockNavigator.workflowType = .onboarding
        viewModel.restartReservoirFill()
        XCTAssertEqual(mockNavigator.currentScreen, .fillReservoirSetupStart)

        mockNavigator.workflowType = .replacement
        viewModel.restartReservoirFill()
        XCTAssertEqual(mockNavigator.currentScreen, .fillReservoir)
    }
    
    func testDoesComponentNeedReplacement() {
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.infusionAssembly))
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.reservoir))
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.pumpBase))
        
        viewModel.componentsNeedingReplacement = [.pumpBase: .subsequent]
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.infusionAssembly))
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.reservoir))
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.pumpBase))
    
        viewModel.componentsNeedingReplacement = [.reservoir: .forced, .infusionAssembly: .forced, .pumpBase: .forced]
        XCTAssertTrue(viewModel.doesComponentNeedReplacement(.infusionAssembly))
        XCTAssertTrue(viewModel.doesComponentNeedReplacement(.reservoir))
        XCTAssertTrue(viewModel.doesComponentNeedReplacement(.pumpBase))

        viewModel.componentsNeedingReplacement = [.reservoir: .soon]
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.infusionAssembly))
        XCTAssertTrue(viewModel.doesComponentNeedReplacement(.reservoir))
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.pumpBase))

        viewModel.componentsNeedingReplacement = [.infusionAssembly: .notRequired, .reservoir: .notRequired, .pumpBase: .notRequired]
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.infusionAssembly))
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.reservoir))
        XCTAssertFalse(viewModel.doesComponentNeedReplacement(.pumpBase))
    }
    
    func testComponentsNeedingReplacementToResolveUpdates() throws {
        XCTAssertEqual(.none, viewModel.componentsNeedingReplacement)
        XCTAssertTrue(viewModel.componentsNeedingReplacement.isEmpty)
        
        var state = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        state.replacementWorkflowState.addComponentsNeedingReplacement(for: .occlusionDetected)
        viewModel.pumpManagerDidUpdateState(self.pumpManager, state)
        XCTAssertEqual([.infusionAssembly: .forced, .reservoir: .forced], viewModel.componentsNeedingReplacement)
    }
    
    func testHasWatchedOnboardingVideo() throws {
        let videoName = "snoopy"
        XCTAssertFalse(viewModel.hasWatchedOnboardingVideo(named: videoName))
        viewModel.setHasWatchedOnboardingVideo(named: videoName, value: true)
        XCTAssertTrue(viewModel.hasWatchedOnboardingVideo(named: videoName))
        viewModel.setHasWatchedOnboardingVideo(named: videoName, value: false)
        XCTAssertFalse(viewModel.hasWatchedOnboardingVideo(named: videoName))
        viewModel.setHasWatchedOnboardingVideo(named: videoName, value: true)
        viewModel.setHasWatchedOnboardingVideo(named: videoName, value: true)
        XCTAssertTrue(viewModel.hasWatchedOnboardingVideo(named: videoName))
        viewModel.setHasWatchedOnboardingVideo(named: videoName, value: false)
        XCTAssertFalse(viewModel.hasWatchedOnboardingVideo(named: videoName))
    }

    func testShouldUnpairPumpBase() throws {
        pump.setupDeviceInformation()
        viewModel.selectedComponents = .all
        pump.deviceInformation?.updateExpirationDate(remainingLifetime: .hours(3))
        isPumpAuthenticated = true
        XCTAssertTrue(viewModel.shouldUnpairPumpBase)

        // false when less than 1 hour
        pump.deviceInformation?.updateExpirationDate(remainingLifetime: .minutes(30))
        XCTAssertFalse(viewModel.shouldUnpairPumpBase)

        // false when pump base is not authenticated
        pump.deviceInformation?.updateExpirationDate(remainingLifetime: .hours(3))
        isPumpAuthenticated = false
        XCTAssertFalse(viewModel.shouldUnpairPumpBase)

        // false when selected components does not include pump base
        isPumpAuthenticated = true
        viewModel.selectedComponents = .infusionAssemblyAndReservoir
        XCTAssertFalse(viewModel.shouldUnpairPumpBase)
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
