//
//  Utils.swift
//  Rovi
//
//  Created by Guru on 3/21/19.
//  Copyright © 2019 Luccas Beck. All rights reserved.
//

import Foundation

class Utils {
    public static func meter(fromRSSI rssi: Double) -> Double {
        let txPower: Double = -62
        var meter: Double = 0
        if rssi == 0 {
            meter = 0
        }
        let ratio = rssi * 1.0 / txPower
        if ratio < 1.0 {
            meter = pow(ratio, 10)
        }
        else {
            meter = 0.89976 * pow(ratio, 7.7095) + 0.111
        }
        
        meter = round(meter * 100.0) / 100.0
        return meter
    }
}
