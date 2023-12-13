//
//  InterfaceController.swift
//  YubisashiClassifier WatchKit Extension
//
//  Created by yorifuji on 2020/10/07.
//

import WatchKit
import Foundation
import CoreMotion
import HealthKit

struct JudgementResult: Codable {
    var time: String
    var result: String
}

class InterfaceController: WKInterfaceController {
    var workoutSession: HKWorkoutSession?
    let motionManager = CMMotionManager()
    let classifier = YubisashiMotionClassifier()
    
    var yubisashi = false
    var lastYubisashi = Date()
    var yubisashiTimer: Timer?
    var deviceSerialNumber: String?
    
    var judgementResults = [[String: Any]]()
    var writer: ResultWriter?
    var outputTimer: Timer?
    
    // api endpoint
    let baseURLString = "https://tzuhsun.online/api/1.0"
    let uploadString = "/influxdb"
    let serialString = "/watch/serial"

    func startTimer() {
        outputTimer = Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(outputTimerAction), userInfo: nil, repeats: true)
    }

    @objc func outputTimerAction() {
        
        let outputData = ["data": judgementResults, "device": deviceSerialNumber!] as [String : Any]
        judgementResults.removeAll()
        print(outputData)
//        let jsonData = try? JSONSerialization.data(withJSONObject: outputData, options: JSONSerialization.WritingOptions.prettyPrinted)
        
        DispatchQueue.main.async {
            if !outputData.isEmpty {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: outputData, options: JSONSerialization.WritingOptions.prettyPrinted)

                    var request = URLRequest(url: URL(string: self.baseURLString + self.uploadString)!)
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    request.httpMethod = "POST"
                    request.httpBody = jsonData
                    let task = URLSession.shared.dataTask(with: request) { data, response, error in
                        guard let data = data, error == nil else {
                            // check for fundamental networking error
                            print("error=\(String(describing: error))")
                            return
                        }

                        if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {
                            // check for http errors
                            print("statusCode should be 200, but is \(httpStatus.statusCode)")
                            print("response = \(String(describing: response))")
                        }

                        do {
                            if let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                                print(json)
                            }
                        } catch let error {
                            print(error.localizedDescription)
                        }
                    }
                    task.resume()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    @IBOutlet weak var labelProbability: WKInterfaceLabel!
    @IBOutlet weak var label: WKInterfaceTextField!
    @IBOutlet weak var button: WKInterfaceButton!
    @IBOutlet weak var imageView: WKInterfaceImage!
    @IBOutlet weak var number: WKInterfaceButton!
    @IBAction func onTapButton() {
        if self.workoutSession == nil {
            let config = HKWorkoutConfiguration()
            config.activityType = .other
            do {
                let healthStore = HKHealthStore()
                self.workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
                self.workoutSession?.delegate = self
                self.workoutSession?.startActivity(with: nil)
            }
            catch let e {
                print(e)
            }
        }
        else {
            self.workoutSession?.stopActivity(with: nil)
        }
    }

    override func awake(withContext context: Any?) {
        // Configure interface objects here.
        classifier.delegate = self
//        UserDefaults.standard.removeObject(forKey: "DeviceSerialNumber")
        super.awake(withContext: context)
        if let savedSerialNumber = UserDefaults.standard.string(forKey: "DeviceSerialNumber") {
            print("hi")
            deviceSerialNumber = savedSerialNumber
        }  else {
            print("here")
            fetchDeviceSerialNumber()
        }
        self.number.setTitle(deviceSerialNumber)
    }
    
    func fetchDeviceSerialNumber() {
        // get new serial number
        guard let url = URL(string: self.baseURLString + self.serialString) else {
            print("invalid url")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("error=\(String(describing: error))")
                return
            }

            if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {
                print("statusCode should be 200, but is \(httpStatus.statusCode)")
                print("response = \(String(describing: response))")
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])

                if let serialNumberDict = json as? [String: Any], let serialNumber = serialNumberDict["number"] as? String {
                    self.deviceSerialNumber = serialNumber
                    self.number.setTitle(self.deviceSerialNumber)
                    UserDefaults.standard.set(serialNumber, forKey: "DeviceSerialNumber")
                } else {
                    print("Invalid response format")
                }
            } catch let error {
                print(error.localizedDescription)
            }
        }
        task.resume()
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
    }
}

extension InterfaceController: HKWorkoutSessionDelegate {

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        print(#function)
        switch toState {
        case .running:
            print("Session status to running")
            self.startWorkout()
        case .stopped:
            print("Session status to stopped")
            self.stopWorkout()
            self.workoutSession?.end()
        case .ended:
            print("Session status to ended")
            self.workoutSession = nil
        default:
            print("Other status \(toState.rawValue)")
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("workoutSession delegate didFailWithError \(error.localizedDescription)")
    }

    func startWorkout() {
        print(#function)
        DispatchQueue.main.async {
            self.button.setTitle("Stop")
            self.startTimer()
        }
        startDeviceMotionUpdates()
    }

    func stopWorkout() {
        print(#function)
        DispatchQueue.main.async {
            self.button.setTitle("Start")
            self.outputTimer?.invalidate()
            self.outputTimer = nil
        }
        stopDeviceMotionUpdates()
    }
}

extension InterfaceController {
    func startDeviceMotionUpdates() {
        print(#function)
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (motion, error) in
            if let motion = motion {
//                print(motion)
                self.classifier.process(deviceMotion: motion)
            }
        }
    }

    func stopDeviceMotionUpdates() {
        print(#function)
        motionManager.stopDeviceMotionUpdates()
    }
}

extension InterfaceController: YubisashiMotionClassifierDelegate {
    func motionDidDetect(results: [(String, Double)]) {
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let outputTime = formatter.string(from: Date())
        
        let resultDict = ["time": outputTime, "result": results[0].0]
        judgementResults.append(resultDict)
        
//        print(results)
        if results[0].0 == "neutral" || results[0].1 < 0.6 {
            print("low confidence or no scratch \n")
            return
        }
        
        print("Itch!!!!!!!!!!  " + results[0].0)
        if Date().timeIntervalSince(self.lastYubisashi) <= 1.5 {
            print("too much")
            return
        }
        self.lastYubisashi = Date()
        DispatchQueue.main.async {
            print("play")
            WKInterfaceDevice.current().play(.success)
            self.label.setHidden(true)
            self.imageView.setHidden(false)
            self.labelProbability.setHidden(false)
            self.labelProbability.setText(results[0].0 + " " + String(format: "%.2f", results[0].1))
            if self.yubisashiTimer != nil {
                self.yubisashiTimer?.invalidate()
            }
            self.yubisashiTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false, block: { _ in
                print("stop")
                self.yubisashi = false
                self.label.setHidden(false)
                self.imageView.setHidden(true)
                self.labelProbability.setHidden(true)
            })
        }
    }
}

// csv file writer
extension InterfaceController {
    func startResultWriter() {
        print(#function)
        writer = ResultWriter()
        writer?.open(ResultWriter.makeFilePath())
    }
    
    func writeResult(_ time: String, _ result: String) {
        if let writer = self.writer {
            writer.write(time, result)
        }
    }
    
    func stopResultWriter() {
        print(#function)
        if let writer = self.writer {
            writer.close()
            if let filePath = writer.filePath {
                print(filePath)
            }
            self.writer = nil
        }
    }
}
