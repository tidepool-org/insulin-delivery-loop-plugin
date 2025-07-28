//
//  IdentifiableClass.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2025-04-28.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

protocol IdentifiableClass: AnyObject {
    static var className: String { get }
}

extension IdentifiableClass {
    static var className: String {
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }
}
