//
//  BeaconTracker.swift
//  CoreiBeacon
//
//  Created by Luccas Beck on 8/1/18.
//  Copyright © 2018 Luccas Beck. All rights reserved.
//

import Foundation
import CoreLocation
import CoreBluetooth
import UIKit
import os.log

//MARK: Log functions
class Log {
    static func e(_ message: String) {
        if #available(iOS 10.0, *) {
            os_log("%@", log: OSLog.default, type: .error, message)
        } else {
            print("CoreiBeacon Error: \(message)")
        }
    }
    
    static func d(_ message: String) {
        self.e(message)
    }
}

//MARK: Common UUID

let ESTIMOTE_UUID = "B9407F30-F5F8-466E-AFF9-25556B57FE6D"
let I6_UUID = "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"

//MARK: CLBeacon Extension
extension CLBeacon {
    var keyString: String {
        return "beaconkey_\(self.major.intValue)-\(self.minor.intValue)"
    }
    func isEqualToCLBeacon(_ beacon: CLBeacon?) -> Bool {
        guard let to = beacon else {
            return false
        }
        
        if self.major.isEqual(to: to.major) && self.minor.isEqual(to: to.minor) {
            return true
        }
        return false
    }
}

//MARK: BeaconTrackerDelegate
@objc protocol BeaconTrackerDelegate: NSObjectProtocol {
    func beaconTracker(_ beaconTracker: BeaconTracker, updateBeacons beacons: [CLBeacon])
    func beaconTrackerNeedToTurnOnBluetooth(_ beaconTracker: BeaconTracker)
}

//MARK: BeaconTracker
class BeaconTracker: NSObject, CLLocationManagerDelegate, CBCentralManagerDelegate {

    //MARK: Singleton Share Beacon Tracker
    static let shared = BeaconTracker()
    
    //MARK: Properties
    private var detectedBeacons: [CLBeacon] = []
    private var blackBeacons: [CLBeacon] = []
    private var nearestBeacon: CLBeacon? = nil
    private var checkTimer: Timer? = nil
    
    private var locationManager: CLLocationManager? = nil
    private var centralManager: CBCentralManager? = nil
    private var beaconRegions: [CLBeaconRegion] = []
    
    var isForegroundMode: Bool {
        return UIApplication.shared.applicationState == .active
    }
    
    //MARK: Delegate
    var delegate: BeaconTrackerDelegate? = nil
    
    //MARK: Initialization
    override init() {
        super.init()
        // register method that be called when the app receive UIApplicationDidEnterBackgroundNotification
        NotificationCenter.default.addObserver(self, selector: #selector(BeaconTracker.applicationEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        beaconRegions.append(CLBeaconRegion(proximityUUID: UUID(uuidString: I6_UUID)!, identifier: I6_UUID))
        beaconRegions.append(CLBeaconRegion(proximityUUID: UUID(uuidString: ESTIMOTE_UUID)!, identifier: ESTIMOTE_UUID))
    }
    
    //MARK: Start & Stop
    func startBeaconTracking() {
        self.locationManager = CLLocationManager()
        
        self.centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
        
        // request permission to get location for iOS 8 +
        if self.locationManager!.responds(to: #selector(CLLocationManager.requestAlwaysAuthorization)) {
            self.locationManager?.requestAlwaysAuthorization()
        }
        
        self.locationManager?.delegate = self
        self.locationManager?.pausesLocationUpdatesAutomatically = false

        for region in beaconRegions {
            self.locationManager?.startMonitoring(for: region)
        }
        
        self.locationManager?.startUpdatingLocation()
        self.startBeaconRanging()
    }
    
    func stopBeaconTracking() {
        self.stopBeaconRanging()
        
        for region in beaconRegions {
            self.locationManager?.stopMonitoring(for: region)
        }
        
        self.locationManager = nil
        self.centralManager = nil
    }
    
    //MARK: Ranging
    private func startBeaconRanging() {
        self.nearestBeacon = nil
        
        for region in beaconRegions {
            self.locationManager?.startRangingBeacons(in: region)
        }
        
        self.locationManager?.startUpdatingLocation()
        
        self.checkTimer?.invalidate()
        self.checkTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(BeaconTracker.checkNewBeacons), userInfo: nil, repeats: true)
    }
    
    private func stopBeaconRanging() {
        for region in beaconRegions {
            self.locationManager?.stopRangingBeacons(in: region)
        }
        
        locationManager?.stopUpdatingLocation()
        
        BackgroundTaskManager.shared.endAllBackgroundTasks()
        
        self.checkTimer?.invalidate()
        self.checkTimer = nil
        
        self.nearestBeacon = nil
    }
    
