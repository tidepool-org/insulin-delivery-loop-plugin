//
//  InsulinDeliveryPump.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2020-03-23.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import CoreBluetooth
import UIKit
import LoopKit
import os.log
import TidepoolSecurity
import InsulinDeliveryServiceKit
import BluetoothCommonKit

// TODO remove
public protocol InsulinDeliveryPumpDelegate: AnyObject, IDPumpDelegate {
    var tidepoolSecurity: TidepoolSecurity? { get }
}

// TODO remove
public protocol InsulinDeliveryPumpComms: IDPumpComms {
    var pumpDelegate: InsulinDeliveryPumpDelegate? { get set }
    func configurePump(pumpConfiguration: PumpConfiguration,
                       initialConfiguration: Bool,
                       completion: @escaping ProcedureResultCompletion)
}

public class InsulinDeliveryPump: InsulinDeliveryService, InsulinDeliveryPumpComms {

    public static let name = "Insulin Delivery Pump"
    
    public weak var pumpDelegate: InsulinDeliveryPumpDelegate?
    
    private let log = OSLog(category: "InsulinDeliveryPump")
    
    var securePersistentAuthentication: () -> SecurePersistentAuthentication
    
    public override var sharedKeyData: Data? {
        get {
            return securePersistentAuthentication().getAuthenticationData(for: pumpKeyServiceIdentifier)
        }
        set {            
            try? securePersistentAuthentication().setAuthenticationData(newValue, for: pumpKeyServiceIdentifier)
        }
    }

    public convenience init(state: IDPumpState = IDPumpState(authorizationControlRequired: true),
                            securePersistentAuthentication: @escaping () -> SecurePersistentAuthentication = { KeychainManager() })
    {
        let bluetoothManager = BluetoothManager(peripheralIdentifier: state.deviceInformation?.identifier, peripheralConfiguration: .pumpGeneralConfiguration, servicesToDiscover: [InsulinDeliveryCharacteristicUUID.service.cbUUID])
        let bolusManager = BolusManager(activeBolusDeliveryStatus: state.activeBolusDeliveryStatus)
        let basalManager = BasalManager(activeTempBasalDeliveryStatus: state.activeTempBasalDeliveryStatus, totalBasalDelivered: state.totalBasalDelivered, lastTempBasalRate: state.lastTempBasalRate)
        let pumpHistoryEventManager = PumpHistoryEventManager(configuration: state.pumpHistoryEventManagerConfiguration)
        let securityManager = SecurityManager(configuration: state.securityManagerConfiguration)
        let acControlPoint = ACControlPointDataHandler(securityManager: securityManager, maxRequestSize: InsulinDeliveryPumpManager.maxRequestSize)
        let acData = ACDataDataHandler(securityManager: securityManager, maxRequestSize: InsulinDeliveryPumpManager.maxRequestSize)
        var state = state
        state.isAuthorizationControlRequired = true
        self.init(bluetoothManager: bluetoothManager,
                  bolusManager: bolusManager,
                  basalManager: basalManager,
                  pumpHistoryEventManager: pumpHistoryEventManager,
                  securityManager: securityManager,
                  acControlPoint: acControlPoint,
                  acData: acData,
                  state: state,
                  securePersistentAuthentication: securePersistentAuthentication)
    }
    
