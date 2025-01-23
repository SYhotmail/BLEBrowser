//
//  CGRect+Ext.swift
//  BLEBrowser
//
//  Created by Siarhei Yakushevich on 23/01/2025.
//

import Foundation
import CoreGraphics

extension CGRect {
    init(center: CGPoint,
         size: CGSize) {
        self.init(x: center.x - size.width * 0.5,
                  y: center.y - size.height * 0.5,
                  width: size.width,
                  height: size.height)
    }
    
    var center: CGPoint {
        .init(x: midX, y: midY)
    }
}
