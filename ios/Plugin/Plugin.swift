import Foundation
import Capacitor
import AVFoundation
/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
@objc(CameraPreview)
public class CameraPreview: CAPPlugin {

    var previewView: UIView!
    var cameraPosition = String()
    var aspectRatio = String()
    let cameraController = CameraController()
    var x: CGFloat?
    var y: CGFloat?
    var width: CGFloat?
    var height: CGFloat?
    var paddingBottom: CGFloat?
    var rotateWhenOrientationChanged: Bool?
    var toBack: Bool?
    var storeToFile: Bool?
    var enableZoom: Bool?
    var highResolutionOutput: Bool = false
    var disableAudio: Bool = false
    var isPreparingCamera: Bool = false

    @objc func rotated() {
        let height = self.paddingBottom != nil ? self.height! - self.paddingBottom!: self.height!;

        if UIApplication.shared.statusBarOrientation.isLandscape {
            self.previewView.frame = CGRect(x: self.y!, y: self.x!, width: max(height, self.width!), height: min(height, self.width!))
            self.cameraController.previewLayer?.frame = self.previewView.frame
        }

        if UIApplication.shared.statusBarOrientation.isPortrait {
            if (self.previewView != nil && self.x != nil && self.y != nil && self.width != nil && self.height != nil) {
                self.previewView.frame = CGRect(x: self.x!, y: self.y!, width: min(height, self.width!), height: max(height, self.width!))
            }
            self.cameraController.previewLayer?.frame = self.previewView.frame
        }

        cameraController.updateVideoOrientation()
    }
    
    @objc func getAspectRatio(_ call: CAPPluginCall) {
        call.resolve([
            "aspectRatio": self.aspectRatio
        ])
        return
    }

    @objc func start(_ call: CAPPluginCall) {
	    // If we're already preparing, reject
	    guard !isPreparingCamera else {
		call.reject("camera preparation in progress")
		return
	    }
	    
	    self.isPreparingCamera = true
	    
	    // Configure camera settings from call
	    self.cameraPosition = call.getString("position") ?? "rear"
	    self.aspectRatio = call.getString("aspectRatio") ?? "4:3"
	    self.highResolutionOutput = call.getBool("enableHighResolution") ?? false
	    self.cameraController.highResolutionOutput = self.highResolutionOutput
	    
	    if call.getInt("width") != nil {
		self.width = CGFloat(call.getInt("width")!)
	    } else {
		self.width = UIScreen.main.bounds.size.width
	    }
	    
	    if call.getInt("height") != nil {
		self.height = CGFloat(call.getInt("height")!)
	    } else {
		self.height = UIScreen.main.bounds.size.height
	    }
	    
	    self.x = call.getInt("x") != nil ? CGFloat(call.getInt("x")!)/UIScreen.main.scale : 0
	    self.y = call.getInt("y") != nil ? CGFloat(call.getInt("y")!)/UIScreen.main.scale : 0
	    
	    if call.getInt("paddingBottom") != nil {
		self.paddingBottom = CGFloat(call.getInt("paddingBottom")!)
	    }
	    
	    self.rotateWhenOrientationChanged = call.getBool("rotateWhenOrientationChanged") ?? true
	    self.toBack = call.getBool("toBack") ?? false
	    self.storeToFile = call.getBool("storeToFile") ?? false
	    self.enableZoom = call.getBool("enableZoom") ?? false
	    self.disableAudio = call.getBool("disableAudio") ?? false
	    
	    AVCaptureDevice.requestAccess(for: .video, completionHandler: { [weak self] (granted: Bool) in
		guard let self = self else {
		    call.reject("plugin deallocated during permission request")
		    return
		}
		
		guard granted else {
		    self.isPreparingCamera = false
		    call.reject("permission failed")
		    return
		}
		
		DispatchQueue.main.async { [weak self] in
		    guard let self = self else {
			call.reject("plugin deallocated")
			return
		    }
		    
		    if self.cameraController.captureSession?.isRunning ?? false {
			self.isPreparingCamera = false
			call.reject("camera already started")
			return
		    }
		    
		    self.cameraController.prepare(
			aspectRatio: self.aspectRatio,
			cameraPosition: self.cameraPosition,
			disableAudio: self.disableAudio
		    ) { [weak self] error in
			guard let self = self else {
			    call.reject("plugin deallocated during preparation")
			    return
			}
			
			defer {
			    self.isPreparingCamera = false
			}
			
			if let error = error {
			    print(error)
			    call.reject(error.localizedDescription)
			    return
			}
			
			// Verify we still have a valid webView before proceeding
			guard let webView = self.webView else {
			    call.reject("webView no longer available")
			    return
			}
			
			do {
			    let height = self.paddingBottom != nil ? self.height! - self.paddingBottom! : self.height!
			    self.previewView = UIView(frame: CGRect(x: self.x ?? 0, y: self.y ?? 0, width: self.width!, height: height))
			    
			    webView.isOpaque = false
			    webView.backgroundColor = UIColor.clear
			    webView.scrollView.backgroundColor = UIColor.clear
			    webView.superview?.addSubview(self.previewView!)
			    
			    if self.toBack! {
				webView.superview?.bringSubviewToFront(webView)
			    }
			    
			    try self.cameraController.displayPreview(on: self.previewView!)
			    
			    if self.rotateWhenOrientationChanged == true {
				NotificationCenter.default.addObserver(
				    self,
				    selector: #selector(CameraPreview.rotated),
				    name: UIDevice.orientationDidChangeNotification,
				    object: nil
				)
			    }
			    
			    call.resolve()
			} catch {
			    print("Error setting up preview: \(error)")
			    call.reject(error.localizedDescription)
			}
		    }
		}
	    })
	}

