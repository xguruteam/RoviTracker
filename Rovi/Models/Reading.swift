//
//  Reading.swift
//  Runner
//
//  Created by Catherine Thompson on 4/30/18.
//  Copyright © 2018 The Chromium Authors. All rights reserved.
//

import Foundation

struct Reading: Codable {
    var metrics: Metrics
    var timestamp: Date
    
    init(metrics: Metrics, timestamp: Date) {
        self.metrics = metrics
        self.timestamp = timestamp
    }
}

extension Reading {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any] else {
            throw NSError()
        }
        return dictionary
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metrics, forKey: .metrics)
        let formattedTs = Formatter.iso8601.string(from: self.timestamp as Date)
        try container.encode(formattedTs, forKey: .timestamp)
    }
}

extension Formatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }()
}
