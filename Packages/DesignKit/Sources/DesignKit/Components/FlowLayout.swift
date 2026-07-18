//
//  FlowLayout.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/3/27.
//

import SwiftUI

public struct FlowLayout: Layout {
    public var horizontalSpacing: CGFloat
    public var verticalSpacing: CGFloat
    
    public init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }
    
    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        
        guard maxWidth > 0 else {
            let totalWidth = subviews.reduce(CGFloat.zero) { partial, subview in
                partial + subview.sizeThatFits(.unspecified).width
            }
            let maxHeight = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return CGSize(width: totalWidth, height: maxHeight)
        }
        
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            let proposedRowWidth: CGFloat
            if currentRowWidth == 0 {
                proposedRowWidth = size.width
            } else {
                proposedRowWidth = currentRowWidth + horizontalSpacing + size.width
            }
            
            if proposedRowWidth > maxWidth {
                totalHeight += currentRowHeight + verticalSpacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth = proposedRowWidth
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        
        totalHeight += currentRowHeight
        
        return CGSize(width: maxWidth, height: totalHeight)
    }
    
    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxWidth = bounds.width
        
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x > bounds.minX && x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += currentRowHeight + verticalSpacing
                currentRowHeight = 0
            }
            
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            
            x += size.width + horizontalSpacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}
