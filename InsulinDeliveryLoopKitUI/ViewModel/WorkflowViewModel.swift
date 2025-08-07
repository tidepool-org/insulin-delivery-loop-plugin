//
//  WorkflowViewModel.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2025-04-29.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import Network
import LoopKit
import InsulinDeliveryLoopKit
import InsulinDeliveryServiceKit
import BluetoothCommonKit

protocol OnboardingWorkflowViewModel: CancelWorkflowViewModel {
    func next()
}

class WorkflowViewModel: OnboardingWorkflowViewModel, ObservableObject {
    
    static let screenTitle = LocalizedString("Pump Setup", comment: "Title common to all pump setup screens")
    
    private let pumpWorkflowHelper: InsulinDeliveryPumpWorkflowHelper
    
    weak var navigator: IDSViewNavigator?
    
    private var pumpConnectionTimer: Timer?

    var devices: [Device] {
        deviceList.values.map { $0 }
    }

    @Published var deviceList: [String: Device] = [:]
    
    @Published var selectedDeviceSerialNumber: String?
    
    @Published var pumpSetupState: PumpSetupState

    var therapyState: InsulinTherapyControlState {
        pumpWorkflowHelper.therapyState
    }
    
    @Published var isPumpConnected: Bool

    @Published var connectToPumpTimedOut: Bool = false
    
    @Published var receivedReservoirIssue: Bool = false

    var remainingPumpLifetime: TimeInterval? {
        pumpWorkflowHelper.remainingPumpLifetime
    }
    
    var pumpHasBeenAuthenticated: Bool {
        pumpWorkflowHelper.isPumpAuthenticated
    }

    var operationalState: PumpOperationalState

    var initialReservoirLevel: Int {
        pumpWorkflowHelper.initialReservoirLevel
    }

    @objc var hasDetectedDevices: Bool {
        return !devices.isEmpty || isPumpConnected
    }
    
    var deviceSelected: Bool {
        return selectedDeviceSerialNumber != nil
    }

    private var workflowStepCompletionHandler: () -> Void

    private var workflowCanceledHandler: () -> Void

    var startInsulinDeliveryCompletion: ((Error?) -> Void)?
    var startPrimingCompletion: (() -> Void)?

    var workflowType: IDSWorkflowType {
        navigator!.workflowType!
    }

    var isConnectingToPump: Bool {
        pumpSetupState.inAuthenticationPendingState || pumpSetupState == .authenticated
    }
    
    init(pumpWorkflowHelper: InsulinDeliveryPumpWorkflowHelper,
         navigator: IDSViewNavigator,
         pumpSetupState: PumpSetupState = .advertising,
         workflowStepCompletionHandler: @escaping () -> Void = { },
         workflowCanceledHandler: @escaping () -> Void = { })
    {
        self.pumpWorkflowHelper = pumpWorkflowHelper
        self.navigator = navigator
        self.pumpSetupState = pumpSetupState
        self.workflowStepCompletionHandler = { DispatchQueue.main.async { workflowStepCompletionHandler() }}
        self.workflowCanceledHandler = workflowCanceledHandler
        isPumpConnected = pumpWorkflowHelper.isPumpConnected
        operationalState = pumpWorkflowHelper.operationalState
        
        pumpWorkflowHelper.addPumpObserver(self, queue: .main)
        pumpWorkflowHelper.addPumpManagerStateObserver(self, queue: .main)
    }
    
    private func prepareForNewPump() {
        reset()
        pumpWorkflowHelper.prepareForNewPump()
    }

    private func reset() {
        deviceList = [:]
        isPumpConnected = false
        pumpConnectionTimer?.invalidate()
        connectToPumpTimedOut = false
        selectedDeviceSerialNumber = nil
        pumpSetupState = .advertising
    }
    
    func connectToSelectedDevice() {
        guard let serialNumber = selectedDeviceSerialNumber else { return }
        workflowStepCompletionHandler()
    }
    
