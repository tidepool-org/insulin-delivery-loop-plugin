//
//  FrameworkLocalizedText.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

fileprivate class FrameworkReferenceClass {
    static let bundle = Bundle(for: FrameworkReferenceClass.self)
}

func FrameworkLocalizedText(_ key: LocalizedStringKey, comment: StaticString) -> Text {
    return Text(key, bundle: FrameworkReferenceClass.bundle, comment: comment)
}
