//
//  IDSViewCoordinator.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2025-04-29.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

import UIKit
import SwiftUI
import LoopKit
import LoopKitUI
import InsulinDeliveryLoopKit
import InsulinDeliveryServiceKit

enum IDSWorkflowType {
    case onboarding
    case replacement
}

enum IDSScreen: Int {
    case attachPump
    case basalRateScheduleEditorScreen
    case connectToPump
    case pumpKeyEntryManual
    case primeReservoir
    case replaceParts
    case selectPump
    case settings
    
    func setupNext(workflowType: IDSWorkflowType) -> IDSScreen? {
        switch self {
        case .basalRateScheduleEditorScreen:
            return IDSScreen.startOnboardingScreen
        case .connectToPump:
            return .primeReservoir
        case .pumpKeyEntryManual:
            return . connectToPump
        case .primeReservoir:
            return .attachPump
        case .selectPump:
            return .pumpKeyEntryManual
        case .replaceParts:
            return .selectPump
        default:
            return nil
        }
    }

    func isMilestoneProgressScreen(workflowType: IDSWorkflowType?) -> Bool {
        switch self {
        case .attachPump, .primeReservoir:
            return true
        default:
            return false
        }
    }

    static var startOnboardingScreen: IDSScreen {
        return .selectPump
    }
    
    static var settingsScreen: IDSScreen {
        return .settings
    }
}

protocol IDSViewNavigator: AnyObject {
    var currentScreen: IDSScreen { get }
    var workflowType: IDSWorkflowType? { get set }
    func navigateTo(_ screen: IDSScreen)
    func navigateToPrevious()
    func replaceCurrentScreen(with screen: IDSScreen)
    func navigateBackTo(_ screen: IDSScreen)
    func suspendOnboarding()
}

class IDSViewCoordinator: UINavigationController, PumpManagerOnboarding, CompletionNotifying, UINavigationControllerDelegate {

    public weak var pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?

    weak var completionDelegate: CompletionDelegate?
    
    var pumpManager: InsulinDeliveryPumpManager
    
    var pump: InsulinDeliveryPumpComms
    
    var workflowViewModel: WorkflowViewModel? = nil
    
    public var maxBasalRateUnitsPerHour: Double?

    public var maxBolusUnits: Double?

    private let colorPalette: LoopUIColorPalette

    public var basalSchedule: BasalRateSchedule?
    
    private var allowDebugFeatures: Bool

    var workflowType: IDSWorkflowType?

    var currentScreen: IDSScreen {
        return screenStack.last!
    }
    
