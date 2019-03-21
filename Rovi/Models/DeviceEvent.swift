//
//  DeviceEvent.swift
//  Runner
//
//  Created by Catherine Thompson on 11/27/18.
//  Copyright © 2018 The Chromium Authors. All rights reserved.
//

import Foundation

struct DeviceMeta: Codable {
    let collectedOn: Date
    let source: String = ""
    let other: [String: String] = [:]

    init(_ timestamp: Date) {
        self.collectedOn = timestamp
    }
}

extension DeviceMeta {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let formattedT = Formatter.iso8601.string(from: self.collectedOn as Date)
        try container.encode(formattedT, forKey: .collectedOn)
        try container.encode(source, forKey: .source)
        try container.encode(other, forKey: .other)
    }
}

enum Value: Codable {
    case double(Double)
    case string(String)
    case gps(Gps)
    case int(Int)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            self = try .double(container.decode(Double.self))
        } catch DecodingError.typeMismatch {
            do {
                self = try .string(container.decode(String.self))
            } catch DecodingError.typeMismatch {
                throw DecodingError.typeMismatch(Value.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Encoded payload not of an expected type"))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .gps(let gps):
            try container.encode(gps)
        case .int(let int):
            try container.encode(int)
        case .bool(let bool):
            try container.encode(bool)
        }
    }
}

struct DeviceReading: Codable {
    let value: Value
    let meta: DeviceMeta

    init(_ value: Value, _ timestamp: Date) {
        self.value = value
        self.meta = DeviceMeta(timestamp)
    }
}

struct DeviceEvent: Codable {
    let timestamp: Date
    var sensors: [String: DeviceReading]
    let meta: [String: String] = [:]
    let info: [String: String] = [:]
    let source: String = "mobile app"
    let type: String = "status"
    
    init(reading: Reading) {
        self.timestamp = reading.timestamp

        self.sensors = [
            "time-zone": DeviceReading(Value.string(reading.metrics.timezone), reading.timestamp)
        ]
        
        if let batteryLevel = reading.metrics.batteryLevel {
            self.sensors["device-battery-level"] = DeviceReading(Value.int(batteryLevel), reading.timestamp)
        }
        
        if let gpsCoord = reading.metrics.gps {
            // filters out inaccurate readings
            if (gpsCoord.accuracy < 100) {
                let gps = Gps(lat: gpsCoord.lat, lng: gpsCoord.lng)
                self.sensors["lat-lng"] = DeviceReading(Value.gps(gps), reading.timestamp)
            }
        }
        
        // Is in meters/sec -> converts to cm/sec
        if let speed = reading.metrics.speed {
            self.sensors["speed"] = DeviceReading(Value.int(speed), reading.timestamp)
        }
        
        if let heading = reading.metrics.heading {
            self.sensors["heading"] = DeviceReading(Value.int(heading), reading.timestamp)
        }
        
        if let charging = reading.metrics.charging {
            self.sensors["charging"] = DeviceReading(Value.bool(charging), reading.timestamp)
        }
        
        if let altitude = reading.metrics.altitude {
            self.sensors["altitude"] = DeviceReading(Value.int(altitude), reading.timestamp)
        }
    }
}

extension DeviceEvent {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sensors, forKey: .sensors)
        let formattedTs = Formatter.iso8601.string(from: self.timestamp as Date)
        try container.encode(formattedTs, forKey: .timestamp)
        try container.encode(meta, forKey: .meta)
        try container.encode(info, forKey: .info)
        try container.encode(source, forKey: .source)
        try container.encode(type, forKey: .type)
    }
}
