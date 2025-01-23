//
//  View+Frame.swift
//  BLEBrowser
//
//  Created by Siarhei Yakushevich on 23/01/2025.
//

import SwiftUI

extension View {
    func frame(size: CGSize, alignment: Alignment = .center) -> some View {
        frame(width: size.width, height: size.height, alignment: alignment)
    }
}