    //MARK: Timer Callback
    @objc private func checkNewBeacons() {
        
//        Log.d("didCheckBeacons")
        let rssiSorted = self.detectedBeacons.sorted { (first, second) -> Bool in
            return first.rssi > second.rssi
        }
        self.delegate?.beaconTracker(self, updateBeacons: rssiSorted)

        if self.isForegroundMode == false {
            let _ = BackgroundTaskManager.shared.beginNewBackgroundTask()
        }
        
        self.detectedBeacons = []
    }
    
    //MARK: CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            Log.d("Location Authorized Always")
        case .authorizedWhenInUse:
            Log.d("Location Authorized When In Use")
        case .denied:
            Log.d("Location Denied")
        case .restricted:
            Log.d("Location Restricted")
        case .notDetermined:
            Log.d("Location Not Determined")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Log.d("Entered Region: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Log.d("Exited Region: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
//        Log.e("didRangeBeacons: \(region.identifier)")
        if beacons.count <= 0 {
            return
        }
            
        let originals = self.detectedBeacons
        self.detectedBeacons = []
        self.detectedBeacons.append(contentsOf: beacons)
        for beacon in originals {
            if beacon.proximityUUID.uuidString != beacons[0].proximityUUID.uuidString {
                self.detectedBeacons.append(beacon)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, rangingBeaconsDidFailFor region: CLBeaconRegion, withError error: Error) {
        Log.d("Beacon raging failed with error: \(region.identifier): \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        switch state {
        case .inside:
            Log.d("Region Inside State: \(region.identifier)")
        case .outside:
            Log.d("Region Outside State: \(region.identifier)")
        case .unknown:
            Log.d("Region Unknown State: \(region.identifier)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Log.e("Region monitoring failed with error: \(error)")
    }
    
    //MARK: CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            self.delegate?.beaconTrackerNeedToTurnOnBluetooth(self)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("\(peripheral.name)-\(advertisementData)")
    }

    //MARK: Application Observers
    @objc private func applicationEnterBackground() {
        let _ = BackgroundTaskManager.shared.beginNewBackgroundTask()
    }
}

//MARK: BackgroundTaskManager
class BackgroundTaskManager: NSObject {
    
    static let shared = BackgroundTaskManager()
    
    var bgTaskIdList: [UIBackgroundTaskIdentifier] = []
    var masterTaskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
    
    func beginNewBackgroundTask() -> UIBackgroundTaskIdentifier {
        
        let application = UIApplication.shared
        var bgTaskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
        
        if application.responds(to: #selector(UIApplication.beginBackgroundTask(withName:expirationHandler:))) {
            bgTaskId = application.beginBackgroundTask(expirationHandler: {
                [weak self] in
                Log.d("background task \(bgTaskId) expired")
                guard let index = self?.bgTaskIdList.index(of: bgTaskId) else {
                    Log.e("Invaild Task \(bgTaskId)")
                    return
                }
                application.endBackgroundTask(bgTaskId)
                self?.bgTaskIdList.remove(at: index)
            })
            
            if self.masterTaskId == UIBackgroundTaskIdentifier.invalid {
                self.masterTaskId = bgTaskId
                Log.d("start master task \(bgTaskId)")
            }
            else {
                Log.d("started background task \(bgTaskId)")
                self.bgTaskIdList.append(bgTaskId)
                self.endBackgroundTasks()
            }
        }
        return bgTaskId
    }
    
    func endBackgroundTasks() {
        self.drainBGTaskList(all: false)
    }
    
    func endAllBackgroundTasks() {
        self.drainBGTaskList(all: true)
    }
    
    func drainBGTaskList(all: Bool) {
        let application = UIApplication.shared
        if application.responds(to: #selector(UIApplication.endBackgroundTask(_:))) {
            let count = self.bgTaskIdList.count
            for _ in (all ? 0 : 1) ..< count {
                let bgTaskId = self.bgTaskIdList[0]
                Log.d("ending background task with id\(bgTaskId)")
                application.endBackgroundTask(bgTaskId)
                self.bgTaskIdList.remove(at: 0)
            }
            
            if self.bgTaskIdList.count > 0 {
                Log.d("kept background task id \(self.bgTaskIdList[0])")
            }
            
            if all {
                Log.d("no more background tasks running")
                application.endBackgroundTask(self.masterTaskId)
                self.masterTaskId = UIBackgroundTaskIdentifier.invalid
            }
            else {
                Log.d("kept master background task id \(self.masterTaskId)")
            }
        }
    }
}

