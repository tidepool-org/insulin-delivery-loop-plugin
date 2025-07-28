//
//  SingleSelectionCheckListView.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI
import LoopKitUI

public struct SingleSelectionCheckListView<Item: Hashable>: View {
    let header: String?
    let footer: String?
    let items: [Item]
    @Binding var selectedItem: Item
    
    public init(header: String? = nil,
                footer: String? = nil,
                items: [Item],
                selectedItem: Binding<Item>) {
        self.header = header
        self.footer = footer
        self.items = items
        _selectedItem = selectedItem
    }
    
    public var body: some View {
        List {
            SingleSelectionCheckList(header: header, footer: footer, items: items, selectedItem: $selectedItem)
        }
        .insetGroupedListStyle()
    }
}

struct SingleSelectionCheckListView_Previews: PreviewProvider {
    static var previews: some View {
        ContentPreview {
            PreviewWrapper()
        }
    }
    
    struct PreviewWrapper: View {
        enum Shape: String, CaseIterable {
            case square = "Square"
            case circle = "Circle"
            case triangle = "Triangle"
            case rectangle = "Rectangle"
        }
        @State var selectedFruit: Shape = .square
        
        var body: some View {
            SingleSelectionCheckListView<Shape>(items: Shape.allCases,
                                                selectedItem: $selectedFruit)
        }
    }
}
