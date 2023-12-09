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

class InterfaceController: WKInterfaceController {
    var workoutSession: HKWorkoutSession?
    let motionManager = CMMotionManager()
    let classifier = YubisashiMotionClassifier()
    var writer: ResultWriter?

    var yubisashi = false
    var lastYubisashi = Date()
    var yubisashiTimer: Timer?
    
    var outputTimer: Timer?

    func startTimer() {
        outputTimer = Timer.scheduledTimer(timeInterval: 100, target: self, selector: #selector(outputTimerAction), userInfo: nil, repeats: true)
    }

    @objc func outputTimerAction() {
        DispatchQueue.main.async {
            self.stopResultWriter()
        }
        DispatchQueue.main.async {
            self.startResultWriter()
        }
        
    }

    @IBOutlet weak var labelProbability: WKInterfaceLabel!
    @IBOutlet weak var label: WKInterfaceTextField!
    @IBOutlet weak var button: WKInterfaceButton!
    @IBOutlet weak var imageView: WKInterfaceImage!
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
            self.startResultWriter()
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
        print("===== print results =====")
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let outputTime = formatter.string(from: Date())
        
        print(results)
        if results[0].0 == "neutral" || results[0].1 < 0.6 {
            print("low confidence or no scratch \n")
            DispatchQueue.main.async {
                self.writeResult(outputTime, "neutral")
            }
            return
        }
        
        print("Itch!!!!!!!!!!")
        DispatchQueue.main.async {
            self.writeResult(outputTime, results[0].0)
        }
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
            self.labelProbability.setText(results[0].0 + String(format: "%.2f", results[0].1))
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
