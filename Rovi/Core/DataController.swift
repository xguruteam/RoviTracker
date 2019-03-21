//
//  DataController.swift
//  Runner
//
//  Created by Catherine Thompson on 4/9/18.
//  Copyright © 2018 The Chromium Authors. All rights reserved.
//

import UIKit
import CoreData

typealias ReadingManagedObject = NSManagedObject

@available(iOS 10.0, *)
class DataController {
    var managedObjectContext: NSManagedObjectContext? = nil
    
    init() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        managedObjectContext = appDelegate.persistentContainer.viewContext
        printState("Init")
    }
    
    func addReading(_ reading: Reading) {
        NSLog("Add Reading: \(reading)")
        printState("Before add")
        guard let managedContext = managedObjectContext else { return }
        
        let entity = NSEntityDescription.entity(forEntityName: "Readings", in: managedContext)!
        let readings = NSManagedObject(entity: entity, insertInto: managedContext)
        
        readings.setValue(reading.timestamp, forKey: "timestamp")

        do {
            let metricsJson = try JSONEncoder().encode(reading.metrics)
            let metricsJsonString = String(data: metricsJson, encoding: .utf8)!
            
            readings.setValue(metricsJsonString, forKey: "metrics")
            
            printState("After add")
        } catch let error as NSError {
            NSLog("Could not save reading. \(error), \(error.userInfo)")
        }
    }

    func fetchReadings() -> [Reading] {
        guard let managedContext = managedObjectContext else { return [] }
        let fetchRequest = NSFetchRequest<ReadingManagedObject>(entityName: "Readings")

        do {
            let readingsSaved = try managedContext.fetch(fetchRequest)
            let readings = readingsSaved.map(self.toReading)
            
            return readings as! [Reading]
        } catch let error as NSError {
            NSLog("Could not fetch readings. \(error), \(error.userInfo)")
        }
        return []
    }
    
    func toReading(_ reading: ReadingManagedObject) -> Reading? {
        if let metricsJson = reading.value(forKey: "metrics"), let timestamp = reading.value(forKey: "timestamp") {
            let metricsJsonObj = (metricsJson as! String).data(using: .utf8)
            let metrics = try? JSONDecoder().decode(Metrics.self, from: metricsJsonObj!)
            
            return Reading(metrics: metrics!, timestamp: timestamp as! Date)
        }
        return nil
    }
    
    func clearData() {
        // saves the readings in the context to the persistent store
        save()
        
        printState("Before clear")
        
        guard let managedContext = managedObjectContext else { return }

        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Readings")
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let results = try managedContext.fetch(fetchRequest)
            for managedObject in results
            {
                let managedObjectData = managedObject as! ReadingManagedObject
                managedContext.delete(managedObjectData)
            }
            printState("After clear")
        } catch let error as NSError {
            NSLog("Clear Data error : \(error) \(error.userInfo)")
        }
    }
    
    func save() {
        NSLog("save")
        guard let managedContext = managedObjectContext else { NSLog("No Managed Context"); return }
        do {
            try managedContext.save()
        } catch let error as NSError {
            NSLog("Data Controller Save error : \(error)")
        }
    }
    
    func undo() {
        guard let managedContext = managedObjectContext else { NSLog("No Managed Context"); return }
        managedContext.undo()
    }
    
    func printState(_ message: String) {
        let readings = fetchReadings()
        NSLog("\(message): \(readings.count)")
    }
}
