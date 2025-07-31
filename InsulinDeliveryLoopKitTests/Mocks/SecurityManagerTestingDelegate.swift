//
//  SecurityManagerTestingDelegate.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-07-28.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//


import Foundation
@testable import BluetoothCommonKit

class SecurityManagerTestingDelegate: SecurityManagerDelegate {
    var sharedKeyData: Data? = nil
    
    func securityManagerDidEstablishedSecurity(_ securityManager: BluetoothCommonKit.SecurityManager) { }
    
    func securityManagerDidUpdateConfiguration(_ securityManager: BluetoothCommonKit.SecurityManager) { }
}