//
//  MockInsulinDeliveryPumpManager+Scenarios.swift
//  InsulinDeliveryLoopKit
//
//  Created by Cameron Ingham on 2/21/23.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import HealthKit
import LoopKit
import LoopTestingKit
import InsulinDeliveryServiceKit

extension MockInsulinDeliveryPumpManager: TestingPumpManager {
    public var reservoirFillFraction: Double {
        get {
            return reservoirLevel ?? 0 / pumpReservoirCapacity
        }
        set {
            // This is left blank intentionally
        }
    }
    
    public var testingDevice: HKDevice {
        status.device
    }
    
    public func trigger(action: DeviceAction) {
        guard let details = convertToDictionary(text: action.details) else { return }
        if "pumpReplacement" == details["type"] as? String {
            updatePumpReplacementDate(details["pumpOffset"] as? Double)
        } else if "insulinRemaining" == details["type"] as? String,
                  let reservoirLevelRemaining = details["reservoirLevelRemaining"] as? Double
        {
            virtualPump.status.updateReservoirRemaining(reservoirLevelRemaining)
        } else if "annunciation" == details["type"] as? String,
                  let annunciationTypeRaw = details["annunciationType"] as? AnnunciationType.RawValue,
                  let dateOffset = details["dateOffset"] as? TimeInterval
        {
            let annunciationType = AnnunciationType(rawValue: annunciationTypeRaw)
            virtualPump.issueAnnunciationForType(annunciationType, delayedBy: dateOffset)
        }
    }
    
    func convertToDictionary(text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any]
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
    
    private func updatePumpReplacementDate(_ pumpOffset: Double?) {
        if let offset = pumpOffset {
            updateExpiryWarningDuration(offset)
            let pumpReplacementDate = Date().addingTimeInterval(offset)
            virtualPump.state.deviceInformation?.updateExpirationDate(replacementDate: pumpReplacementDate, lifespan: InsulinDeliveryPumpManager.lifespan)
            replacementWorkflowState = replacementWorkflowState.updatedAfterReplacingPump({ pumpReplacementDate })
        }
        
        retractAllAlertsResolvedByPumpReplacement()
    }

    public func injectPumpEvents(_ pumpEvents: [NewPumpEvent]) {
        pumpDelegate.notify { delegate in
            delegate?.pumpManager(self, hasNewPumpEvents: pumpEvents, lastReconciliation: Date(), replacePendingEvents: true) { (error) in
                if let error = error {
                    self.log.error("Error storing pump events: %{public}@", String(describing: error))
                } else {
                    self.log.debug("Stored pump events: %{public}@", String(describing: pumpEvents))
                }
            }
        }
    }
    
    public func acceptDefaultsAndSkipOnboarding() {
        quickPumpSetup()
        markOnboardingCompleted()
    }
    
    private func quickPumpSetup() {
        var deviceInformation = MockInsulinDeliveryPumpStatus.deviceInformation
        deviceInformation.therapyControlState = .run
        deviceInformation.pumpOperationalState = .ready
        virtualPump.deviceInformation = deviceInformation
        virtualPump.status.pumpConfiguration = pumpConfiguration
        virtualPump.isConnected = true
        virtualPump.isAuthenticated = true
        
        virtualPump.status.initialReservoirLevel = 100
        virtualPump.status.basalProfile = state.basalRateSchedule.basalProfile
        virtualPump.status.pumpPrimed()
        virtualPump.status.startInsulinDelivery()
        
        replacementWorkflowState.lastPumpReplacementDate = Date()
    }
    
    private func longPumpSetup(completion: @escaping () -> Void) {
        connectToPump(withIdentifier: MockInsulinDeliveryPumpStatus.identifier, andSerialNumber: MockInsulinDeliveryPumpStatus.serialNumber)
        configurePump { _ in
            self.setReservoirLevel(reservoirLevel: 100) { _ in
                self.startPriming { _ in
                    self.stopPriming { _ in
                        self.startInsulinDelivery { _ in
                            self.replacementWorkflowState.lastPumpReplacementDate = Date()
                            completion()
                        }
                    }
                }
            }
        }
    }
}
