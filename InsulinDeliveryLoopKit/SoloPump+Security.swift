//
//  SoloPump+Security.swift
//  RocheSoloKit
//
//  Created by Nathaniel Hamming on 2025-03-26.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import UIKit
import LoopKit
import PotentASN1
import ShieldOID
import Shield

extension SoloPump {
    var pumpKeyServiceIdentifier: String { "org.tidepool.RocheSoloKit.Key.Shared" }
    
    private var wildcardIdentifierKey: String { "org.tidepool.RocheSoloKit.Key.Wildcard" }
    
    private var wildcardIdentifierCertificate: String { "org.tidepool.RocheSoloKit.Certificate.Wildcard" }
    
    private var constrainedIdentifierCertificate: String { "org.tidepool.RocheSoloKit.Certificate.Constrained" }
    
    private var appTypeID: String { "1" }
    
    private var appInstanceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "209648d4-4948-4aa2-9786-2fcadc0b2bad" }
    
    private var hardwareVersion: String { UIDevice.current.model }
    
    private var softwareVersion: String { UIDevice.current.systemVersion }
    
    private var phdTypeID: String { "775" }
    
    private var wildcardCertificateType: String { "WILDCARD" }
    
    private var constrainedCertificateType: String { "CONSTRAINED" }
    
    private(set) var wildcardKeyData: Data? {
        get {
            return securePersistentPumpAuthentication().getAuthenticationData(for: wildcardIdentifierKey)
        }
        set {
            guard let wildcardKeyData = newValue else {
                return
            }
            
            try? securePersistentPumpAuthentication().setAuthenticationData(wildcardKeyData, for: wildcardIdentifierKey)
        }
    }
    
    private(set) var wildcardCertificateData: Data? {
        get {
            return securePersistentPumpAuthentication().getAuthenticationData(for: wildcardIdentifierCertificate)
        }
        set {
            guard let wildcardCertificateData = newValue else {
                return
            }
            
            try? securePersistentPumpAuthentication().setAuthenticationData(wildcardCertificateData, for: wildcardIdentifierCertificate)
        }
    }
    
    private(set) var constrainedCertificateData: Data? {
        get {
            return securePersistentPumpAuthentication().getAuthenticationData(for: constrainedIdentifierCertificate)
        }
        set {
            guard let constrainedCertificateData = newValue else {
                return
            }
            
            try? securePersistentPumpAuthentication().setAuthenticationData(constrainedCertificateData, for: constrainedIdentifierCertificate)
        }
    }
    
    func getCSRBase64(pumpSerialNumber: String, certificateNonceString: String) -> String? {
        guard let csrBase64Encoded = try? createCSR(pumpSerialNumber: pumpSerialNumber, certificateNonceString: certificateNonceString)?.encoded().base64EncodedString() else { return nil }
        return csrBase64Encoded
    }
    
    func createCSR(pumpSerialNumber: String, certificateNonceString: String) -> CertificationRequest? {
        securityManager.generateKeyPair()

        guard let clientPrivateKey = securityManager.clientPrivateKey,
              let clientPublicKey = SecKeyCopyPublicKey(clientPrivateKey)
        else { return nil }

        let appKeyPair = SecKeyPair(privateKey: clientPrivateKey, publicKey: clientPublicKey)

        let appCSRSubject = NameBuilder()
            .add("Tidepool Project", forType: iso_itu.ds.attributeType.organizationName.oid)
            .add("Tidepool Loop", forType: iso_itu.ds.attributeType.name.oid)
            .add(appTypeID, forType: iso_itu.ds.attributeType.commonName.oid)
            .add(appInstanceID, forType: iso_itu.ds.attributeType.serialNumber.oid)
            .add(phdTypeID, forType: iso_itu.ds.attributeType.surname.oid)
            .add(pumpSerialNumber, forType: iso_itu.ds.attributeType.givenName.oid)
            .add(certificateNonceString, forType: iso_itu.ds.attributeType.pseudonym.oid)
            .name

        return try? CertificationRequest.Builder()
            .subject(name: appCSRSubject)
            .publicKey(keyPair: appKeyPair, usage: [.nonRepudiation, .digitalSignature, .keyAgreement])
            .build(signingKey: appKeyPair.privateKey, digestAlgorithm: .sha256)
    }
    
    func getCertificateData(pumpSerialNumber: String, certificateNonceString: String) async -> (constrained: Data?, wildcard: Data?) {
        
        guard let tidepoolSecurity = soloPumpDelegate?.tidepoolSecurity else {
            loggingDelegate?.logErrorEvent("tidepool security not available")
            return (nil, wildcardCertificateData)
        }
        
        guard let csr = getCSRBase64(pumpSerialNumber: pumpSerialNumber, certificateNonceString: certificateNonceString) else {
            loggingDelegate?.logErrorEvent("Could not create CSR")
            return (nil, wildcardCertificateData)
        }
        
        do {
            let partnerData = [
                "rcTypeId": appTypeID,
                "rcInstanceId": appInstanceID,
                "rcHWVersion": hardwareVersion,
                "rcSWVersion": softwareVersion,
                "phdTypeId": phdTypeID,
                "phdInstanceId": pumpSerialNumber,
                "csr": csr
            ]
            
            let responseData = try await tidepoolSecurity.sendAppAssertion(partnerIdentifier: "Coastal", partnerData: partnerData)
            let assertionResponse = try JSONDecoder.tidepool.decode(AssertionResponse.self, from: responseData)
            
            if let wildcardCertificateBase64Encoded = assertionResponse.data.certificates.first(where: { $0.type == wildcardCertificateType })?.content {
                guard let clientPrivateKey = securityManager.clientPrivateKey else {
                    return (nil, nil)
                }
                wildcardCertificateData = Data(base64Encoded: wildcardCertificateBase64Encoded)
                
                // save the key used to create the wildcard certificate to be used when needed
                var error: Unmanaged<CFError>?
                wildcardKeyData = SecKeyCopyExternalRepresentation(clientPrivateKey, &error) as Data?
            }
            
            guard let constrainedCertificateBase64Encoded = assertionResponse.data.certificates.first(where: { $0.type == constrainedCertificateType })?.content else {
                return (nil, wildcardCertificateData)
            }
            
            constrainedCertificateData = Data(base64Encoded: constrainedCertificateBase64Encoded)
            return (constrainedCertificateData, wildcardCertificateData)
        } catch let error {
            loggingDelegate?.logErrorEvent("Error sending assertion \(error.localizedDescription.debugDescription)")
            
            // when failures occur, return the wildcard certificate
            guard let wildcardKey = loadWildcardKey() else {
                loggingDelegate?.logErrorEvent("Error loading the wildcard key")
                return (nil, nil)
            }
            
            securityManager.clientPrivateKey = wildcardKey
            return (nil, wildcardCertificateData)
        }
    }
    
    private func loadWildcardKey() -> SecKey? {
        let privateAttributes = [kSecAttrKeySizeInBits: 256,
                                       kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                                      kSecAttrKeyClass: kSecAttrKeyClassPrivate,
                                   kSecPrivateKeyAttrs: [kSecAttrIsPermanent: false]] as [CFString : Any] as CFDictionary
        
        var error: Unmanaged<CFError>?
        
        guard let certificateKeyData = wildcardKeyData else { return nil }
        
        let certificateKey = SecKeyCreateWithData(NSData(data: certificateKeyData) as CFData, privateAttributes, &error)
        if let error = error {
            loggingDelegate?.logErrorEvent("wildcard certificate key creation failed \(String(describing: error))")
        }
        
        return certificateKey
    }
    
    struct AssertionResponse: Codable {
        let data: AssertionData
    }
    
    struct AssertionData: Codable {
        let certificates: [CertificateResponse]
    }
    
    struct CertificateResponse: Codable {
        let content: String
        let ttlInDays: Int
        let type: String
    }
}

public protocol SecurePersistentPumpAuthentication {
    func setAuthenticationData(_ data: Data?, for keyService: String?) throws
    func getAuthenticationData(for keyService: String?) -> Data?
}

extension KeychainManager: SecurePersistentPumpAuthentication {
    public func setAuthenticationData(_ data: Data?, for keyService: String?) throws {
        if let keyService = keyService {
            try replaceGenericPassword(data, forService: keyService)
        }
    }

    public func getAuthenticationData(for keyService: String?) -> Data? {
        guard let keyService = keyService else {
            return nil
        }
        return try? getGenericPasswordForServiceAsData(keyService)
    }
}
