//
//  ReservoirView.swift
//  InsulinDeliveryLoopKitUI
//
//  Created by Nathaniel Hamming on 2020-08-21.
//  Copyright © 2020 Tidepool Project. All rights reserved.
//

import UIKit
import LoopKitUI
import InsulinDeliveryLoopKit

public final class ReservoirView: BaseHUDView, NibLoadable {
    
    override public var orderPriority: HUDViewOrderPriority {
        return 11
    }

    @IBOutlet private weak var reservoirOpenView: UIImageView!
    @IBOutlet private weak var reservoirFullView: UIImageView!
    @IBOutlet private weak var volumeLabel: UILabel!
    
    private var viewModel = ReservoirHUDViewModel(userThreshold: Double(PumpConfiguration.defaultConfiguration.reservoirLevelWarningThresholdInUnits))
    
    public class func instantiate() -> ReservoirView {
        return nib().instantiate(withOwner: nil, options: nil)[0] as! ReservoirView
    }

    override public func awakeFromNib() {
        super.awakeFromNib()
        updateViews()
    }

    override public func tintColorDidChange() {
        super.tintColorDidChange()
        volumeLabel.textColor = tintColor
    }

    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0

        return formatter
    }()

    private func showFull() {
        volumeLabel.isHidden = true
        reservoirFullView.isHidden = false
        reservoirOpenView.isHidden = true
        tintColor = color
    }
    
    private func showOpen() {
        volumeLabel.isHidden = false
        reservoirFullView.isHidden = true
        reservoirOpenView.isHidden = false
        tintColor = color
    }
    
    private func updateViews() {
        switch viewModel.imageType {
        case .full:
            showFull()
        case .open:
            showOpen()
        }

        if let units = numberFormatter.string(for: viewModel.reservoirLevel) {
            volumeLabel.text = String(format: LocalizedString("%@U", comment: "Format string for reservoir volume. (1: The localized volume)"), units)
            accessibilityValue = String(format: LocalizedString("%1$@ units remaining", comment: "Accessibility format string for (1: localized volume)"), units)
        }
    }

    private var color: UIColor? {
        switch viewModel.warningColor {
        case .normal:
            return stateColors?.normal
        case .warning:
            return stateColors?.warning
        case .error:
            return stateColors?.error
        case .none:
            return stateColors?.unknown
        }
    }

    public func update(level: Double?, threshold: Int) {
        viewModel.reservoirLevel = level
        viewModel.userThreshold = Double(threshold)
        updateViews()
    }
}
