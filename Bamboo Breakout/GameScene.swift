import SpriteKit
import CoreMotion
import CoreLocation
import CoreMedia
import Foundation
import AVFoundation

let BallCategoryName = "ball"
let PaddleCategoryName = "paddle"
let BlockCategoryName = "block"
let GameMessageName = "gameMessage"
let REyeName = "eye_r"
let LEyeName = "eye_l"
let brightnessTheshold = -1

extension CLLocationDirection {
    var toRadians: CGFloat { return CGFloat(self * .pi / 180) }
}

class GameScene: SKScene, AVCaptureVideoDataOutputSampleBufferDelegate {
  var lastTouchPosition: CGPoint?
  var ball: SKSpriteNode?
  var motionManager: CMMotionManager! = CMMotionManager()
  var locationManager: CLLocationManager = {
        $0.requestWhenInUseAuthorization()
        $0.startUpdatingHeading()
        $0.startUpdatingLocation()
        return $0
  }(CLLocationManager())
  var l_eye: SKSpriteNode?
  var r_eye: SKSpriteNode?
  var captureSession: AVCaptureSession = AVCaptureSession()
  var hasAccess: Bool = false
  var buffer: CMSampleBuffer?
  var brightness = 0.0
  var timer: Timer?
  var blinkTimer: Timer?
  var blinkReseter: Timer?
  
    
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
     if let touch = touches.first {
       let location = touch.location(in: self)
       lastTouchPosition = location
     }
   }
    
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    if let touch = touches.first {
      let location = touch.location(in: self)
      lastTouchPosition = location
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    lastTouchPosition = nil
  }
    
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    lastTouchPosition = nil
  }
    
  override func didMove(to view: SKView) {
    super.didMove(to: view)
    
    let borderBody = SKPhysicsBody(edgeLoopFrom: self.frame)
    borderBody.friction = 0
    self.physicsBody = borderBody
    
    motionManager.startAccelerometerUpdates()
    ball = childNode(withName: BallCategoryName) as? SKSpriteNode
    
    r_eye = ball?.childNode(withName: REyeName) as? SKSpriteNode
    l_eye = ball?.childNode(withName: LEyeName) as? SKSpriteNode
    
    AVCaptureDevice.requestAccess(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video))) {
        (granted: Bool) -> Void in
        guard granted else {
            /// Report an error. We didn't get access to hardware.
            return
        }
        self.hasAccess = true
    }
    
    guard let inputDevice = device(mediaType: convertFromAVMediaType(AVMediaType.video), position: .front) else {
        /// Handle an error. We couldn't get hold of the requested hardware.
        return
    }
    
    var captureInput: AVCaptureDeviceInput!
    
    do {
        captureInput = try AVCaptureDeviceInput(device: inputDevice)
    }
    catch {
        /// Handle an error. Input device is not available.
    }
    
    captureSession.beginConfiguration()
    captureSession.addInput(captureInput)
    
    let outputData = AVCaptureVideoDataOutput()
    
    outputData.videoSettings = [:]
    
    let captureSessionQueue = DispatchQueue(label: "CameraSessionQueue", attributes: [])
    outputData.setSampleBufferDelegate(self as AVCaptureVideoDataOutputSampleBufferDelegate, queue: captureSessionQueue)
    
    guard captureSession.canAddOutput(outputData) else {
        /// Handle an error. We failed to add an output device.
        assert(false, "can't add output to capture session")
    }
    
    captureSession.addOutput(outputData)
    captureSession.commitConfiguration()
    captureSession.startRunning()
    
    timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(self.updateLight), userInfo: nil, repeats: true)
  }
    
  @objc func updateLight() {
    if brightness < -1 {
        if (Int(r_eye?.zPosition ?? 1) > 0 && self.blinkTimer == nil) {
            r_eye?.zPosition = CGFloat(-1)
            l_eye?.zPosition = CGFloat(-1)
        }
    } else {
        if (Int(r_eye?.zPosition ?? 1) < 0 && self.blinkTimer == nil) {
            r_eye?.zPosition = CGFloat(3)
            l_eye?.zPosition = CGFloat(3)
            self.initBlinking()
        }
    }
  }
    
    @objc func resetBlink() {
        self.r_eye?.zPosition = CGFloat(3)
        self.l_eye?.zPosition = CGFloat(3)
        if self.blinkTimer != nil {
            self.blinkTimer?.invalidate()
            self.blinkTimer = nil
        }
        self.blinkReseter = nil
    }

  func initBlinking() {
    blinkTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.blink), userInfo: nil, repeats: true)
    blinkReseter = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(self.resetBlink), userInfo: nil, repeats: false)
  }
    
  @objc func blink() {
    if (Int(r_eye?.zPosition ?? 1) > 0) {
        r_eye?.zPosition = CGFloat(-1)
        l_eye?.zPosition = CGFloat(-1)
    } else {
        r_eye?.zPosition = CGFloat(3)
        l_eye?.zPosition = CGFloat(3)
    }
  }

  override func update(_ currentTime: TimeInterval) {
    #if targetEnvironment(simulator)
    if let currentTouch = lastTouchPosition {
        if let b = ball {
            let diff = CGPoint(x: currentTouch.x - b.position.x, y: currentTouch.y - b.position.y)
            physicsWorld.gravity = CGVector(dx: diff.x / 100, dy: diff.y / 100)
        }
    }
    #else
    if let accelerometerData = motionManager.accelerometerData {
        physicsWorld.gravity = CGVector(dx: accelerometerData.acceleration.x * 10, dy: accelerometerData.acceleration.y * 10)
    }
    if let heading = locationManager.heading {
        let radians = heading.trueHeading.toRadians
        r_eye?.zRotation = radians
        l_eye?.zRotation = radians
    }
    
    #endif
  }
    
  func getBrightness(sampleBuffer: CMSampleBuffer) -> Double {
    let rawMetadata = CMCopyDictionaryOfAttachments(allocator: nil, target: sampleBuffer, attachmentMode: CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))
    let metadata = CFDictionaryCreateMutableCopy(nil, 0, rawMetadata) as NSMutableDictionary
    let exifData = metadata.value(forKey: "{Exif}") as? NSMutableDictionary
    let brightnessValue : Double = exifData?[kCGImagePropertyExifBrightnessValue as String] as! Double
    
    return brightnessValue
  }

  func device(mediaType: String, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    guard let devices = AVCaptureDevice.devices(for: AVMediaType(rawValue: mediaType)) as? [AVCaptureDevice] else { return nil }
        
    if let index = devices.index(where: { $0.position == position }) {
      return devices[index]
    }
        
    return nil
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      self.brightness = getBrightness(sampleBuffer: sampleBuffer)
  }
    
  func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
      print("sampleBuffer drop")
  }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVMediaType(_ input: AVMediaType) -> String {
	return input.rawValue
}