    var screenStack = [IDSScreen]() {
        didSet {
            if !screenStack.isEmpty {
                if currentScreen.isMilestoneProgressScreen(workflowType: workflowType) {
                    storeMilestoneProgress()
                }
                if currentScreen == .startOnboardingScreen {
                    pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didCreatePumpManager: pumpManager)
                }
            }
        }
    }

    private func storeMilestoneProgress() {
        //pumpManager.updateReplacementWorkflowState(milestoneProgress: screenStack.map { $0.rawValue }, pumpSetupState: workflowViewModel?.pumpSetupState, selectedComponents: nil)
    }

    private func restoreMilestoneProgress() -> [IDSScreen]? {
        let screenStack = pumpManager.replacementWorkflowState.milestoneProgress.map { IDSScreen(rawValue: $0) }
        guard !screenStack.contains(where: { $0 == nil }),
              !screenStack.isEmpty,
              let pumpSetupState = pumpManager.replacementWorkflowState.pumpSetupState
        else {
            return nil
        }

        prepareWorkflowViewModel()
        workflowViewModel?.pumpSetupState = pumpSetupState

        return screenStack.compactMap { $0 }
    }
    
    private func viewControllerForFirstRunOnboardingScreen(_ screen: IDSScreen) -> UIViewController {
        switch screen {
        case .basalRateScheduleEditorScreen:
            let view = BasalRateScheduleEditor(schedule: basalSchedule,
                                               supportedBasalRates:InsulinDeliveryPumpManager.supportedBasalRates,
                                               maximumBasalRate:InsulinDeliveryPumpManager.maximumBasalRateAmount,
                                               maximumScheduleEntryCount:InsulinDeliveryPumpManager.maximumBasalScheduleEntryCount,
                                               syncBasalRateSchedule: { items, completion in
                guard let basalRateSchedule = BasalRateSchedule(dailyItems: items) else {
                    completion(.failure(InsulinDeliveryPumpManagerError.invalidBasalSchedule))
                    return
                }
                completion(.success(basalRateSchedule))
            },
                                               onSave: { [weak self] basalRateSchedule in
                guard let self = self else { return }
                self.basalSchedule = basalRateSchedule
                self.pumpManager.reportUpdatedBasalRateSchedule(basalRateSchedule)
                self.setupStepFinished()
            })
            return hostingController(rootView: view)
        default:
            fatalError("Wrong workflow for screen \(screen)")
        }
    }
    
    private func viewControllerForScreen(_ screen: IDSScreen) -> UIViewController {
        switch screen {
        case .attachPump:
            let view = AttachPumpView(viewModel: workflowViewModel!)
            return hostingController(rootView: view)
        case .connectToPump:
            let view = ConnectToPumpView(viewModel: workflowViewModel!)
            return hostingController(rootView: view)
        case .pumpKeyEntryManual:
            let view = PumpKeyEntryManualView(viewModel: workflowViewModel!)
            return hostingController(rootView: view)
        case .primeReservoir:
            let view = PrimePumpView(viewModel: workflowViewModel!)
            return hostingController(rootView: view)
        case .selectPump:
            prepareForNewPump()
            
            let view = SelectPumpView(viewModel: workflowViewModel!)
            return hostingController(rootView: view)
        case .settings:
            let viewModel = SettingsViewModel(pumpManager: pumpManager,
                                              navigator: self,
                                              completionHandler: { [weak self] in
                guard let self = self else {
                    return
                }
                self.completionDelegate?.completionNotifyingDidComplete(self)
            })
            let view = SettingsView(viewModel: viewModel)
            return hostingController(rootView: view)
        case .replaceParts:
            prepareWorkflowViewModel()
            let view = ReplaceComponentsView(viewModel: workflowViewModel!)
            return hostingController(rootView: view)
        default:
            return viewControllerForFirstRunOnboardingScreen(screen)
        }
    }
    
    private func hostingController<Content: View>(rootView: Content) -> DismissibleHostingController<some View> {
        let rootView = rootView.environment(\.allowDebugFeatures, allowDebugFeatures)
        let isOnboarded = pumpManager.isOnboarded
        let hostingController = DismissibleHostingController(content: rootView, isModalInPresentation: !isOnboarded, colorPalette: colorPalette)
        hostingController.navigationItem.backButtonDisplayMode = .generic
        return hostingController
    }
        
    private func setupStepFinished() {
        if let nextStep = currentScreen.setupNext(workflowType: workflowType!) {
            navigateTo(nextStep)
        } else {
            switch workflowType {
            case .onboarding:
                completePumpOnboarding()
            default:
                break
            }

            if workflowViewModel != nil {
                pumpManager.replacementWorkflowCompleted()
                resetWorkflowViewModel()
            }

            completionDelegate?.completionNotifyingDidComplete(self)
        }
    }

    private func removeObservers() {
        guard let workflowViewModel = workflowViewModel else { return }
        pumpManager.removePumpObserver(workflowViewModel)
        pumpManager.removePumpManagerStateObserver(workflowViewModel)
    }

    private func resetWorkflowViewModel() {
        removeObservers()
        workflowViewModel = nil
    }
    
    private func workflowCanceled() {
        pumpManager.replacementWorkflowCanceled()
        resetWorkflowViewModel()
        completionDelegate?.completionNotifyingDidComplete(self)
    }
    
    private func completePumpOnboarding() {
        pumpManager.markOnboardingCompleted()
        pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didOnboardPumpManager: pumpManager)
    }
    
    private func prepareWorkflowViewModel() {
        guard workflowViewModel == nil else {
            prepareForNewPump()
            return
        }

        workflowViewModel = WorkflowViewModel(pumpWorkflowHelper: pumpManager,
                                              navigator: self,
                                              workflowStepCompletionHandler: { [weak self] in self?.setupStepFinished() },
                                              workflowCanceledHandler: { [weak self] in self?.workflowCanceled() })

        workflowType = !pumpManager.isOnboarded ? .onboarding : .replacement
    }

    private func prepareForNewPump() {
        pumpManager.prepareForNewPump()
    }

    init(pumpManager:InsulinDeliveryPumpManager? = nil,
         pump: InsulinDeliveryPumpComms? = nil,
         colorPalette: LoopUIColorPalette,
         pumpManagerType:InsulinDeliveryPumpManager.Type? = nil,
         basalSchedule: BasalRateSchedule? = nil,
         maxBolusUnits: Double? = nil,
         allowDebugFeatures: Bool)
    {
        if pumpManager == nil,
           let pumpManagerType = pumpManagerType,
           let basalSchedule = basalSchedule,
           let maxBolusUnits = maxBolusUnits
        {
            let pumpState = pump?.state ?? IDPumpState()
            let pumpManagerState = InsulinDeliveryPumpManagerState(basalRateSchedule: basalSchedule, maxBolusUnits: maxBolusUnits, pumpState: pumpState)
            let pumpManager = pumpManagerType.init(state: pumpManagerState)
            self.pumpManager = pumpManager
            self.pump = pumpManager.pump
            self.maxBolusUnits = maxBolusUnits
            self.basalSchedule = basalSchedule
        } else {
            guard let pumpManager = pumpManager else {
                fatalError("Unable to createInsulinDeliveryPumpManager")
            }
            self.pumpManager = pumpManager
            self.pump = pumpManager.pump
            self.basalSchedule = pumpManager.state.basalRateSchedule
            self.maxBolusUnits = pumpManager.state.maxBolusUnits
        }

        self.colorPalette = colorPalette

        self.allowDebugFeatures = allowDebugFeatures

        super.init(navigationBarClass: UINavigationBar.self, toolbarClass: UIToolbar.self)
    }
    
    private func determineScreenStack() -> [IDSScreen] {
        guard let milestoneProgress = restoreMilestoneProgress() else {
            if !pumpManager.isOnboarded {
                prepareWorkflowViewModel()
                
                let unsupportedBasalRates = basalSchedule?.items.filter { repeatingScheduleValue in
                    !InsulinDeliveryPumpManager.supportedBasalRates.contains(repeatingScheduleValue.value)
                } ?? []
                
                return unsupportedBasalRates.isEmpty ? [.startOnboardingScreen] : [.basalRateScheduleEditorScreen]
            } else {
                return [.settingsScreen]
            }
        }

        return milestoneProgress
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if screenStack.isEmpty {
            screenStack = determineScreenStack()
            let viewControllers = screenStack.map { viewControllerForScreen($0) }
            setViewControllers(viewControllers, animated: false)
        }
    }
    
    var customTraitCollection: UITraitCollection {
        // Select height reduced layouts on iPhone SE and iPod Touch,
        // and select regular width layouts on larger screens, for list rendering styles
        if UIScreen.main.bounds.height <= 640 {
            return UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(verticalSizeClass: .compact)])
        } else {
            return UITraitCollection(traitsFrom: [super.traitCollection, UITraitCollection(horizontalSizeClass: .regular)])
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemGroupedBackground
        delegate = self
    }

    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {

        setOverrideTraitCollection(customTraitCollection, forChild: viewController)
        
        if viewControllers.count < screenStack.count {
            // Navigation back
            let _ = screenStack.popLast()
        }
        viewController.view.backgroundColor = UIColor.systemGroupedBackground

    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension IDSViewCoordinator: IDSViewNavigator {
    func navigateTo(_ screen: IDSScreen) {
        screenStack.append(screen)
        let viewController = viewControllerForScreen(screen)
        DispatchQueue.main.async { [weak self] in
            self?.pushViewController(viewController, animated: true)
        }
    }
    
    func navigateToPrevious() {
        let _ = screenStack.popLast()
        popViewController(animated: true)
    }
    
    func popToRoot() {
        screenStack.removeLast(screenStack.count - 1)
        popToRootViewController(animated: true)
    }

    func replaceCurrentScreen(with screen: IDSScreen) {
        _ = screenStack.popLast()
        _ = viewControllers.popLast()
        screenStack.append(screen)
        viewControllers.append(viewControllerForScreen(screen))
    }

    func navigateBackTo(_ screen: IDSScreen) {
        guard let screenIndex = screenStack.lastIndex(where: { $0 == screen }) else { return }

        screenStack.removeSubrange((screenIndex+1)..<screenStack.count)
        let viewController = viewControllers[screenIndex]
        self.popToViewController(viewController, animated: true)
    }

    func suspendOnboarding() {
        completionDelegate?.completionNotifyingDidComplete(self)
        pumpManagerOnboardingDelegate?.pumpManagerOnboarding(didPauseOnboarding: pumpManager)
    }
}
