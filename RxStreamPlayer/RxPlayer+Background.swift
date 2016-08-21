import Foundation
import UIKit

extension RxPlayer {
	public func setUIApplication(uiApplication: UIApplicationType) {
		self.uiApplication = uiApplication
	}
	
	public func beginBackgroundTask() {
		guard let uiApplication = uiApplication else { return }
		beginBackgroundTask(uiApplication)
	}
	
	internal func beginBackgroundTask(application: UIApplicationType) {
		let currentIdentifier = backgroundTaskIdentifier
		
		backgroundTaskIdentifier = application.beginBackgroundTaskWithExpirationHandler { [weak self] in
			if let backgroundTaskIdentifier = self?.backgroundTaskIdentifier {
				application.endBackgroundTask(backgroundTaskIdentifier)
			}
			self?.backgroundTaskIdentifier = nil
		}
		
		if let currentIdentifier = currentIdentifier {
			application.endBackgroundTask(currentIdentifier)
		}
	}
	
	public func endBackgroundTask() {
		guard let uiApplication = uiApplication else { return }
		endBackgroundTask(uiApplication)
	}
	
	internal func endBackgroundTask(application: UIApplicationType) {
		if let backgroundTaskIdentifier = backgroundTaskIdentifier {
			if backgroundTaskIdentifier != UIBackgroundTaskInvalid {
				application.endBackgroundTask(backgroundTaskIdentifier)
			}
			self.backgroundTaskIdentifier = nil
		}
	}
}