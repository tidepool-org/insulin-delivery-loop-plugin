//
//  MockKeychainManager.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-07-28.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//


import XCTest
@testable import BluetoothCommonKit

public class MockKeychainManager: SecurePersistentAuthentication {
    var storage: [String: Data] = [:]
    
    public func setAuthenticationData(_ data: Data?, for keyService: String?) throws {
        guard let keyService = keyService else {
            return
        }

        storage[keyService] = data
    }

    public func getAuthenticationData(for keyService: String?) -> Data? {
        guard let keyService = keyService else {
            return nil
        }
        
        return storage[keyService]
    }
}
