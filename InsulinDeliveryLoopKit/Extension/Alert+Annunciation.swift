//
//  Alert+Annunciation.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-12.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit
import InsulinDeliveryServiceKit

extension Alert {
    init(with annunciation: Annunciation, managerIdentifier: String) {
        let title = annunciation.localizedTitle
        let body = annunciation.localizedMessage
        let dismissActionLabel = annunciation.localizedDismissActionLabel
        let interruptionLevel = annunciation.interruptionLevel
        let trigger = annunciation.annunciationTrigger
        
        let userAlertInAppContent = annunciation.hasInApp ?
            Alert.Content(title: title,
                          body: body,
                          acknowledgeActionButtonLabel: dismissActionLabel)
            : nil
        let userAlertNotificationContent = Alert.Content(title: title,
                                                         body: body,
                                                         acknowledgeActionButtonLabel: dismissActionLabel)
        self = Alert(identifier: Alert.Identifier(managerIdentifier: managerIdentifier,
                                                  alertIdentifier: annunciation.alertIdentifier),
                     foregroundContent: userAlertInAppContent,
                     backgroundContent: userAlertNotificationContent,
                     trigger: trigger,
                     interruptionLevel: interruptionLevel,
                     sound: Alert.Sound(from: annunciation.sound))
    }
}

extension Alert.AlertIdentifier {
    public init(from annunciation: Annunciation) {
        self = "\(annunciation.type.rawValue).\(annunciation.identifier)"
    }
    public func annunciationComponents() throws -> (type: AnnunciationType, identifier: AnnunciationIdentifier) {
        let components = components(separatedBy: ".")
        guard let typeComponent = components.first,
              let rawValue = UInt16(typeComponent),
              let identifierComponent = components.last,
              let identifier = AnnunciationIdentifier(identifierComponent)
        else {
            throw AnnunciationError.invalidAlertIdentifier
        }

        let type = AnnunciationType(rawValue: rawValue)
        return (type, identifier)
    }
}
