//
//  PumpStatusHighlights.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 5/5/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit

public struct SignalLossPumpStatusHighlight: DeviceStatusHighlight {
    public var localizedMessage = NSLocalizedString("Signal Loss", comment: "Status highlight that pump signal is lost.")
    public var imageName = "exclamationmark.circle.fill"
    public var state = DeviceStatusHighlightState.critical
}

public struct InsulinSuspendedPumpStatusHighlight: DeviceStatusHighlight {
    public var localizedMessage = NSLocalizedString("Insulin Suspended", comment: "Status highlight that insulin delivery was suspended.")
    public var imageName = "pause.circle.fill"
    public var state = DeviceStatusHighlightState.warning
}

public struct IncompleteReplacementPumpStatusHighlight: DeviceStatusHighlight {
    public var localizedMessage = NSLocalizedString("Incomplete\nReplacement", comment: "Status highlight when a replacement workflow is incomplete.")
    public var imageName = "exclamationmark.circle.fill"
    public var state = DeviceStatusHighlightState.warning
}

public struct CompleteSetupPumpStatusHighlight: DeviceStatusHighlight {
    public var localizedMessage = NSLocalizedString("Complete Setup", comment: "Status highlight that onboarding is not yet completed.")
    public var imageName = "exclamationmark.circle.fill"
    public var state = DeviceStatusHighlightState.warning
}

extension DeviceStatusHighlight {
    func isEqual(to other: DeviceStatusHighlight) -> Bool {
        return self.localizedMessage == other.localizedMessage &&
            self.imageName == other.imageName &&
            self.state == other.state
    }
}

extension Optional where Wrapped == DeviceStatusHighlight {
    func isEqual(to other: Wrapped?) -> Bool {
        switch (self, other) {
        case (.none, .none): return true
        case (.none, .some): return false
        case (.some, .none): return false
        case (.some(let self), .some(let other)): return self.isEqual(to: other)
        }
    }
}
