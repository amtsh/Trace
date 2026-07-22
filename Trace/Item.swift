//
//  Item.swift
//  Trace
//
//  Created by Amit Shinde on 2026-07-22.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
