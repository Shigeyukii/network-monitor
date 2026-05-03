//
//  Item.swift
//  network-monitor
//
//  Created by 目時重孝 on 2026/05/03.
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
