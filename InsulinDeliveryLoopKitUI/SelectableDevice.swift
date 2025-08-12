//
//  SelectableDevice.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-02.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

struct SelectableDevice: View {
    @Environment(\.guidanceColors) var guidanceColors

    var device: Device
    @Binding var selectedDeviceSerialNumber: String?
    
    public init(device: Device, selectedDeviceSerialNumber: Binding<String?>) {
        self.device = device
        _selectedDeviceSerialNumber = selectedDeviceSerialNumber
    }

    private var formatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.day, .hour]
        return formatter
    }()
    
    public var body: some View {
        Button(action: {
            if selectedDeviceSerialNumber == device.serialNumber {
                selectedDeviceSerialNumber = nil
            } else {
                selectedDeviceSerialNumber = device.serialNumber
            }
        }) {
            HStack {
                Image(frameworkImage: device.imageName)
                    .resizable()
                    .aspectRatio(contentMode: ContentMode.fit)
                    .frame(height: 60)
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading) {
                        Text(device.name)
                            .font(.headline)
                        HStack(spacing: 0) {
                            FrameworkLocalizedText("SN: ", comment: "serial number short form identifier")
                            Text(device.serialNumber ?? "")
                        }
                    }
                    if let remainingLifetime = device.remainingLifetime,
                       let formattedRemainingLifetime = formatter.string(from: remainingLifetime)
                    {
                        FrameworkLocalizedText("Use Time Left: \(formattedRemainingLifetime)", comment: "Use time left for the pump (formattedRemainingLifetime = x days, y hours)")
                            .font(.caption)
                            .foregroundColor(guidanceColors.critical)
                    }
                }
                    
                Spacer()
                    
                if selectedDeviceSerialNumber == device.serialNumber {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SelectableDevice_Previews: PreviewProvider {
    static var previews: some View {
        let deviceSerialNumber = "GW681092"
        let device = Device(id: UUID(), name: "Test device", serialNumber: deviceSerialNumber, imageName: "unknown-device", remainingLifetime: .hours(16))
        return SelectableDevice(device: device, selectedDeviceSerialNumber: .constant(deviceSerialNumber))
    }
}
