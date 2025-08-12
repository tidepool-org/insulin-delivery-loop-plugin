//
//  PumpSetupState.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-05-19.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import LoopKitUI

public enum PumpSetupState: String, Codable {
    case advertising
    case connecting
    case authenticating
    case authenticationFailed
    case authenticationCancelled
    case pumpAlreadyPaired
    case authenticated
    case configured
    case configuring
    case updatingTherapy
    case primingPump
    case primingPumpStopped
    case primingPumpIssue
    case pumpPrimed
    case startingTherapy
    case therapyStarted
    
    public mutating func next() {
        switch self {
        case .advertising:
            self = .connecting
        case .connecting:
            self = .authenticating
        case .authenticating:
            self = .authenticated
        case .authenticationFailed:
            self = .advertising
        case .authenticationCancelled:
            self = .advertising
        case .pumpAlreadyPaired:
            self = .advertising
        case .authenticated:
            self = .updatingTherapy
        case .updatingTherapy:
            self = .configuring
        case .configuring:
            self = .configured
        case .configured:
            self = .primingPump
        case .primingPump:
            self = .pumpPrimed
        case .primingPumpStopped:
            self = .primingPump
        case .primingPumpIssue:
            break
        case .pumpPrimed:
            self = .startingTherapy
        case .startingTherapy:
            self = .therapyStarted
        case .therapyStarted:
            break
        }
    }
    
    public var showProgressDetail: Bool {
        switch self {
        case .connecting, .authenticating, .configuring, .updatingTherapy, .primingPump, .startingTherapy:
            return true
        default:
            return false
        }
    }
    
    public var progressState: ProgressIndicatorState {
        switch self {
        case .advertising, .primingPumpIssue, .authenticationFailed, .pumpAlreadyPaired, .authenticationCancelled:
            return .hidden
        case .connecting, .authenticating, .configuring, .updatingTherapy, .primingPump, .startingTherapy:
            return .indeterminantProgress
        case .authenticated, .configured, .primingPumpStopped, .pumpPrimed, .therapyStarted:
            return .completed
        }
    }
    
    public var isProcessing: Bool {
        switch self {
        case .connecting, .authenticating, .configuring, .updatingTherapy, .primingPump, .startingTherapy:
            return true
        default:
            return false
        }
    }
    
    public var isFinished: Bool {
        switch self {
        case .authenticated, .configured, .pumpPrimed, .primingPumpStopped, .therapyStarted:
            return true
        default:
            return false
        }
    }
    
    public var actionButtonDescription: String {
        switch self {
        case .advertising:
            return LocalizedString("Searching...", comment: "Action button description while searching for the pump")
        case .connecting:
            return LocalizedString("Connecting...", comment: "Action button description while connecting to the pump")
        case .authenticating:
            return LocalizedString("Authenticating...", comment: "Action button description while authenticating the pump")
        case .authenticationFailed:
            return LocalizedString("Enter Pump Information", comment: "Action button description when authentication has failed")
        case .authenticationCancelled:
            return LocalizedString("Try again", comment: "Action button description when authentication was cancelled")
        case .pumpAlreadyPaired:
            return LocalizedString("Replace Pump", comment: "Action button description when pump has already been paired")
        case .authenticated:
            return LocalizedString("Continue", comment: "Action button description when the pump is authenticated")
        case .configuring:
            return LocalizedString("Configuring...", comment: "Action button description while configuring the pump")
        case .updatingTherapy:
            return LocalizedString("Updating...", comment: "Action button description while updating the therapy details of the pump")
        case .configured:
            return LocalizedString("Start Priming", comment: "Action button description to start priming")
        case .primingPump:
            return LocalizedString("Stop Priming", comment: "Action button description to stop priming and continue to the next step")
        case .primingPumpStopped:
            return LocalizedString("No, continue Priming", comment: "Action button description when priming the pump stopped but can continue")
        case .primingPumpIssue:
            return LocalizedString("Unable to Prime Pump", comment: "Action button description when priming the pump has an issue")
        case .pumpPrimed:
            return LocalizedString("Start Insulin Delivery", comment: "Action button description to start insulin delivery")
        case .startingTherapy:
            return LocalizedString("Starting Insulin Delivery...", comment: "Action button description while starting insulin delivery")
        case .therapyStarted:
            return LocalizedString("Continue", comment: "Action button description when the insulin delivery has started")
        }
    }

    public var statusMessage: String {
        switch self {
        case .advertising:
            return LocalizedString("Searching for Pump", comment: "Status message while searching for the pump")
        case .connecting:
            return LocalizedString("Connecting to Pump", comment: "Communication status message when connecting to the pump")
        case .authenticating:
            return LocalizedString("Authenticating Pump", comment: "Communication status message when authenticating the pump")
        case .authenticationFailed:
            return LocalizedString("Authentication Failed", comment: "Status message when pump authentication has failed")
        case .authenticationCancelled:
            return LocalizedString("Authentication Cancelled", comment: "Status message when pump authentication was cancelled")
        case .pumpAlreadyPaired:
            return LocalizedString("Pump Already In-Use", comment: "Status message when pump has already been paired")
        case .authenticated:
            return LocalizedString("Pump Connected", comment: "Communication success message for pump authenticated")
        case .configuring:
            return LocalizedString("Updating Pump Settings", comment: "Communication status message when configuring the pump")
        case .updatingTherapy:
            return LocalizedString("Updating Pump Settings", comment: "Communication status message when updating therapy settings")
        case .configured:
            return LocalizedString("Pump Updated", comment: "Communication success message for pump updated")
        case .primingPump:
            return LocalizedString("Priming...", comment: "Status message to while priming the pump")
        case .primingPumpStopped:
            return LocalizedString("Priming the Pump Stopped", comment: "Status message when priming the pump stopped but can continue")
        case .primingPumpIssue:
            return LocalizedString("Issue Priming the Pump", comment: "Status message when priming the pump has an issue")
        case .pumpPrimed:
            return LocalizedString("Pump Primed", comment: "Status message when the pump has been primed")
        case .startingTherapy:
            return LocalizedString("Starting Insulin Delivery", comment: "Status message while starting insulin delivery")
        case .therapyStarted:
            return LocalizedString("Insulin Delivery Started", comment: "Status message when the insulin delivery has started")
        }
    }

    public var inAuthenticationPendingState: Bool {
        switch self {
        case .advertising, .connecting, .authenticating, .authenticationFailed, .authenticationCancelled, .pumpAlreadyPaired:
            return true
        default:
            return false
        }
    }
}