    func connectToPump(withSerialNumber serialNumber: String) {
        if let device = deviceList[serialNumber] {
            pumpWorkflowHelper.connectToPump(withIdentifier: device.id, andSerialNumber: serialNumber)
            startPumpConnectionTimer()
            pumpSetupState = .connecting
        }
    }

    private func startPumpConnectionTimer() {
        pumpConnectionTimer?.invalidate()
        pumpConnectionTimer = Timer.scheduledTimer(withTimeInterval: .seconds(120), repeats: true, block: { [weak self] _ in self?.connectToPumpTimedOut = true })
    }

    func pumpAssembled() {
        workflowStepCompletionHandler()
    }
    
    func deviceMatchingSerialNumber(_ serialNumber: String) -> Device? {
        deviceList[serialNumber]
    }

    func pumpKeyEntry(_ pumpKey: String) {
        guard let serialNumber = selectedDeviceSerialNumber else { return }

        pumpWorkflowHelper.setOOBString(pumpKey)
        connectToPump(withSerialNumber: serialNumber)
        workflowStepCompletionHandler()
    }

    func selectPumpAgain() {
        pumpSetupState = .advertising
        navigator?.navigateTo(.selectPump)
    }

    func connectToPumpAgain() {
        guard let serialNumber = selectedDeviceSerialNumber  else {
            selectPumpAgain()
            return
        }

        pumpWorkflowHelper.prepareForNewPump()
        connectToPump(withSerialNumber: serialNumber)
        pumpSetupState = .connecting
    }
    
    func repeatPumpSetup() {
        prepareForNewPump()
        navigator?.navigateBackTo(.selectPump)
    }

    func configurePump(completion: @escaping (Error?) -> Void) {
        pumpWorkflowHelper.configurePump() { [weak self] error in
            DispatchQueue.main.async {
                completion(error)
                if error == nil {
                    self?.pumpSetupState = .configured
                } else {
                    self?.pumpSetupState = .authenticated
                }
            }
        }
    }

    func startSetup() {
        workflowStepCompletionHandler()
    }

    func next() {
        workflowStepCompletionHandler()
    }
        
    func storeInitialReservoirLevel(initialReservoirLevel: Int) {
        pumpWorkflowHelper.initialReservoirLevel = initialReservoirLevel

        if pumpHasBeenAuthenticated != true {
            workflowStepCompletionHandler()
        } else {
            if !pumpWorkflowHelper.isPumpConnected {
                pumpSetupState = .connecting
                connectToPumpAgain()
            } else {
                pumpSetupState = .authenticated
                navigator?.navigateTo(.connectToPump)
            }
        }
    }
    
    func setReservoirLevel(completion: @escaping (Error?) -> Void) {
        pumpWorkflowHelper.setReservoirLevel(reservoirLevel: initialReservoirLevel) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(error)
                    return
                }

