//
//  Gps.swift
//  Runner
//
//  Created by Catherine Thompson on 4/30/18.
//  Copyright © 2018 The Chromium Authors. All rights reserved.
//

import Foundation

struct Gps: Codable {
    let lat: Double
    let lng: Double
}

struct GpsCoord: Codable {
    let lat: Double
    let lng: Double
    let accuracy: Double
}
