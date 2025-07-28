//
//  AnnunciationType.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import LoopKit
import InsulinDeliveryServiceKit

extension AnnunciationType {
    public static let endOfPumpLifetime = AnnunciationType(rawValue: 0xffff)
    
    public var interruptionLevel: Alert.InterruptionLevel {
        switch self {
        case .mechanicalIssue:
            return .critical
        case .reservoirIssue:
            return .critical
        case .reservoirEmpty:
            return .critical
        case .batteryEmpty:
            return .critical
        case .occlusionDetected:
            return .critical
        case .primingIssue:
            return .timeSensitive
        case .reservoirLow:
            return .timeSensitive
        case .batteryLow:
            return .timeSensitive
        case .tempBasalCanceled:
            return .timeSensitive
        case .bolusCanceled:
            return .timeSensitive
        default:
            return classification?.interruptionLevel ?? .timeSensitive
        }
    }
    
    public var isResolvedByPumpReplacement: Bool {
        switch self {
        case .airPressureOutOfRange, .batteryEmpty, .infusionSetDetached, .infusionSetIncomplete, .mechanicalIssue, .occlusionDetected, .powerSourceInsufficient, .primingIssue, .reservoirEmpty, .reservoirIssue, .systemIssue, .temperatureOutOfRange:
            return true
        default:
            return false
        }
    }
    
    public var doesPumpNeedsReplacement: Bool {
        switch self {
        case .batteryEmpty, .mechanicalIssue, .occlusionDetected, .powerSourceInsufficient, .reservoirEmpty, .reservoirIssue, .systemIssue:
            return true
        default:
            return false
        }
    }
    
    public var statusHighlight: PumpStatusHighlight? {
        return insulinStatusHighlightLocalizedString.flatMap { PumpStatusHighlight(
            localizedMessage: $0,
            imageName: "exclamationmark.circle.fill",
            state: .critical)
        }
    }
    
    public func insulinDeliveryStatusLocalizedString(automaticDosingEnabled: Bool = true) -> String? {
        return insulinDeliveryStatusProblemHintLocalizedString(automaticDosingEnabled: automaticDosingEnabled).map { $0 + (insulinDeliveryStatusSolutionHintLocalizedString.map { " " + $0 } ?? "") }
    }
    
    func insulinDeliveryStatusProblemHintLocalizedString(automaticDosingEnabled: Bool) -> String? {
        switch self {
        case .batteryEmpty:
            return NSLocalizedString("Battery empty.", comment: "Battery empty problem descriptive hint text")
        case .batteryLow:
            return NSLocalizedString("The pump battery is almost empty.", comment: "Battery low problem descriptive hint text")
        case .mechanicalIssue:
            return NSLocalizedString("Insulin delivery stopped.", comment: "Mechanical issue problem descriptive hint text")
        case .occlusionDetected:
            return NSLocalizedString("Insulin delivery stopped.", comment: "Occlusion detected problem descriptive hint text")
        case .primingIssue:
            return NSLocalizedString("Reservoir needle not filled.", comment: "Priming issue problem descriptive hint text")
        case .reservoirEmpty:
            return NSLocalizedString("Reservoir empty.", comment: "Reservoir empty problem descriptive hint text")
        case .reservoirIssue:
            return NSLocalizedString("Programmed insulin amount differs from detected insulin amount.", comment: "Reservoir issue problem descriptive hint text")
        default:
            return isInsulinDeliveryStopped ? NSLocalizedString("Insulin delivery stopped.", comment: "Descriptive hint problem text when insulin delivery is stopped") : nil
        }
    }
    
    var insulinDeliveryStatusSolutionHintLocalizedString: String? {
        switch self {
        case .batteryLow:
            return LocalizedString("Replace the reservoir soon.", comment: "Battery low solution descriptive hint text")
        case .mechanicalIssue:
            return LocalizedString("Replace the reservoir now. If the error is still not resolved, replace the pump.", comment: "Mechanical issue solution descriptive hint text")
        default:
            return nil
        }
    }
}

extension AnnunciationType.Classification {
    public var interruptionLevel: Alert.InterruptionLevel {
        switch self {
        case .error, .maintenance:
            return .critical
        case .warning:
            return .timeSensitive
        case .reminder:
            return .active
        }
    }
    
    public var trigger: Alert.Trigger {
        return isRepeating ? .repeating(repeatInterval: repeatFrequency!) : .immediate
    }
}

extension LoopKit.Alert {
    func annunciationType() throws -> AnnunciationType {
        return try identifier.alertIdentifier.annunciationComponents().type
    }
}

extension Array where Element == PersistedAlert {
    func highestPriorityAnnunciationType() -> AnnunciationType? {
        try? self.filter {
            (try? $0.alert.annunciationType()) != nil
        }
        .map {
            (try $0.alert.annunciationType(), $0.issuedDate)
        }
        .sorted {
            // If the rank isn't the same, rank wins, otherwise most recent (last issuedDate) wins.
            $0.0.rank != $1.0.rank ? $0.0.rank > $1.0.rank : $0.1 > $1.1
        }
        .first?.0
    }
}