    public init(bluetoothManager: BluetoothManager,
                bolusManager: BolusManager,
                basalManager: BasalManager,
                pumpHistoryEventManager: PumpHistoryEventManager,
                securityManager: SecurityManager,
                acControlPoint: ACControlPointDataHandler,
                acData: ACDataDataHandler,
                state: IDPumpState,
                securePersistentAuthentication: @escaping () -> SecurePersistentAuthentication = { KeychainManager() },
                pendingAnnunciationCompletions: [ProcedureID : Any] = [:],
                isConnectedHandler: (() -> Bool)? = nil,
                isAuthenticatedHandler: (() -> Bool)? = nil,
                getCharacteristicForUUID: ((CBUUID) -> CBCharacteristic?)? = nil)
    {
        self.securePersistentAuthentication = securePersistentAuthentication
        super.init(bluetoothManager: bluetoothManager,
                   bolusManager: bolusManager,
                   basalManager: basalManager,
                   pumpHistoryEventManager: pumpHistoryEventManager,
                   securityManager: securityManager,
                   acControlPoint: acControlPoint,
                   acData: acData,
                   state: state,
                   pendingAnnunciationCompletions: pendingAnnunciationCompletions,
                   isConnectedHandler: isConnectedHandler,
                   isAuthenticatedHandler: isAuthenticatedHandler,
                   getCharacteristicForUUID: getCharacteristicForUUID)
        
        if state.isAuthorizationControlRequired == true {
            bluetoothManager.peripheralConfiguration = .pumpAuthorizationControlConfiguration
        } else {
            bluetoothManager.peripheralConfiguration = .pumpGeneralConfiguration
        }
        
        self.acControlPoint.certificateHandler = { [weak self] certificateNonce in
            guard let self = self,
                  let serialNumber = self.deviceInformation?.serialNumber
            else { return }
            
            Task {
                let certificateData = await self.getCertificateData(pumpSerialNumber: serialNumber, certificateNonceString: "\(certificateNonce)")
                guard let certificateData = certificateData else {
                    self.loggingDelegate?.logErrorEvent("Error during authentication. Could not get the wildcard or constrained certificate")
                    self.delegate?.pumpDidCompleteAuthentication(self, error: DeviceCommError.authenticationFailed)
                    return
                }
                
                self.completeKeyExchange(certificateData: certificateData)
            }
        }
    }
    
    override public func prepareForDeactivation(completion: @escaping ProcedureResultCompletion) {
        loggingDelegate?.logConnectionEvent()
        unpairPump() { [weak self] result in
            switch result {
            case .success:
                self?.bluetoothManager.prepareForDeactivation()
                self?.securityManager.prepareForDeactivation()
                self?.idStatusReader.lifetimeRemainingHandler = nil
                self?.acControlPoint.maxRequestSizeUpdatedHandler = nil
                self?.reset()
                completion(.success)
            default:
                completion(result)
            }
        }
    }

    public func prepareForAuthentication() {
        //TODO need to take steps to prepare for authentication (delete secrets)
        deleteStoredKey()
//        deleteConstrainedCertificate()
    }

