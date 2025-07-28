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

    private func setUpViewCoordinator() {
        let pump = InsulinDeliveryPump(bluetoothManager: BluetoothManager(restoreOptions: nil),
                                       bolusManager: BolusManager(),
                                       basalManager: BasalManager(),
                                       pumpHistoryEventManager: PumpHistoryEventManager(),
                                       securityManager: SecurityManager(),
                                       acControlPoint: ACControlPoint(securityManager: SecurityManager(), maxRequestSize: 19),
                                       acData: ACData(securityManager: SecurityManager(), maxRequestSize: 19),
                                       state: IDPumpState())

        let pumpManagerState = InsulinDeliveryPumpManagerState.forPreviewsAndTests
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
        XCTAssertEqual(IDSScreen.assemblePumpGuide.setupNext(workflowType: .replacement), .setReservoirFillValue)
        XCTAssertNil(IDSScreen.attachPump.setupNext(workflowType: .replacement))
        XCTAssertEqual(IDSScreen.connectToPump.setupNext(workflowType: .replacement), .primeReservoir)
        XCTAssertEqual(IDSScreen.discardInfusionAssembly.setupNext(workflowType: .replacement), .prepareInsertionDevice)
        XCTAssertEqual(IDSScreen.prepareInsertionDevice.setupNext(workflowType: .replacement), .applyInfusionAssembly)
        XCTAssertEqual(IDSScreen.applyInfusionAssembly.setupNext(workflowType: .replacement), .checkCannula)
        XCTAssertEqual(IDSScreen.checkCannula.setupNext(workflowType: .replacement), .attachPump)
        XCTAssertEqual(IDSScreen.discardAllComponents.setupNext(workflowType: .replacement), .prepareInsertionDevice)
        XCTAssertEqual(IDSScreen.discardReservoir.setupNext(workflowType: .replacement), .fillReservoir)
        XCTAssertEqual(IDSScreen.fillReservoir.setupNext(workflowType: .replacement), .assemblePumpGuide)
        XCTAssertEqual(IDSScreen.primeReservoir.setupNext(workflowType: .replacement), .attachPump)
        XCTAssertEqual(IDSScreen.pumpBarcodeScanner.setupNext(workflowType: .replacement), .connectToPump)
        XCTAssertEqual(IDSScreen.pumpKeyEntryManual.setupNext(workflowType: .replacement), .connectToPump)
        XCTAssertNil(IDSScreen.replaceParts.setupNext(workflowType: .replacement))
        XCTAssertEqual(IDSScreen.selectPump.setupNext(workflowType: .replacement), .pumpKeyEntryManual)
        XCTAssertEqual(IDSScreen.setReservoirFillValue.setupNext(workflowType: .replacement), .pumpBarcodeScanner)
        XCTAssertNil(IDSScreen.settings.setupNext(workflowType: .replacement))
    }

    func testIDSScreenSetupNextOnboardingWorkflow() throws {
        XCTAssertEqual(IDSScreen.setupSystemComponents1.setupNext(workflowType: .onboarding), .waterUsage)
        XCTAssertEqual(IDSScreen.waterUsage.setupNext(workflowType: .onboarding), .setupSystemComponents2InfusionAssembly)
        XCTAssertEqual(IDSScreen.setupSystemComponents2InfusionAssembly.setupNext(workflowType: .onboarding), .infusionAssemblySetupStart)
        XCTAssertEqual(IDSScreen.setupSystemComponents2FillReservoir.setupNext(workflowType: .onboarding), .fillReservoirSetupStart)
        XCTAssertEqual(IDSScreen.setupSystemComponents2FillNeedle.setupNext(workflowType: .onboarding), .fillReservoirNeedleSetupStart)
        XCTAssertEqual(IDSScreen.infusionAssemblySetupStart.setupNext(workflowType: .onboarding), .infusionAssemblySetupVideo)
        XCTAssertEqual(IDSScreen.infusionAssemblySetupVideo.setupNext(workflowType: .onboarding), .infusionAssemblySteps1to3)
        XCTAssertEqual(IDSScreen.infusionAssemblySteps1to3.setupNext(workflowType: .onboarding), .infusionAssemblyStep4)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep4.setupNext(workflowType: .onboarding), .infusionAssemblyStep5)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep5.setupNext(workflowType: .onboarding), .infusionAssemblyStep6)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep6.setupNext(workflowType: .onboarding), .infusionAssemblyStep7)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep7.setupNext(workflowType: .onboarding), .infusionAssemblyStep8)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep8.setupNext(workflowType: .onboarding), .infusionAssemblyStep9)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep9.setupNext(workflowType: .onboarding), .infusionAssemblyStep10)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep10.setupNext(workflowType: .onboarding), .infusionAssemblyStep11)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep11.setupNext(workflowType: .onboarding), .infusionAssemblyStep12)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep12.setupNext(workflowType: .onboarding), .infusionAssemblyStep13)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep13.setupNext(workflowType: .onboarding), .infusionAssemblyStep14)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep14.setupNext(workflowType: .onboarding), .infusionAssemblyStep15)
        XCTAssertEqual(IDSScreen.infusionAssemblyStep15.setupNext(workflowType: .onboarding), .setupSystemComponents2FillReservoir)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStart.setupNext(workflowType: .onboarding), .fillReservoirSetupVideo)
        XCTAssertEqual(IDSScreen.fillReservoirSetupVideo.setupNext(workflowType: .onboarding), .fillReservoirSetupStep1)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep1.setupNext(workflowType: .onboarding), .fillReservoirSetupStep2)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep2.setupNext(workflowType: .onboarding), .fillReservoirSetupStep3)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep3.setupNext(workflowType: .onboarding), .fillReservoirSetupStep4)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep4.setupNext(workflowType: .onboarding), .fillReservoirSetupStep5)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep5.setupNext(workflowType: .onboarding), .fillReservoirSetupStep6)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep6.setupNext(workflowType: .onboarding), .fillReservoirSetupStep7)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep7.setupNext(workflowType: .onboarding), .fillReservoirSetupStep8)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep8.setupNext(workflowType: .onboarding), .fillReservoirSetupStep9)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep9.setupNext(workflowType: .onboarding), .fillReservoirSetupStep10)
        XCTAssertEqual(IDSScreen.fillReservoirSetupStep10.setupNext(workflowType: .onboarding), .connectToPump)
        XCTAssertEqual(IDSScreen.pumpBarcodeScanner.setupNext(workflowType: .onboarding), .connectToPump)
        XCTAssertEqual(IDSScreen.selectPump.setupNext(workflowType: .onboarding), .pumpKeyEntryManual)
        XCTAssertEqual(IDSScreen.pumpKeyEntryManual.setupNext(workflowType: .onboarding), .connectToPump)
        XCTAssertEqual(IDSScreen.setReservoirFillValue.setupNext(workflowType: .onboarding), .connectToPump)
        XCTAssertEqual(IDSScreen.connectToPump.setupNext(workflowType: .onboarding), .setupSystemComponents2FillNeedle)
        XCTAssertEqual(IDSScreen.fillReservoirNeedleSetupStart.setupNext(workflowType: .onboarding), .fillReservoirNeedleSetupWarning)
        XCTAssertEqual(IDSScreen.fillReservoirNeedleSetupWarning.setupNext(workflowType: .onboarding), .primeReservoir)
        XCTAssertEqual(IDSScreen.primeReservoir.setupNext(workflowType: .onboarding), .attachPump)
        XCTAssertEqual(IDSScreen.attachPump.setupNext(workflowType: .onboarding), .attachPump)
        XCTAssertEqual(IDSScreen.attachPump.setupNext(workflowType: .onboarding), .expirationConfiguration)
        XCTAssertEqual(IDSScreen.expirationConfiguration.setupNext(workflowType: .onboarding), .lowReservoirConfiguration)
        XCTAssertEqual(IDSScreen.lowReservoirConfiguration.setupNext(workflowType: .onboarding), .setupComplete)
        XCTAssertNil(IDSScreen.setupComplete.setupNext(workflowType: .onboarding))
    }

    func testIDSScreenMilestoneProgressScreen() throws {
        XCTAssertTrue(IDSScreen.applyInfusionAssembly.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertTrue(IDSScreen.assemblePumpGuide.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertTrue(IDSScreen.attachPump.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertTrue(IDSScreen.checkCannula.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertFalse(IDSScreen.connectToPump.isMilestoneProgressScreen(workflowType: .quickOnboarding))
        XCTAssertTrue(IDSScreen.discardAllComponents.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertTrue(IDSScreen.discardInfusionAssembly.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertTrue(IDSScreen.discardInfusionAssemblyAndReservoir.isMilestoneProgressScreen(workflowType: .quickOnboarding))
        XCTAssertTrue(IDSScreen.discardReservoir.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertTrue(IDSScreen.discardReservoirAndPumpBase.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertTrue(IDSScreen.fillReservoir.isMilestoneProgressScreen(workflowType: .quickOnboarding))
        XCTAssertTrue(IDSScreen.prepareInsertionDevice.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertTrue(IDSScreen.primeReservoir.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertFalse(IDSScreen.pumpBarcodeScanner.isMilestoneProgressScreen(workflowType: .quickOnboarding))
        XCTAssertFalse(IDSScreen.pumpKeyEntryManual.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertFalse(IDSScreen.replaceParts.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertFalse(IDSScreen.selectPump.isMilestoneProgressScreen(workflowType: .quickOnboarding))
        XCTAssertFalse(IDSScreen.setReservoirFillValue.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertFalse(IDSScreen.settings.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertTrue(IDSScreen.setupSystemComponents1.isMilestoneProgressScreen(workflowType: .quickOnboarding))
        XCTAssertTrue(IDSScreen.infusionAssemblySetupStart.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertTrue(IDSScreen.fillReservoirSetupStart.isMilestoneProgressScreen(workflowType: .onboarding))
        XCTAssertTrue(IDSScreen.fillReservoirNeedleSetupStart.isMilestoneProgressScreen(workflowType: .replacement))
        XCTAssertFalse(IDSScreen.attachPump.isMilestoneProgressScreen(workflowType: .removeAirBubbles))
    }

    func testStartOnboardingScreen() throws {
        XCTAssertEqual(IDSScreen.startOnboardingScreen, IDSScreen.setupSystemComponents1)
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
        viewCoordinator.navigateTo(.assemblePumpGuide)
        XCTAssertEqual(viewCoordinator.currentScreen, .assemblePumpGuide)
        XCTAssertEqual(viewCoordinator.screenStack, [.assemblePumpGuide])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .setReservoirFillValue)
        XCTAssertEqual(viewCoordinator.screenStack, [.assemblePumpGuide, .setReservoirFillValue])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .pumpBarcodeScanner)
        XCTAssertEqual(viewCoordinator.screenStack, [.assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .connectToPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner, .connectToPump])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .primeReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner, .connectToPump, .primeReservoir])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .attachPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner, .connectToPump, .primeReservoir, .attachPump])
    }
    
    func testViewControllerForScreenReplacementFlowInfusionAssembly() throws {
        setUpViewCoordinator()
        viewCoordinator.navigateTo(.replaceParts)
        XCTAssertEqual(viewCoordinator.currentScreen, .replaceParts)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts])
        
        viewCoordinator.navigateTo(.discardInfusionAssembly)
        XCTAssertEqual(viewCoordinator.currentScreen, .discardInfusionAssembly)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssembly])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .prepareInsertionDevice)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssembly, .prepareInsertionDevice])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .applyInfusionAssembly)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssembly, .prepareInsertionDevice, .applyInfusionAssembly])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .checkCannula)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssembly, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .attachPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssembly, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .attachPump])
    }

    func testViewControllerForScreenReplacementFlowReservoir() throws {
        setUpViewCoordinator()
        viewCoordinator.navigateTo(.replaceParts)
        XCTAssertEqual(viewCoordinator.currentScreen, .replaceParts)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts])

        viewCoordinator.navigateTo(.discardReservoir)
        XCTAssertEqual(viewCoordinator.currentScreen, .discardReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardReservoir])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .fillReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardReservoir, .fillReservoir])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .assemblePumpGuide)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardReservoir, .fillReservoir, .assemblePumpGuide])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .setReservoirFillValue)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardReservoir, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue])

        // since there is a reservoir replacement in the workflow, the setup helper navigates to connectToPump instead of the next screen
        viewCoordinator.navigateTo(.connectToPump)
        XCTAssertEqual(viewCoordinator.currentScreen, .connectToPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardReservoir, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .connectToPump])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .primeReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardReservoir, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .connectToPump, .primeReservoir])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .attachPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardReservoir, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .connectToPump, .primeReservoir, .attachPump])
    }

    func testViewControllerForScreenReplacementFlowInfusionAssemblyAndReservoir() throws {
        setUpViewCoordinator()
        viewCoordinator.navigateTo(.replaceParts)
        XCTAssertEqual(viewCoordinator.currentScreen, .replaceParts)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts])

        viewCoordinator.navigateTo(.discardInfusionAssemblyAndReservoir)
        XCTAssertEqual(viewCoordinator.currentScreen, .discardInfusionAssemblyAndReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .prepareInsertionDevice)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .applyInfusionAssembly)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .checkCannula)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula])

        // since there is a reservoir replacement in the workflow, the setup helper navigates to fill reservoir instead of the next screen
        viewCoordinator.navigateTo(.fillReservoir)
        XCTAssertEqual(viewCoordinator.currentScreen, .fillReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .assemblePumpGuide)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .setReservoirFillValue)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue])

        // since there is a reservoir replacement in the workflow, the setup helper navigates to connectToPump instead of the next screen
        viewCoordinator.navigateTo(.connectToPump)
        XCTAssertEqual(viewCoordinator.currentScreen, .connectToPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .connectToPump])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .primeReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .connectToPump, .primeReservoir])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .attachPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardInfusionAssemblyAndReservoir, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .connectToPump, .primeReservoir, .attachPump])
    }

    func testViewControllerForScreenReplacementFlowAllComponents() throws {
        setUpViewCoordinator()
        viewCoordinator.navigateTo(.replaceParts)
        XCTAssertEqual(viewCoordinator.currentScreen, .replaceParts)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts])
        
        viewCoordinator.navigateTo(.discardAllComponents)
        XCTAssertEqual(viewCoordinator.currentScreen, .discardAllComponents)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .prepareInsertionDevice)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .applyInfusionAssembly)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .checkCannula)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula])

        // since there is a reservoir replacement in the workflow, the setup helper navigates to fill reservoir instead of the next screen
        viewCoordinator.navigateTo(.fillReservoir)
        XCTAssertEqual(viewCoordinator.currentScreen, .fillReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .assemblePumpGuide)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .setReservoirFillValue)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .pumpBarcodeScanner)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .connectToPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner, .connectToPump])

        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .primeReservoir)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner, .connectToPump, .primeReservoir])
        
        viewCoordinator.navigateTo(try XCTUnwrap(viewCoordinator.currentScreen.setupNext(workflowType: .replacement)))
        XCTAssertEqual(viewCoordinator.currentScreen, .attachPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.replaceParts, .discardAllComponents, .prepareInsertionDevice, .applyInfusionAssembly, .checkCannula, .fillReservoir, .assemblePumpGuide, .setReservoirFillValue, .pumpBarcodeScanner, .connectToPump, .primeReservoir, .attachPump])
    }
    
    func testPopToRoot() throws {
        setUpViewCoordinator()

        viewCoordinator.navigateTo(.replaceParts)
        viewCoordinator.navigateTo(.discardInfusionAssembly)
        viewCoordinator.navigateTo(.attachPump)
        
        viewCoordinator.popToRoot()
        XCTAssertEqual(viewCoordinator.currentScreen, .replaceParts)
    }
    
    func testNavigateToPrevious() throws {
        setUpViewCoordinator()

        viewCoordinator.navigateTo(.replaceParts)
        viewCoordinator.navigateTo(.discardInfusionAssembly)
        
        viewCoordinator.navigateToPrevious()
        XCTAssertEqual(viewCoordinator.currentScreen, .replaceParts)
    }

    func testReplaceCurrentScreen() throws {
        setUpViewCoordinator()
        viewCoordinator.navigateTo(.assemblePumpGuide)
        XCTAssertEqual(viewCoordinator.currentScreen, .assemblePumpGuide)
        viewCoordinator.replaceCurrentScreen(with: .connectToPump)
        XCTAssertEqual(viewCoordinator.currentScreen, .connectToPump)
        XCTAssertEqual(viewCoordinator.screenStack, [.connectToPump])
    }
}

extension viewCoordinatorTests: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        didCreatePumpManager = true
    }
    
    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        didOnboardPumpManager = true
    }

    func pumpManagerOnboarding(didPauseOnboarding pumpManager: PumpManagerUI) {
    }
}
