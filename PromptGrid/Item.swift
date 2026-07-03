//
//  Item.swift
//  PromptGrid
//
//  Created by Brian Cantin on 2026-07-03.
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
