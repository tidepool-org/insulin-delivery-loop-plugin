//
//  PumpStatusHighlights.swift
//  InsulinDeliveryLoopKit
//
//  Created by Rick Pasetto on 5/5/22.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import LoopKit

public func SignalLossPumpStatusHighlight() -> PumpStatusHighlight {
    PumpStatusHighlight(localizedMessage: NSLocalizedString("Signal Loss", comment: "Status highlight that pump signal is lost."),
                        imageName: "exclamationmark.circle.fill",
                        state: .critical)
}

public func PumpExpiredStatusHighlight() -> PumpStatusHighlight {
    PumpStatusHighlight(localizedMessage: NSLocalizedString("Pump Expired", comment: "Status highlight that the pump has expired."),
                        imageName: "exclamationmark.circle.fill",
                        state: .critical)
}

public func InsulinSuspendedPumpStatusHighlight() -> PumpStatusHighlight {
    PumpStatusHighlight(localizedMessage: NSLocalizedString("Insulin Suspended", comment: "Status highlight that insulin delivery was suspended."),
                        imageName: "pause.circle.fill",
                        state: .warning)
}

public func IncompleteReplacementPumpStatusHighlight() -> PumpStatusHighlight {
    PumpStatusHighlight(localizedMessage: NSLocalizedString("Incomplete\nReplacement", comment: "Status highlight when a replacement workflow is incomplete."),
                        imageName: "exclamationmark.circle.fill",
                        state: .warning)
}

public func CompleteSetupPumpStatusHighlight() -> PumpStatusHighlight {
    PumpStatusHighlight(localizedMessage: NSLocalizedString("Complete Setup", comment: "Status highlight that onboarding is not yet completed."),
                        imageName: "exclamationmark.circle.fill",
                        state: .warning)
}
