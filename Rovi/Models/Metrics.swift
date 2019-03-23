//
//  Metrics.swift
//  Runner
//
//  Created by Catherine Thompson on 4/30/18.
//  Copyright © 2018 The Chromium Authors. All rights reserved.
//

import Foundation

struct Metrics: Codable {
    let gps: GpsCoord?
    let batteryLevel: Int?
    let charging: Bool?
    let heading: Int?
    let speed: Int?
    let timezone: String
    let altitude: Int?
    let temperature: Int?
    let signal_strength: Int?
    
    init(
        gps: GpsCoord? = nil,
        batteryLevel: Int? = nil,
        charging: Bool? = nil,
        heading: Int? = nil,
        speed: Int? = nil,
        altitude: Int? = nil, // in cm
        temperature: Int? = nil,
        signal_strength: Int? = nil,
        timezone: String? = NSTimeZone.system.identifier
    ) {
        self.gps = gps
        self.charging = charging
        self.altitude = altitude
        
        if let temperatureUnwrapped = temperature {
            self.temperature = temperatureUnwrapped
        }
        else {
            self.temperature = nil
        }
        
        if let signal_strengthUnwrapped = signal_strength {
            self.signal_strength = signal_strengthUnwrapped
        }
        else {
            self.signal_strength = nil
        }
        
        // a negative speed value indicates an invalid speed, should be excluded if negative
        if let speedUnwrapped = speed, speedUnwrapped > 0 {
            self.speed = speedUnwrapped
        } else {
            self.speed = nil
        }
        
        // a negative heading value indicates an invalid heading, should be excluded if negative
        if let headingUnwrapped = heading, headingUnwrapped > 0 {
            self.heading = headingUnwrapped
        } else {
            self.heading = nil
        }
        
        // a negative batteryLevel value indicates an invalid batteryLevel, should be excluded if negative
        if let batteryLevelUnwrapped = batteryLevel, batteryLevelUnwrapped > 0 {
            self.batteryLevel = batteryLevelUnwrapped
        } else {
            self.batteryLevel = nil
        }
        
        self.timezone = timezone!
    }
}
