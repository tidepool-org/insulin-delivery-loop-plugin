//
//  MockPumpSettingsViewModel.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation
import InsulinDeliveryLoopKit
import InsulinDeliveryServiceKit
import BluetoothCommonKit

class MockPumpSettingsViewModel: ObservableObject {
    var virtualPump: VirtualInsulinDeliveryPump
    
    var pumpManager: InsulinDeliveryPumpManager?

    var disconnectComms: Bool

    var uncertainDeliveryCommandReceived: Bool

    @Published var uncertainDeliveryEnabled: Bool
    
    @Published var stoppedNotificationDelay: TimeInterval
    
    @Published var annunciationTypeToIssue: AnnunciationType?
    
    @Published var annunciationTypeToIssueDelay: TimeInterval

    @Published var authenticationError: SimulatedAuthenticationError = .none
    
    @Published var errorOnNextComms: SimulatedPumpCommError = .none

    @Published var reservoirString: String

    @Published var batteryLevelString: String
    
    @Published var fakePumpReplacementDate: Date?
    
    var reservoirRemaining: Double? {
        guard let reservoirRemaining = numberFormatter.number(from: reservoirString) else { return nil }
        return Double(truncating: reservoirRemaining)
    }

    var isBolusActive: Bool {
        virtualPump.isBolusActive
    }

    var isTempBasalActive: Bool {
        virtualPump.isTempBasalActive
    }

    var isDeliveringInsulin: Bool {
        virtualPump.state.isDeliveringInsulin
    }

    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var causeInsulinDeliveryInterruption: Bool = false

    var causeBolusInterruption: Bool = false

    var causeTempBasalInterruption: Bool = false

    init(virtualPump: VirtualInsulinDeliveryPump = VirtualInsulinDeliveryPump(), pumpManager: InsulinDeliveryPumpManager? = nil, annunciationTypeToIssueDelay: TimeInterval = .seconds(10)) {
        self.virtualPump = virtualPump
        self.disconnectComms = !virtualPump.isConnected
        self.uncertainDeliveryEnabled = virtualPump.uncertainDeliveryEnabled
        self.uncertainDeliveryCommandReceived = virtualPump.uncertainDeliveryCommandReceived
        let reservoirAmount: Double = virtualPump.deviceInformation?.reservoirLevel ?? 0
        reservoirString = numberFormatter.string(from: reservoirAmount) ?? ""
        let batteryLevel = virtualPump.deviceInformation?.batteryLevel ?? 100
        batteryLevelString = "\(batteryLevel)"
        stoppedNotificationDelay = virtualPump.stoppedNotificationDelay
        self.annunciationTypeToIssueDelay = annunciationTypeToIssueDelay
        self.pumpManager = pumpManager
        
        fakePumpReplacementDate = pumpManager?.lastPumpReplacementDate
    }

    func updateState() {
        errorOnNextComms = SimulatedPumpCommError(virtualPump.errorOnNextComms)
        disconnectComms = !virtualPump.isConnected
        authenticationError = SimulatedAuthenticationError(virtualPump.authenticationError)
        stoppedNotificationDelay = virtualPump.stoppedNotificationDelay

        let reservoirAmount: Double = virtualPump.deviceInformation?.reservoirLevel ?? 0
        reservoirString = numberFormatter.string(from: reservoirAmount) ?? ""
        
        let batteryLevel = virtualPump.deviceInformation?.batteryLevel ?? 100
        batteryLevelString = "\(batteryLevel)"

        fakePumpReplacementDate = pumpManager?.lastPumpReplacementDate
    }

    func commitUpdatedSettings() {
        virtualPump.errorOnNextComms = errorOnNextComms.commError
        virtualPump.isConnected = !disconnectComms
        virtualPump.authenticationError = authenticationError.commError
        virtualPump.stoppedNotificationDelay = stoppedNotificationDelay
        virtualPump.uncertainDeliveryEnabled = uncertainDeliveryEnabled
        virtualPump.uncertainDeliveryCommandReceived = uncertainDeliveryCommandReceived
        if let reservoirRemaining = reservoirRemaining {
            virtualPump.updateReservoirRemaining(reservoirRemaining)
        }
        virtualPump.deviceInformation?.batteryLevel = Int(batteryLevelString)
        if let annunciationTypeToIssue = annunciationTypeToIssue {
            virtualPump.issueAnnunciationForType(annunciationTypeToIssue, delayedBy: annunciationTypeToIssueDelay)
            self.annunciationTypeToIssue = nil
        }
        if causeInsulinDeliveryInterruption {
            virtualPump.interruptInsulinDelivery()
        }
        if causeBolusInterruption {
            virtualPump.interruptBolus()
        }
        if causeTempBasalInterruption {
            virtualPump.interruptTempBasal()
        }
        pumpManager?.lastPumpReplacementDate = fakePumpReplacementDate
        virtualPump.deviceInformation?.updateExpirationDate(replacementDate: fakePumpReplacementDate, lifespan: InsulinDeliveryPumpManager.lifespan)
    }
}

protocol SimulatedError: Hashable, Identifiable, CaseIterable where AllCases == Array<Self> {
    var commError: DeviceCommError? { get }
    var rawValue: String { get }
}
extension SimulatedError {
    var id: String { rawValue }
}

enum SimulatedPumpCommError: String, SimulatedError {
    case connectionTimeout
    case procedureNotApplicable
    case pumpNotReady
    case decryptionError
    case none

    init(_ error: DeviceCommError?) {
        switch error {
        case .connectionTimeout: self = .connectionTimeout
        case .procedureNotApplicable: self = .procedureNotApplicable
        case .deviceNotReady: self = .pumpNotReady
        case .securityManagerError(_): self = .decryptionError
        default: self = .none
        }
    }

    var commError: DeviceCommError? {
        switch self {
        case .connectionTimeout:
            return DeviceCommError.connectionTimeout
        case .procedureNotApplicable:
            return DeviceCommError.procedureNotApplicable
        case .pumpNotReady:
            return DeviceCommError.deviceNotReady
        case .decryptionError:
            return DeviceCommError.securityManagerError(.decryptionFailed)
        case .none:
            return nil
        }
    }
}

enum SimulatedAuthenticationError: String, SimulatedError {
    case authenticationFailed
    case pumpAlreadyPaired
    case none
    
    init(_ error: DeviceCommError?) {
        switch error {
        case .authenticationFailed: self = .authenticationFailed
        case .deviceAlreadyPaired: self = .pumpAlreadyPaired
        default: self = .none
        }
    }
    
    var commError: DeviceCommError? {
        switch self {
        case .authenticationFailed:
            return DeviceCommError.authenticationFailed
        case .pumpAlreadyPaired:
            return DeviceCommError.deviceAlreadyPaired
        case .none:
            return nil
        }
    }
}
