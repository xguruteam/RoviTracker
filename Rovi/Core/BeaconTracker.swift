//
//  BeaconTracker.swift
//  Rovi
//
//  Created by Luccas Beck on 3/1/18.
//  Copyright © 2019 RoviTracker. All rights reserved.
//

import Foundation
import CoreLocation
import CoreBluetooth
import UIKit
import os.log
import CoreData

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

let DEVICE_ID = "NX993NSDF8"

//MARK: CLBeacon Extension
extension CLBeacon {
    var keyString: String {
        return "beaconkey_\(self.major.intValue)-\(self.minor.intValue)"
    }
    
    var idString: String {
        return "\(self.major.intValue)-\(self.minor.intValue)"
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
@available(iOS 10.0, *)
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
    
    
    var dataController: DataController!
    var backgroundSessionCompletionHandler: (() -> Void)?
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "roviBackgroundSession")
        // wakes up the app when a task completes
        // config.sessionSendsLaunchEvents = true
        // the system waits for optimal conditions to send data - saves battery and cell data
        // config.isDiscretionary = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    
    //MARK: Initialization
    override init() {
        super.init()
        // register method that be called when the app receive UIApplicationDidEnterBackgroundNotification
        NotificationCenter.default.addObserver(self, selector: #selector(BeaconTracker.applicationEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        beaconRegions.append(CLBeaconRegion(proximityUUID: UUID(uuidString: I6_UUID)!, identifier: I6_UUID))
        beaconRegions.append(CLBeaconRegion(proximityUUID: UUID(uuidString: ESTIMOTE_UUID)!, identifier: ESTIMOTE_UUID))
        
        dataController = DataController()
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
        // this is the default accuracy
        // TODO: use kCLLocationAccuracyBestForNavigation when app is open - best accuracy
        self.locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager?.headingOrientation = .portrait
        // TODO: move to settings on Flutter side
        self.locationManager?.headingFilter = 30
        // setsup background location for iOS 9 and above - should wake up app if suspended
        self.locationManager?.allowsBackgroundLocationUpdates = true
        // this is the default activity type
        self.locationManager?.activityType = CLActivityType.other
        // turns off for continuous location updates after app is suspended
        self.locationManager?.pausesLocationUpdatesAutomatically = false
        changeDistanceFilter(distance: 5.0)

        for region in beaconRegions {
            self.locationManager?.startMonitoring(for: region)
        }
        
        self.locationManager?.startUpdatingLocation()
        self.locationManager?.startUpdatingHeading()
        self.startBeaconRanging()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleBatteryLevelChange(notification:)),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.handleBatteryStateChange(notification:)),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }
    
    
    func stopBeaconTracking() {
        self.stopBeaconRanging()
        
        for region in beaconRegions {
            self.locationManager?.stopMonitoring(for: region)
        }
        
        self.locationManager?.stopUpdatingLocation()
        self.locationManager?.stopUpdatingLocation()
        self.locationManager = nil
        self.centralManager = nil
        
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name:  UIDevice.batteryStateDidChangeNotification, object: nil)
    }
    
    public func changeDistanceFilter(distance: Double) {
        self.locationManager?.distanceFilter = distance
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
        
        let beaconReadingsList = rssiSorted.map(beaconToReading)
        beaconReadingsList.forEach(dataController.addReading)

        handleUploadReadings()
    }
    
    private func beaconToReading(beacon: CLBeacon) -> Reading {

        let deviceId = beacon.idString
        let temperature = 0
        let signal_strength = Int(Utils.meter(fromRSSI: Double(beacon.rssi)))
        
        let metrics = Metrics(
            temperature: temperature,
            signal_strength: signal_strength
        )
        
        return Reading(
            deviceId: deviceId,
            metrics: metrics,
            timestamp: Date()
        )
    }
    
    // handles uploading readings to rovitracker
    private func sendReadings(token: String, readings: [Reading]) {
        // NSLog("Sending Readings: \(readings.count)")
        // TODO: remove hardcode
        if let urlComponents = URLComponents(string: "https://admin.rovitracker.com/device-api/v1/devices/R-IOS-DJVMBLY3/events") {
            guard let url = urlComponents.url else { return }
            
            let events = readings.map { reading in DeviceEvent(reading: reading) }
            guard let uploadData = try? JSONEncoder().encode(events) else {
                return
            }
            
            // temporarily saves to file - see if can do directly with dataController
            let tempDir = FileManager.default.temporaryDirectory
            let localURL = tempDir.appendingPathComponent("throwaway")
            try? uploadData.write(to: localURL)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let task = backgroundSession.uploadTask(with: request, fromFile: localURL)
            task.resume()
        }
    }
    
    func handleUploadReadings() {
        // if there are more that 20 readings, upload data to rovitracker
        let fetchedReadings = dataController.fetchReadings()
        
        let firstReading = fetchedReadings.first
        let firstUpdateTimeInterval = firstReading?.timestamp.timeIntervalSinceNow ?? 0
        let throttleSeconds = -10.0
        let minIntervalSeconds = -300.0
        let throttleCount = 10
        // sends data if there area at least 10 events and at least 10 seconds has passed OR if at least 5 minutes have passed
        let shouldSend = (fetchedReadings.count > throttleCount && firstUpdateTimeInterval < throttleSeconds) ||
            (firstUpdateTimeInterval < minIntervalSeconds)
        
        // NSLog("handleUploadReadings: \(shouldSend), reading count: \(fetchedReadings.count), time interval: \(firstUpdateTimeInterval)")
        
        if (shouldSend) {
            NSLog("uploading: \(fetchedReadings.count)")
            // finds token saved to local storage
//            let defaults = UserDefaults.standard
//            if let token = (defaults.object(forKey: "credentials") as! Dictionary<String, String>?)?["token"] {
                self.sendReadings(token: "token", readings: fetchedReadings)
                dataController.clearData()
//            } else {
//                NSLog("token not found")
//            }
        }
        
        handleUpdateUIReadings(fetchedReadings)
    }
    
    func handleUpdateUIReadings(_ fetchedReadings: [Reading]) {
        let state = UIApplication.shared.applicationState
        // if app is not backgrounded, send latest reading to flutter side
        if state != .background {
//            self.receivedNewReadings!(fetchedReadings)
        }
    }
    
    @objc func handleBatteryLevelChange(notification: Notification) {
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryPercent = Int(batteryLevel * 100)
        let metrics = Metrics(
            batteryLevel: batteryPercent
        )
        let reading = Reading(
            deviceId: DEVICE_ID,
            metrics: metrics,
            timestamp: Date()
        )
        
        dataController.addReading(reading)
        
        handleUploadReadings()
    }
    
    @objc func handleBatteryStateChange(notification: Notification) {
        let charging = batteryStatusToBool(status: UIDevice.current.batteryState)
        let metrics = Metrics(
            charging: charging
        )
        let reading = Reading(
            deviceId: DEVICE_ID,
            metrics: metrics,
            timestamp: Date()
        )
        
        dataController.addReading(reading)
        
        handleUploadReadings()
    }
    
    // Coverts to accepted backend batteryState as defined in roviDefinitions
    func batteryStatusToBool(status: UIDevice.BatteryState) -> Bool? {
        switch status {
        case .charging, .full:
            return true
        case .unplugged:
            return false
        default:
            return nil
        }
    }
    
    
    private func locationToReading(location: CLLocation) -> Reading {
        let gps = GpsCoord(
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
        let speed = Int(location.speed * 100) // meters per sec to cm per sec
        let altitude = Int(location.altitude * 100) // converts Double in meters to Int in cm
        let heading = Int(location.course)
        
        let metrics = Metrics(
            gps: gps,
            heading: heading,
            speed: speed,
            altitude: altitude
        )
        
        return Reading(
            deviceId: DEVICE_ID,
            metrics: metrics,
            timestamp: location.timestamp
        )
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
    
    // handles location updates
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        // processes incoming list of location updates and sends to dataController to be stored
        let locationReadingsList = locations.map(locationToReading)
        locationReadingsList.forEach(dataController.addReading)
        
        handleUploadReadings()
    }
    
    // handles heading updates
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // only sends heading when app is active
        // TODO: should stop heading updates when app is backgrounded and resume when become active
        if UIApplication.shared.applicationState == .active {
            let metrics = Metrics(
                heading: Int(newHeading.trueHeading)
            )
            let reading = Reading(
                deviceId: DEVICE_ID,
                metrics: metrics,
                timestamp: newHeading.timestamp
            )
            dataController.addReading(reading)
            
            handleUploadReadings()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("Location Error \(error)")
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

// Have to use Delegate since completionHandlers can't run in background
@available(iOS 10.0, *)
extension BeaconTracker: URLSessionDelegate, URLSessionTaskDelegate {
    // Tells the delegate that all messages enqueued for a session have been delivered.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            // completion handler is passed from AppDelegate - tells system we're done
            guard let completionHandler = self.backgroundSessionCompletionHandler else {
                return
            }
            completionHandler()
        }
    }
    
    // Tells the delegate that the task finished transferring data.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let httpResponse = task.response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode) else {
                NSLog("Server error")
                // reverts the changes made to the data context to before the readings were deleted
                dataController.undo()
                return
        }
        
        NSLog("UrlSession task complete: \(httpResponse.statusCode)")
        
        // saves the persistent data store with the context with the deleted uploaded readings
        dataController.save()
    }
    
    // Tells the URL session that the session has been invalidated.
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        // reverts the changes made to the data context to before the readings were deleted
        dataController.undo()
        if let err = error {
            NSLog("Url Session Error: \(err.localizedDescription)")
        } else {
            NSLog("Url Session Error. Giving up")
        }
    }
}
