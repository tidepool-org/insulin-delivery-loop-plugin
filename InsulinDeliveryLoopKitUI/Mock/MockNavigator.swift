//
//  MockNavigator.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2025-04-29.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import Foundation

class MockNavigator: IDSViewNavigator {

    public var screenStack: [IDSScreen] = []
    
    public var currentScreen: IDSScreen {
        get {
            return screenStack.last!
        }
        set {
            screenStack.append(newValue)
        }
    }
        
    var workflowType: IDSWorkflowType?
    
    public func navigateTo(_ screen: IDSScreen) {
        screenStack.append(screen)
    }
    
    public func navigateToPrevious() {
        screenStack.removeLast()
    }

    public func navigateBackTo(_ screen: IDSScreen) {
        guard let screenIndex = screenStack.lastIndex(where: { $0 == screen }) else  { return }
        screenStack.removeSubrange((screenIndex+1)..<screenStack.count)
    }
    
    public func resetTo(_ screen: IDSScreen) {
        screenStack.removeAll()
        screenStack.append(screen)
    }

    func replaceCurrentScreen(with screen: IDSScreen) {
        screenStack.removeLast()
        screenStack.append(screen)
    }

    func suspendOnboarding() { }
}