    public func unpairPump(completion: @escaping ProcedureResultCompletion) {
        loggingDelegate?.logConnectionEvent()
        
        guard isAuthenticated else {
            loggingDelegate?.logConnectionEvent("pump was not authenticated. return success")
            completion(.success)
            return
        }

        guard isConnected else {
            loggingDelegate?.logConnectionEvent("pump was not connected. disconnect failure")
            completion(.failure(.disconnected))
            return
        }

        let invalidateKeyCompletion: ProcedureResultCompletion = { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
        
        let getRemainingLifetimeCompletion: ProcedureResultCompletion = { [weak self] result in
            switch result {
            case .success:
                self?.invalidateKey(completion: invalidateKeyCompletion)
            default:
                completion(result)
            }
        }
        
        guard state.isDeliveringInsulin else {
            self.getRemainingLifetime(completion: getRemainingLifetimeCompletion)
            return
        }
        
        self.suspendInsulinDelivery() { [weak self] result in
            switch result {
            case .success:
                self?.getRemainingLifetime(completion: getRemainingLifetimeCompletion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    //MARK: Procedure handling
    public func configurePump(pumpConfiguration: PumpConfiguration,
                              initialConfiguration: Bool = false,
                              completion: @escaping ProcedureResultCompletion)
    {
        loggingDelegate?.logSendEvent("Pump configuration is managed by the pump manager. Responding with success")
        self.delegate?.pumpDidCompleteConfiguration(self)
        completion(.success)
    }
   
    // TODO this could be reduced to just start priming and stop priming
    
    public func startPrimingReservoir(completion: @escaping ProcedureResultCompletion) {
        super.startPrimingReservoir(InsulinDeliveryPumpManager.primingAmount, completion: completion)
    }
        
    public func checkAndSetBasalRateSchedule(_ basalRateSchedule: BasalRateSchedule, completion: @escaping ProcedureResultCompletion) {
        guard basalRateSchedule.items.allSatisfy({ isValidBasalRate($0.value) }) else {
            loggingDelegate?.logErrorEvent("Invalid basal rate schedule \(basalRateSchedule)")
            completion(.failure(.parameterOutOfRange))
            return
        }
        
        super.setBasalProfile(basalRateSchedule.basalProfile, completion: completion)
    }

    public func checkAndSetBolus(_ amount: Double, activationType: IDBolusActivationType, completion: @escaping BolusDeliveryStatusCompletion) {
        guard isValidBolusVolume(amount) else {
            loggingDelegate?.logErrorEvent("Invalid bolus amount \(amount)")
            completion(.failure(.parameterOutOfRange))
            return
        }
        
        setBolus(amount, activationType: activationType, completion: completion)
    }
    
    public override func serialNumber(fromAdvertisementData advertisementData: [String: Any]?) -> String? {
        guard let advertisementData = advertisementData else { return nil }

        guard let serialNumber = advertisementData["kCBAdvDataLocalName"] as? String else { return  nil } // peripheral name is the
        
        return serialNumber
    }
    
    public override func updatePeripheralConfigurationIfNeeded(_ manager: BluetoothManager,
                                                               peripheralManager: PeripheralManager)
    {
        if state.isAuthorizationControlRequired {
            bluetoothManager.peripheralConfiguration = .pumpAuthorizationControlConfiguration
        } else {
            bluetoothManager.peripheralConfiguration = .pumpGeneralConfiguration
        }
    }
    
    public override func bluetoothManager(_ manager: BluetoothManager,
                                          peripheralManager: PeripheralManager,
                                          isReadyWithError error: Error?)
    {
        loggingDelegate?.logConnectionEvent("peripheral: \(peripheralManager), error: \(String(describing: error))")
        if isConnected {
            peripheralManager.perform { [weak self] peripheralManager in
                guard let self = self else { return }
                
                if !self.state.isAuthorizationControlRequired || self.securityManager.applicationSecurityEstablished {
                    self.getInsulinDeliveryFeatures { [weak self] result in
                        guard let self = self else { return }
                        self.state.features.update(with: [.supportedE2EProtection])
                        print("!!! features = \(self.state.features)")
                        switch result {
                        case .success():
                            self.getInsulinDeliveryStatus() { [weak self] result in
                                guard let self = self else { return }
                                switch result {
                                case .success():
                                    if self.bolusManager.isBolusActive {
                                        self.getActiveBolusDeliveredDetails() { _ in }
                                    }
                                    
                                    // REMOVE: reconnected. make the pump beep as a sanity check
                                    self.sendBeepRequest()
                                    
                                    if self.state.setupCompleted {
                                        self.loggingDelegate?.logSendEvent("Setup is completed. Checking for status changes to sync.")
                                        // check remaining lifetime of the pump
                                        self.getRemainingLifetime() { result in
                                            switch result {
                                            case .success:
                                                self.getInsulinDeliveryStatusChanged() { _ in }
                                            default:
                                                break
                                            }
                                        }
                                    }
                                    
                                    // report after it is known that authentication works, otherwise a disconnect occurs
                                    self.delegate?.pumpConnectionStatusChanged(self)
                                    self.delegate?.pumpDidCompleteAuthentication(self)
                                default:
                                    break
                                }
                            }
                        default:
                            break
                        }
                    }
                } else if !self.acControlPoint.hasRequestToSend {
                    // pump needs to be authenticated
                    guard bluetoothManager.peripheralConfiguration == .pumpAuthorizationControlConfiguration else {
                        return
                    }
                    self.startAuthentication(with: peripheralManager)
                }
            }
        } else if let nsError = error as NSError? {
            handleCBError(CBError(_nsError: nsError))
        }
    }

    //TODO duplicate from InsulinDeliveryServiceKit
    private func startAuthentication(with peripheralManager: PeripheralManager) {
        loggingDelegate?.logSendEvent("Preparing for pump authentication.")
        delegate?.pumpConnectionStatusChanged(self)
        acControlPoint.queueConfigurationRequests()
        loggingDelegate?.logSendEvent("Starting pump authentication.")
        loggingDelegate?.logSendEvent("Procedure \(String(describing: acControlPoint.procedureIDForNextRequest()))")
        acControlPoint.sendNextRequest(peripheralManager, timeout: 30)
    }
}

extension BasalRateSchedule {
    var basalProfile: [BasalSegment] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = startOfDay.addingTimeInterval(.days(1))
        let schedule = self.between(start: startOfDay, end: endOfDay)
        var basalProfile: [BasalSegment] = []
        for (index, entry) in schedule.enumerated() {
            basalProfile.append(BasalSegment(index: UInt8(index+1), rate: entry.value, duration: entry.endDate.timeIntervalSince(entry.startDate)))
        }
        return basalProfile
    }
}
