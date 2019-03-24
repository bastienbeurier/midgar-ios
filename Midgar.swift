import UIKit


// ----------------------------------
// MARK: Window
// ----------------------------------


class MidgarWindow: UIWindow {
    
    fileprivate var screenDetectionTimer: Timer?
    fileprivate var currentScreen = ""
    fileprivate var eventBatch: [Event] = []
    fileprivate var eventUploadTimer: Timer?
    fileprivate let eventUploadService = EventUploadService()
    fileprivate var shutdown = false
    fileprivate var appToken = ""
    fileprivate var detectionFrequency = 0.5 // in seconds
    fileprivate var uploadFrequency = 10.0 // in seconds
    fileprivate var uploadTimerLoopCount = 0
    fileprivate var checkAppEnabledFrequency = 6 // in upload timer loops
    
    func start(appToken: String) {
        guard !shutdown else { return }
        self.appToken = appToken
        checkAppEnabled()
    }
    
    func stop() {
        guard !shutdown else { return }
        stopMonitoring()
    }
    
    private func startMonitoring() {
        guard screenDetectionTimer == nil && eventUploadTimer == nil && !shutdown else { return }
        
        screenDetectionTimer = Timer.scheduledTimer(withTimeInterval: detectionFrequency, repeats: true, block: { (_) in
            let currentScreen = UIApplication.topViewControllerDescription()
            
            if currentScreen != self.currentScreen {
                self.currentScreen = currentScreen
                self.eventBatch.append(Event(screen: currentScreen))
            }
        })
        
        eventUploadTimer = Timer.scheduledTimer(withTimeInterval: uploadFrequency, repeats: true, block: { (_) in
            if self.eventBatch.count > 0 {
                self.eventUploadService.uploadBatch(events: self.eventBatch, appToken: self.appToken)
                self.eventBatch = []
            }
            
            self.uploadTimerLoopCount += 1
            if self.uploadTimerLoopCount >= self.checkAppEnabledFrequency {
                self.uploadTimerLoopCount = 0
                self.checkAppEnabled()
            }
        })
    }
    
    private func stopMonitoring() {
        screenDetectionTimer?.invalidate()
        eventUploadTimer?.invalidate()
        screenDetectionTimer = nil
        eventUploadTimer = nil
    }
    
    private func checkAppEnabled() {
        eventUploadService.checkKillSwitch(appToken: appToken) { (data, response, error) in
            DispatchQueue.main.async {
                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode == 200 {
                    self.startMonitoring()
                } else {
                    self.shutdown = true
                    self.stopMonitoring()
                }
            }
        }
    }

}

// ----------------------------------
// MARK: EventUploadService
// ----------------------------------


private class EventUploadService: NSObject {
    
    fileprivate let baseUrl = "https://midgar-flask.herokuapp.com/api"
    
    func checkKillSwitch(appToken: String, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        let parameters: [String: Any] = ["app_token": appToken]
        let url = baseUrl + "/apps/kill"
        guard let request = createPostRequest(url: url, parameters: parameters) else { return }
        URLSession.shared.dataTask(with: request, completionHandler: completion).resume()
    }
    
    func uploadBatch(events: [Event], appToken: String) {
        let parameters: [String: Any] = ["events": events.map { $0.toDict() }, "app_token": appToken]
        let url = baseUrl + "/events"
        guard let request = createPostRequest(url: url, parameters: parameters) else { return }
        URLSession.shared.dataTask(with: request).resume() // TODO: retry if failed.
    }
    
    func createPostRequest(url: String, parameters: [String: Any]) -> URLRequest? {
        guard let url = URL(string: url) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONSerialization.data(withJSONObject: parameters, options: []) else {
            return nil
        }
        request.httpBody = body
        return request
    }
    
}

// ----------------------------------
// MARK: Event Model
// ----------------------------------

private struct Event {
    
    let type: String
    let screen: String
    let timestamp: Int
    
    init(screen: String) {
        type = "impression"
        self.screen = screen
        timestamp = Date().timestamp
    }
    
    func toDict() -> [String: Any] {
        return ["type": type, "screen": screen, "timestamp": timestamp]
    }
    
}

// ----------------------------------
// MARK: Extensions
// ----------------------------------


extension UIApplication {
    
    class func topViewController(controller: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        
        if let tabController = controller as? UITabBarController {
            if let selected = tabController.selectedViewController {
                return topViewController(controller: selected)
            }
        }
        
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        
        return controller
    }
    
    class func topViewControllerDescription() -> String {
        if let topVC = topViewController() {
            return "\(type(of: topVC))"
        } else {
            return ""
        }
    }
    
}

extension Date {
    
    var timestamp: Int {
        return Int(truncatingIfNeeded: Int64((self.timeIntervalSince1970 * 1000.0).rounded()))
    }
    
}
