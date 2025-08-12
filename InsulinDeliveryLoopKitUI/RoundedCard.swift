//
//  RoundedCard.swift
//  InsulinDeliveryLoopKit
//
//  Created by Nathaniel Hamming on 2025-05-01.
//  Copyright © 2025 Tidepool Project. All rights reserved.
//

import SwiftUI

fileprivate let inset: CGFloat = 16

struct RoundedCardTitle: View {
    var title: String
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        FixedHeightText(title)
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: .leading, vertical: .center))
            .padding(.leading, titleInset)
    }

    private var isCompact: Bool {
        return self.horizontalSizeClass == .compact
    }

    private var titleInset: CGFloat {
        return isCompact ? inset : 0
    }
}

struct RoundedCardRowInstructions: View {
    var text: String
    
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        FixedHeightText(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: .leading, vertical: .center))
    }
}

struct RoundedCardFooter: View {
    var text: String
    var alignment: HorizontalAlignment

    init(_ text: String, alignment: HorizontalAlignment = .leading, inset footerInset: CGFloat? = nil) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        RoundedCardRowInstructions(text)
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .padding(.horizontal, inset)
    }
}

public struct RoundedCardValueRow: View {
    var label: String
    var value: String
    var highlightValue: Bool
    var highlightColor: Color
    var disclosure: Bool

    public init(label: String, value: String, highlightValue: Bool = false, highlightColor: Color = .accentColor, disclosure: Bool = false) {
        self.label = label
        self.value = value
        self.highlightValue = highlightValue
        self.highlightColor = highlightColor
        self.disclosure = disclosure
    }

    public var body: some View {
        HStack {
            FixedHeightText(label)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            Text(value)
                .fixedSize(horizontal: true, vertical: true)
                .foregroundColor(highlightValue ? highlightColor : .secondary)
            if disclosure {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
        }
    }
}

public struct RoundedCardToggleRow: View {
    var label: String
    @Binding var enabled: Bool
    let toggleTintColor: Color

    public var body: some View {
        Toggle(isOn: $enabled) {
            FixedHeightText(label)
        }
        .toggleStyle(SwitchToggleStyle(tint: toggleTintColor))
    }
}

struct RoundedCard<Content: View, HeroView: View>: View {
    var heroView: () -> HeroView?
    var content: () -> Content?
    var alignment: HorizontalAlignment
    var title: String?
    var footer: String?
    var backgroundColor: Color
    var stroke: (lineWidth: CGFloat, color: Color?)?
    var contentPadding: (horizontal: CGFloat, vertical: CGFloat)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init(title: String? = nil,
         footer: String? = nil,
         alignment: HorizontalAlignment = .leading,
         backgroundColor: Color = Color(.secondarySystemGroupedBackground),
         stroke: (lineWidth: CGFloat, color: Color?)? = nil,
         contentPadding: (horizontal: CGFloat, vertical: CGFloat) = (inset, inset),
         @ViewBuilder heroView: @escaping () -> HeroView? = { nil },
         @ViewBuilder content: @escaping () -> Content? = { nil }) {
        self.content = content
        self.heroView = heroView
        self.alignment = alignment
        self.title = title
        self.footer = footer
        self.backgroundColor = backgroundColor
        self.stroke = stroke
        self.contentPadding = contentPadding
    }

    var body: some View {
        VStack(spacing: 10) {
            if let title = title {
                RoundedCardTitle(title)
            }

            if hasContent {
                if isCompact {
                    VStack(spacing: 0) {
                        borderLine
                        
                        VStack(alignment: alignment, spacing: inset) {
                            heroView()
                            
                            VStack(
                                alignment: alignment,
                                spacing: 16,
                                content: content
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                        .padding(inset)
                        .background(backgroundColor)
                        
                        borderLine
                    }
                } else {
                    if let stroke = stroke {
                        ZStack {
                            cardContent
                            
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(lineWidth: stroke.lineWidth)
                                .foregroundColor(stroke.color)
                        }
                    } else {
                        cardContent
                    }
                }
            }

            if let footer = footer {
                RoundedCardFooter(footer)
            }
        }
    }
    
    private var hasContent: Bool {
        content() != nil || !(heroView() is EmptyView)
    }
    
    private var cardContent: some View {
        VStack(spacing: 0) {
            heroView()
            
            VStack(alignment: alignment, spacing: 16, content: content)
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                .padding(.horizontal, contentPadding.horizontal)
                .padding(.vertical, contentPadding.vertical)
                .background(backgroundColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    var borderLine: some View {
        Rectangle()
            .fill(Color(.quaternaryLabel))
            .frame(height: 0.5)
    }

    private var isCompact: Bool {
        return self.horizontalSizeClass == .compact
    }

    private var padding: CGFloat {
        return isCompact ? 0 : inset
    }

    private var cornerRadius: CGFloat {
        return isCompact ? 0 : 8
    }

}

extension RoundedCard where HeroView == EmptyView {
    init(title: String? = nil,
         footer: String? = nil,
         alignment: HorizontalAlignment = .leading,
         backgroundColor: Color = Color(.secondarySystemGroupedBackground),
         stroke: (lineWidth: CGFloat, color: Color?)? = nil,
         contentPadding: (horizontal: CGFloat, vertical: CGFloat) = (inset, inset),
         @ViewBuilder content: @escaping () -> Content? = { nil })
    {
        self.init(title: title, footer: footer, alignment: alignment, backgroundColor: backgroundColor, stroke: stroke, contentPadding: contentPadding, heroView: EmptyView.init, content: content)
    }
}


struct RoundedCardScrollView<Content: View>: View {
    var content: () -> Content
    var title: String?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                if let title = title {
                    HStack {
                        FixedHeightText(title)
                            .font(Font.largeTitle.weight(.bold))
                            .padding(.top)
                        
                        Spacer()
                    }
                    .padding([.leading, .trailing])
                    .navigationBarTitleDisplayMode(.inline)
                }
                
                VStack(alignment: .leading, spacing: 25, content: content)
                    .padding(padding)
            }
        }
    }

    private var padding: CGFloat {
        return self.horizontalSizeClass == .regular ? inset : 0
    }

}
