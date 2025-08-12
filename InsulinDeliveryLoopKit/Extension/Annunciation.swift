//
//  Annunciation.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import InsulinDeliveryServiceKit
import LoopKit

extension Annunciation {
    public static func alertIdentifierComponents(_ alertIdentifier: Alert.AlertIdentifier) -> (type: AnnunciationType, identifier: AnnunciationIdentifier)? {
        return try? alertIdentifier.annunciationComponents()
    }
    
    public var alertIdentifier: Alert.AlertIdentifier {
        Alert.AlertIdentifier(from: self)
    }
    
    var annunciationClassificationTitle: String {
        return type.classification?.title ?? "Unknown"
    }
    
    var annunciationTrigger: Alert.Trigger {
        return self.type.classification?.trigger ?? .immediate
    }
    
    var annunciationTitle: String {
        switch self.type {
        case .mechanicalIssue:
            return LocalizedString("Mechanical Error", comment: "Title of the mechanical issue annunciation")
        case .reservoirIssue:
            return LocalizedString("Deviation in Reservoir Amount", comment: "Title of the reservoir issue annunciation")
        case .reservoirEmpty:
            return LocalizedString("Reservoir Empty", comment: "Title of the reservoir empty annunciation")
        case .batteryEmpty:
            return LocalizedString("Battery Empty", comment: "Title of the battery empty annunciation")
        case .occlusionDetected:
            return LocalizedString("Occlusion Detected", comment: "Title of the occlusion detected annunciation")
        case .primingIssue:
            return LocalizedString("Reservoir Needle Not Filled", comment: "Title of the priming issue annunciation")
        case .reservoirLow:
            return LocalizedString("Low Reservoir", comment: "Title of the reservoir low annunciation")
        case .batteryLow:
            return LocalizedString("Battery Almost Empty", comment: "Title of the battery low annunciation")
        case .tempBasalCanceled:
            return LocalizedString("Temporary basal canceled", comment: "Title of the temp basal canceled annunciation")
        case .bolusCanceled:
            return LocalizedString("Bolus Delivery Interrupted", comment: "Title of the bolus canceled annunciation")
        default:
            return LocalizedString("Unknown annunciation", comment: "Title of an unknown annunciation")
        }
    }
    
    var annunciationMessageCauseFormat: String? {
        switch self.type {
        case .mechanicalIssue:
            return LocalizedString("Insulin delivery stopped.", comment: "Mechanical issue possible cause message.")
        case .reservoirIssue:
            return LocalizedString("Programmed insulin amount differs from detected insulin amount.", comment: "Reservoir issue possible cause message.")
        case .reservoirEmpty:
            return LocalizedString("Insulin delivery stopped.", comment: "Reservoir empty possible cause message.")
        case .batteryEmpty:
            return LocalizedString("Insulin delivery stopped.", comment: "Battery empty possible cause message.")
        case .occlusionDetected:
            return LocalizedString("Insulin delivery stopped.", comment: "Occlusion detected possible cause message.")
        case .primingIssue:
            return LocalizedString("Insulin delivery stopped.", comment: "Priming issue possible cause message.")
        case .reservoirLow:
            return LocalizedString("%1$@ insulin or less remaining in reservoir.", comment: "Format string for alert content body for reservoir low cause message. (1: current reservoir level value).")
        case .tempBasalCanceled:
            return LocalizedString("An active temporary basal rate was canceled.", comment: "Temporary basal rate canceled possible cause message.")
        case .bolusCanceled:
            return LocalizedString("Approximately %1$@ of %2$@ of insulin were delivered of a programmed bolus.", comment: "Bolus canceled possible cause message. (1: partial bolus amount delivered, 2: programmed total amount)")
        default:
            return nil
        }
    }
    
    var annunciationMessageCause: String? {
        annunciationMessageCauseFormat.map { String(format: $0, arguments: annunciationMessageCauseArgs) }
    }
    
    var annunciationMessageSolution: String? {
        switch self.type {
        case .mechanicalIssue:
            return LocalizedString("Replace the pump now.", comment: "Mechanical issue possible solution message.")
        case .reservoirIssue:
            return LocalizedString("Replace the reservoir now.", comment: "Reservoir issue possible solution message.")
        case .reservoirEmpty:
            return LocalizedString("Replace the reservoir now.", comment: "Reservoir empty possible solution message.")
        case .batteryEmpty:
            return LocalizedString("Replace the reservoir now.", comment: "Battery empty possible solution message.")
        case .occlusionDetected:
            return LocalizedString("Replace pump now. Then check your blood glucose.", comment: "Occlusion detected possible solution message.")
        case .primingIssue:
            return LocalizedString("Replace the pump now.", comment: "Priming issue possible solution message.")
        case .reservoirLow:
            return LocalizedString("Replace the reservoir soon.", comment: "Reservoir low possible solution message.")
        case .batteryLow:
            return LocalizedString("The pump battery is almost empty.", comment: "Battery low possible solution message.")
        case .tempBasalCanceled:
            return LocalizedString("Make sure that the cancellation was intentional. Program a new temporary basal rate if required.", comment: "Temporary basal rate canceled possible solution message.")
        case .bolusCanceled:
            return LocalizedString("Note the insulin amount already delivered and schedule a new bolus if necessary.", comment: "Bolus canceled possible solution message.")
        default:
            return nil
        }
    }
    
    public var hasInApp: Bool {
        return true
    }
    
    public var hasUserNotification: Bool {
        return true
    }
    
    public var localizedTitle: String {
        return annunciationTitle
    }
    
    public var localizedMessage: String {
        return [annunciationMessageCause, annunciationMessageSolution]
            .compactMap { $0 }
            .joined(separator: " ")
    }
    
    public var localizedDismissActionLabel: String {
        return LocalizedString("OK", comment: "Alert acknowledgment OK button")
    }
    
    //  Higher rank wins.
    public var rank: Int {
        return type.rank
    }
    
    public var interruptionLevel: Alert.InterruptionLevel {
        return type.interruptionLevel
    }
    
    public var sound: AlertSound {
        switch type.classification {
        case .error:
            return .error
        case .maintenance:
            return .maintenance
        case .warning:
            return .warning
        default:
            return .`default`
        }
    }
}
