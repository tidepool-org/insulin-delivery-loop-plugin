//
//  MutuallyExclusive.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

class MutuallyExclusive<T: Hashable>: ObservableObject {
    
    @Published var cases: [T: Bool]
        
    init(cases: [T]) {
        self.cases = Dictionary(uniqueKeysWithValues: cases.map { ($0, false) })
    }
    
    func binding(for key: T) -> Binding<Bool> {
        return Binding(
            get: {
                self.cases[key] == true
            },
            set: { newValue in
                self.cases[key] = newValue
                for k in self.cases.keys {
                    if k != key {
                        self.cases[k] = false
                    }
                }
            }
        )
    }
    
    func isSet(for key: T) -> Bool {
        cases[key] == true
    }
    
}