    @objc func flip(_ call: CAPPluginCall) {
        do {
            try self.cameraController.switchCameras()
            call.resolve()
        } catch {
            call.reject("failed to flip camera")
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                call.resolve() // Already cleaned up
                return
            }
            
            // If we're still preparing, wait a bit and try again
            if self.isPreparingCamera {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.stop(call)
                }
                return
            }
            
            // Safe cleanup of session
            if let session = self.cameraController.captureSession {
                if session.isRunning {
                    session.stopRunning()
                }
            }
            
            // Safe cleanup of preview
            if let previewView = self.previewView {
                previewView.removeFromSuperview()
                self.previewView = nil
            }
            
            // Reset webView properties
            self.webView?.isOpaque = true
            
            // Remove orientation observer if it was added
            if self.rotateWhenOrientationChanged == true {
                NotificationCenter.default.removeObserver(
                    self,
                    name: UIDevice.orientationDidChangeNotification,
                    object: nil
                )
            }
            
            call.resolve()
        }
    }
    // Get user's cache directory path
    @objc func getTempFilePath() -> URL {
        let path = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let identifier = UUID()
        let randomIdentifier = identifier.uuidString.replacingOccurrences(of: "-", with: "")
        let finalIdentifier = String(randomIdentifier.prefix(8))
        let fileName="cpcp_capture_"+finalIdentifier+".HEIC"
        let fileUrl=path.appendingPathComponent(fileName)
        return fileUrl
    }
    
    @objc func tapToFocus(_ call: CAPPluginCall){
        guard let x = call.getInt("x") else{
            call.reject("failed to set focuspoint, x is missing")
            return
        }
        
        guard let y = call.getInt("y") else{
            call.reject("failed to set focuspoint, x is missing")
            return
        }
        do {
            try self.cameraController.tapToFocus(x: x, y: y)
            call.resolve()
        } catch {
            call.reject("failed to set focus")
        }
    }
    
    @objc func switchAspectRatio(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let aspectRatioString = call.getString("aspectRatio", "4:3")
                    
            // Store current preview view properties
            let currentFrame = self.previewView.frame
            
            // Remove current preview
            self.previewView.removeFromSuperview()
            self.webView?.isOpaque = true
            self.aspectRatio = aspectRatioString
            
            self.cameraController.switchAspectRatio(aspectRatio: aspectRatioString) { error in
                if let error = error {
                    call.reject("Failed to switch aspect ratio: \(error.localizedDescription)")
                    return
                }
                
                // Recreate preview view with same frame
                self.previewView = UIView(frame: currentFrame)
                
                // Setup preview view
                self.webView?.isOpaque = false
                self.webView?.backgroundColor = UIColor.clear
                self.webView?.scrollView.backgroundColor = UIColor.clear
                self.webView?.superview?.addSubview(self.previewView)
                
                if self.toBack! {
                    self.webView?.superview?.bringSubviewToFront(self.webView!)
                }
                
                // Display new preview
                do {
                    try self.cameraController.displayPreview(on: self.previewView)
                    
                    // Setup gestures again
                    let frontView = self.toBack! ? self.webView : self.previewView
                    // self.cameraController.setupGestures(target: frontView ?? self.previewView, enableZoom: self.enableZoom!)
                    
                    call.resolve([
                        "aspectRatio": aspectRatioString
                    ])
                } catch {
                    call.reject("Failed to display preview after switching aspect ratio")
                }
            }
        }
    }

    @objc func capture(_ call: CAPPluginCall) {
        DispatchQueue.main.async {

            let quality: Int? = call.getInt("quality", 100)
            
            self.cameraController.captureImage() { (image, error) in
                guard let image = image else {
                    print(error ?? "Image capture error")
                    guard let error = error else {
                        call.reject("Image capture error")
                        return
                    }
                    call.reject(error.localizedDescription)
                    return
                }
                
                let processedImage: UIImage
                if self.cameraController.currentCameraPosition == .front {
                    processedImage = image.withHorizontallyFlippedOrientation()
                } else {
                    processedImage = image
                }
                
                // Try to get HEIF data first, fall back to JPEG if needed
                let imageData: Data?
                let mimeType: String
                if #available(iOS 17.0, *) {
                    print("YOLO ÇA CAPTURE EN HEIC")
                    // HEIF available and conversion successful
                    imageData = processedImage.heicData()
                    mimeType = "image/heic"
                } else {
                    // Fallback on earlier versions
                    imageData = processedImage.jpegData(compressionQuality: CGFloat(quality!/100))
                    mimeType = "image/jpeg"
                }
                
                print("YOLO ÇA CAPTURE")
                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve([
                        "value": imageBase64!,
                        "format": mimeType
                    ])
                } else {
                    do {
                        let fileUrl = self.getTempFilePath()
                        try imageData?.write(to: fileUrl)
                        call.resolve([
                            "value": fileUrl.absoluteString,
                            "format": mimeType
                        ])
                    } catch {
                        call.reject("error writing image to file")
                    }
                }
            }
        }
    }

    @objc func captureSample(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let quality: Int? = call.getInt("quality", 85)

            self.cameraController.captureSample { image, error in
                guard let image = image else {
                    print("Image capture error: \(String(describing: error))")
                    call.reject("Image capture error: \(String(describing: error))")
                    return
                }

                let imageData: Data?
                if self.cameraPosition == "front" {
                    let flippedImage = image.withHorizontallyFlippedOrientation()
                    imageData = flippedImage.jpegData(compressionQuality: CGFloat(quality!/100))
                } else {
                    imageData = image.jpegData(compressionQuality: CGFloat(quality!/100))
                }

                if self.storeToFile == false {
                    let imageBase64 = imageData?.base64EncodedString()
                    call.resolve(["value": imageBase64!])
                } else {
                    do {
                        let fileUrl = self.getTempFilePath()
                        try imageData?.write(to: fileUrl)
                        call.resolve(["value": fileUrl.absoluteString])
                    } catch {
                        call.reject("Error writing image to file")
                    }
                }
            }
        }
    }

    @objc func getSupportedFlashModes(_ call: CAPPluginCall) {
        do {
            let supportedFlashModes = try self.cameraController.getSupportedFlashModes()
            call.resolve(["result": supportedFlashModes])
        } catch {
            call.reject("failed to get supported flash modes")
        }
    }

    @objc func setFlashMode(_ call: CAPPluginCall) {
        guard let flashMode = call.getString("flashMode") else {
            call.reject("failed to set flash mode. required parameter flashMode is missing")
            return
        }
        do {
            var flashModeAsEnum: AVCaptureDevice.FlashMode?
            switch flashMode {
            case "off" :
                flashModeAsEnum = AVCaptureDevice.FlashMode.off
            case "on":
                flashModeAsEnum = AVCaptureDevice.FlashMode.on
            case "auto":
                flashModeAsEnum = AVCaptureDevice.FlashMode.auto
            default: break
            }
            if flashModeAsEnum != nil {
                try self.cameraController.setFlashMode(flashMode: flashModeAsEnum!)
            } else if flashMode == "torch" {
                try self.cameraController.setTorchMode()
            } else {
                call.reject("Flash Mode not supported")
                return
            }
            call.resolve()
        } catch {
            call.reject("failed to set flash mode")
        }
    }

    @objc func startRecordVideo(_ call: CAPPluginCall) {
        DispatchQueue.main.async {

            let quality: Int? = call.getInt("quality", 85)

            self.cameraController.captureVideo { (image, error) in

                guard let image = image else {
                    print(error ?? "Image capture error")
                    guard let error = error else {
                        call.reject("Image capture error")
                        return
                    }
                    call.reject(error.localizedDescription)
                    return
                }

                // self.videoUrl = image

                call.resolve(["value": image.absoluteString])
            }
        }
    }

    @objc func stopRecordVideo(_ call: CAPPluginCall) {

        self.cameraController.stopRecording { (_) in

        }
    }
    
    @objc func getDeviceOrientation(_ call: CAPPluginCall) {
        do {
            let orientation = try self.cameraController.getDeviceOrientation()
            call.resolve([
                "value": orientation
            ])
        } catch {
            call.reject("failed to set zoom level")
        }
    }

    @objc func setZoomLevel(_ call: CAPPluginCall) {
        guard let zoomLevel = call.getFloat("zoomLevel") else {
            call.reject("failed to set zoom level. required parameter zoomLevel is missing")
            return
        }
        do {
            try self.cameraController.setZoomLevel(zoomLevel: zoomLevel)
            call.resolve()
        } catch {
            call.reject("failed to set zoom level")
        }
    }

}