                if error == nil {
                    self.pumpSetupState = .configuring
                    self.configurePump(completion: completion)
                } else {
                    if let error = error as? DeviceCommError,
                       error == .procedureNotApplicable,
                       self.pumpWorkflowHelper.therapyState == .run
                    {
                        // the connected pump is still delivering insulin
                        self.stopInsulinDelivery(completion: { [weak self] stopInsulinDeliveryError in
                            guard let strongSelf = self else {
                                completion(error)
                                return
                            }
                            if stopInsulinDeliveryError == nil {
                                // insulin delivery has stopped, try again
                                strongSelf.setReservoirLevel(completion: completion)
                            } else {
                                completion(error)
                                strongSelf.pumpSetupState = .authenticated
                            }
                        })
                    } else {
                        completion(error)
                        self.pumpSetupState = .authenticated
                    }
                }
            }
        }
        pumpSetupState = .updatingTherapy
    }

    func pumpConfigurationCompleted() {
        workflowStepCompletionHandler()
    }
    
    func startPriming(completion: @escaping (Error?) -> Void) {
        pumpWorkflowHelper.startPriming() { [weak self] error in
            if error == nil {
                // priming does not actualy start until pump operational state changes to .priming
                self?.startPrimingCompletion = { DispatchQueue.main.async { completion(nil) } }
            } else {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    func stopPriming(completion: @escaping (Error?) -> Void) {
        pumpWorkflowHelper.stopPriming() { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }

    func issuePriming(completion: @escaping (Error?) -> Void) {
        guard pumpSetupState != .primingPumpStopped else {
            // if the priming has already stopped, no need to stop it
            pumpSetupState = .primingPumpIssue
            return
        }

        pumpSetupState = .primingPumpIssue
        stopPriming() { _ in }
    }

    func primingHasCompleted() {
        if pumpSetupState == .primingPump || pumpSetupState == .primingPumpStopped {
            pumpSetupState = .pumpPrimed
        }
        workflowStepCompletionHandler()
    }
    
    func startInsulinDelivery(completion: @escaping (Error?) -> Void) {
        guard therapyState != .run else {
            completion(nil)
            return
        }

        pumpWorkflowHelper.startInsulinDelivery() { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }

    func confirmInsulinDeliveryStarted() {
        completeWorkflow()
    }

    var isWorkflowCompleted: Bool {
        guard !(pumpSetupState == .startingTherapy &&
                pumpWorkflowHelper.operationalState == .ready &&
                pumpWorkflowHelper.therapyState == .run)
        else { return true }

        return pumpSetupState == .pumpPrimed &&
        pumpWorkflowHelper.operationalState == .ready &&
        pumpWorkflowHelper.therapyState == .run
    }

    private var isWorkflowCompletedJustInsulinDeliverySuspend: Bool {
        let primingCompleted = pumpSetupState == .pumpPrimed
        return navigator?.currentScreen == .attachPump && primingCompleted && operationalState == .ready && therapyState == .stop
    }

    private func completeWorkflow() {
        pumpSetupState = .therapyStarted
        workflowStepCompletionHandler()
    }

    func startInsulinDeliverySelected(completion: @escaping (Error?) -> Void) {
        startInsulinDelivery(completion: completion)
    }
    
    func replacePumpSelected() {
        prepareForNewPump()
        navigator?.navigateTo(.selectPump)
    }
}

extension WorkflowViewModel: InsulinDeliveryPumpObserver {
    func didDiscoverPump(name: String?,
                         identifier: UUID,
                         serialNumber: String?,
                         remainingLifetime: TimeInterval?)
    {
        if let name = name,
           let serialNumber = serialNumber
        {
            let device = Device(id: identifier,
                                name: name,
                                serialNumber: serialNumber,
                                imageName: "pump-simulator",
                                remainingLifetime: remainingLifetime)
            deviceList[serialNumber] = device
        }
    }
    
    func pumpDidCompleteAuthentication(error: DeviceCommError?) {
        guard let error = error else {
            deviceList = [:] // clear detected devices the pump is connected and authenticated
            pumpSetupState = .authenticated
            return
        }
        
        if error == .authenticationFailed {
            pumpSetupState = .authenticationFailed
        } else if error == .authenticationCancelled {
            pumpSetupState = .authenticationCancelled
        } else {
            pumpSetupState = .pumpAlreadyPaired
        }
    }

    func pumpDidUpdateState() {
        guard !isWorkflowCompleted else {
            return
        }

        isPumpConnected = pumpWorkflowHelper.isPumpConnected

        if operationalState != pumpWorkflowHelper.operationalState {
            operationalState = pumpWorkflowHelper.operationalState

            if operationalState == .ready,
               pumpSetupState == .primingPump
            {
                // reached the end of the pump priming command
                pumpSetupState = .primingPumpStopped
            }

            if operationalState == .priming {
                if pumpSetupState == .configured || pumpSetupState == .primingPumpStopped {
                    pumpSetupState = .primingPump
                    startPrimingCompletion?()
                    startPrimingCompletion = nil
                } else if pumpSetupState == .pumpPrimed {
                    pumpSetupState = .startingTherapy
                    startPrimingCompletion?()
                    startPrimingCompletion = nil
                }
            }
        }
    }

    func pumpConnectionStatusChanged(connected: Bool) {
        isPumpConnected = connected
        if pumpSetupState == .connecting && isPumpConnected {
            connectToPumpTimedOut = false
            pumpConnectionTimer?.invalidate()
            pumpSetupState = .authenticating
        }
    }
    
    func pumpEncounteredReservoirIssue() {
        receivedReservoirIssue = true
    }
}

//MARK: - Replacement workflow

extension WorkflowViewModel {
    var disconnectPumpWarning: String {
        var warning = LocalizedString("This will disconnect the pump from Tidepool Loop.", comment: "First part of replace system component disconnect pump warning")
        if therapyState == .run {
            warning = LocalizedString("This will stop insulin delivery and disconnect the pump from Tidepool Loop.", comment: "First part of replace system component will stop insulin delivery and disconnect pump warning")
        }
        return warning
    }

    var stopInsulinDeliveryWarning: String {
        LocalizedString("This will stop insulin delivery.", comment: "First part of replace system component will stop insulin delivery warning")
    }

    func stopInsulinDelivery(completion: @escaping (Error?) -> Void) {
        pumpWorkflowHelper.stopInsulinDelivery() { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }
    
    var virtualPump: VirtualInsulinDeliveryPump? {
        pumpWorkflowHelper.getVirtualPump()
    }
}

//MARK: - Cancel Workflow
extension WorkflowViewModel: CancelWorkflowViewModel {
    func warningButtonPrimary(completion: @escaping (AlertModalDetails?) -> Void) -> SwiftUI.Alert.Button {
        let buttonText: Text
        switch workflowType {
        case .onboarding:
            buttonText = FrameworkLocalizedText("Yes, cancel setup", comment: "Button label to cancel the setup workflow")
        case .replacement:
            buttonText = FrameworkLocalizedText("Yes, cancel replacement", comment: "Button label to cancel the replacement workflow")
        }

        return .destructive(buttonText) { [weak self] in
            self?.warningButtonAction(completion: completion)()
        }
    }

    func warningButtonAction(completion: @escaping (AlertModalDetails?) -> Void) -> AlertAction {
        switch workflowType {
        case .onboarding, .replacement:
            return { [weak self] in self?.cancelWorkflow(completion: completion) }
        }
    }

    var cancelWorkflowWarningTitle: AlertTitle {
        switch workflowType {
        case .onboarding:
            return LocalizedString("Are you sure you want to cancel setup?", comment: "Title of cancel setup workflow warning")
        case .replacement:
            return LocalizedString("Are you sure you want to cancel replacement?", comment: "Title of cancel replacement workflow warning")
        }
    }

    var cancelWorkflowWarningMessage: AlertMessage {
        guard !isWorkflowCompletedJustInsulinDeliverySuspend else {
            return LocalizedString("If you cancel now, you will have successfully completed this process, but insulin delivery will remain suspended. To resume delivery, tap 'Resume Insulin Delivery' on the home screen or in your pump settings.", comment: "Message of cancel workflow warning when the workflow was successful but insulin delivery is still suspended")
        }

        switch workflowType {
        case .onboarding:
            return LocalizedString("If you cancel now, you will return to the beginning of the pump setup.", comment: "Message of cancel onboarding workflow warning")
        case .replacement:
            return LocalizedString("If you cancel now, insulin delivery will remain suspended until you complete the replacement process.", comment: "Message of cancel replacement workflow warning")
        }
    }

    func cancelWorkflow(completion: @escaping (AlertModalDetails?) -> Void) {
        guard !isWorkflowCompletedJustInsulinDeliverySuspend else {
            pumpSetupState = .advertising
            workflowStepCompletionHandler()
            completion(nil)
            return
        }
        
        workflowCanceledHandler()
        pumpSetupState = .advertising
        completion(nil)
    }
}

struct Device: Identifiable, Equatable {
    let id: UUID
    let name: String
    let serialNumber: String?
    let imageName: String
    let remainingLifetime: TimeInterval?
}

extension WorkflowViewModel: InsulinDeliveryPumpManagerStateObserver {
    func pumpManagerDidUpdateState(_ pumpManager: InsulinDeliveryPumpManager, _ state: InsulinDeliveryPumpManagerState) {
        // NOP
    }
}
