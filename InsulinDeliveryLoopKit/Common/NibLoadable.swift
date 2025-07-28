//
//  NibLoadable.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 7/2/16.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import UIKit

protocol NibLoadable: IdentifiableClass {
    static func nib() -> UINib
}

extension NibLoadable {
    static func nib() -> UINib {
        return UINib(nibName: className, bundle: Bundle(for: self))
    }
}
