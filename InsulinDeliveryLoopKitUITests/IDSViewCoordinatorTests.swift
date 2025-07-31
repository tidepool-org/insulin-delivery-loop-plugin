//
//  IDSViewCoordinatorTests.swift
//  InsulinDeliveryLoopKitUITests
//
//  Created by Nathaniel Hamming on 2020-04-30.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import XCTest
import SwiftUI
import LoopKit
import LoopKitUI
import InsulinDeliveryServiceKit
import BluetoothCommonKit
@testable import InsulinDeliveryLoopKit
@testable import InsulinDeliveryLoopKitUI

@MainActor
class IDSViewCoordinatorTests: XCTestCase {

    private let loopColorPalette = LoopUIColorPalette(guidanceColors: GuidanceColors(acceptable: .primary, warning: .yellow, critical: .red),
                                                      carbTintColor: .green,
                                                      glucoseTintColor: .purple,
                                                      insulinTintColor: .orange,
                                                      loopStatusColorPalette: StateColorPalette(unknown: .gray, normal: .blue, warning: .orange, error: .red),
                                                      chartColorPalette: ChartColorPalette(axisLine: .black, axisLabel: .black, grid: .gray, presetTint: .systemIndigo, glucoseTint: .purple, insulinTint: .orange, carbTint: .green))
    private var viewCoordinator: IDSViewCoordinator!
    private var didCreatePumpManager = false
    private var didOnboardPumpManager = false
    
    private var securityManagerTestingDelegate = SecurityManagerTestingDelegate()

    private func setUpViewCoordinator() {
        securityManagerTestingDelegate.sharedKeyData = Data(hexadecimalString: "000102030405060708090a0b0c0d0e0f")!
        let securityManager = SecurityManager()
        securityManager.delegate = securityManagerTestingDelegate
        let bluetoothManager = BluetoothManager(peripheralConfiguration: .insulinDeliveryServiceConfiguration, servicesToDiscover: [InsulinDeliveryCharacteristicUUID.service.cbUUID], restoreOptions: nil)
        bluetoothManager.peripheralManager = PeripheralManager()

        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
        let pump = InsulinDeliveryPump(bluetoothManager: bluetoothManager,
                                       bolusManager: BolusManager(),
                                       basalManager: BasalManager(),
                                       pumpHistoryEventManager: PumpHistoryEventManager(),
                                       securityManager: securityManager,
                                       acControlPoint: ACControlPointDataHandler(securityManager: securityManager, maxRequestSize: 19),
                                       acData: ACDataDataHandler(securityManager: securityManager, maxRequestSize: 19),
                                       state: pumpManagerState.pumpState)
        let pumpManager = InsulinDeliveryPumpManager(state: pumpManagerState, pump: pump)

        viewCoordinator = IDSViewCoordinator(pumpManager: pumpManager, colorPalette: loopColorPalette, allowDebugFeatures: false)
        viewCoordinator.basalSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1)])
        viewCoordinator.maxBolusUnits = 10.0
        viewCoordinator.workflowViewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                                              navigator: viewCoordinator,
                                                              workflowStepCompletionHandler: { })
        viewCoordinator.pumpManagerOnboardingDelegate = self
    }

    func testIDSScreenSetupNextReplacementWorkflow() throws {
        XCTAssertNil(IDSScreen.attachPump.setupNext(workflowType: .replacement))
        XCTAssertEqual(IDSScreen.connectToPump.setupNext(workflowType: .replacement), .primeReservoir)
        XCTAssertEqual(IDSScreen.primeReservoir.setupNext(workflowType: .replacement), .attachPump)
        XCTAssertEqual(IDSScreen.selectPump.setupNext(workflowType: .replacement), .connectToPump)
        XCTAssertNil(IDSScreen.settings.setupNext(workflowType: .replacement))
    }

    func testIDSScreenSetupNextOnboardingWorkflow() throws {
        XCTAssertEqual(IDSScreen.selectPump.setupNext(workflowType: .onboarding), .connectToPump)
        XCTAssertEqual(IDSScreen.connectToPump.setupNext(workflowType: .onboarding), .primeReservoir)
        XCTAssertEqual(IDSScreen.primeReservoir.setupNext(workflowType: .onboarding), .attachPump)
        XCTAssertNil(IDSScreen.attachPump.setupNext(workflowType: .onboarding))
    }

    func testIDSScreenMilestoneProgressScreen() throws {
        XCTAssertTrue(IDSScreen.attachPump.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertFalse(IDSScreen.connectToPump.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertTrue(IDSScreen.primeReservoir.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertFalse(IDSScreen.selectPump.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertFalse(IDSScreen.settings.isMilestoneProgressScreen(workflowType: .onboarding))
    }

    func testStartOnboardingScreen() throws {
        XCTAssertEqual(IDSScreen.startOnboardingScreen, IDSScreen.selectPump)
    }

    func testSettingScreen() throws {
        XCTAssertEqual(IDSScreen.settingsScreen, IDSScreen.settings)
    }
    
    func testStartOnboarding() throws {
        setUpViewCoordinator()
        XCTAssertFalse(didCreatePumpManager)
        viewCoordinator.viewWillAppear(false)
        XCTAssertTrue(didCreatePumpManager)
    }
    
    func testViewControllerForScreenSetupFlow() throws {
        setUpViewCoordinator()
        viewCoordinator.navigateTo(.selectPump)
        XCTAssertEqual(viewCoordinator.currentScreen, .selectPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.selectPump])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .connectToPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.selectPump, .connectToPump])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .primeReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.selectPump, .connectToPump, .primeReservoir])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .attachPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.selectPump, .connectToPump, .primeReservoir, .attachPump])        
    }
    
    func testPopToRoot() throws {
        setUpViewCoordinator()

        viewCoordinator.navigateTo(.selectPump)
        viewCoordinator.navigateTo(.primeReservoir)
        viewCoordinator.navigateTo(.attachPump)
        
        viewCoordinator.popToRoot()
        XCTAssertEqual(viewCoordinator.currentScreen, .selectPump)
    }
    
    func testNavigateToPrevious() throws {
        setUpViewCoordinator()

        viewCoordinator.navigateTo(.selectPump)
        viewCoordinator.navigateTo(.attachPump)
        
        viewCoordinator.navigateToPrevious()
        XCTAssertEqual(viewCoordinator.currentScreen, .selectPump)
    }

    func testReplaceCurrentScreen() throws {
        setUpViewCoordinator()
        viewCoordinator.navigateTo(.selectPump)
        XCTAssertEqual(viewCoordinator.currentScreen, .selectPump)
        viewCoordinator.replaceCurrentScreen(with: .connectToPump)
        XCTAssertEqual(viewCoordinator.currentScreen, .connectToPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.connectToPump])
    }
}

extension IDSViewCoordinatorTests: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        didCreatePumpManager = true
    }
    
    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        didOnboardPumpManager = true
    }

    func pumpManagerOnboarding(didPauseOnboarding pumpManager: PumpManagerUI) {
    }
}
