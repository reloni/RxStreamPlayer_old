import Foundation
import AVFoundation
import RxSwift

enum AssetLoadingEvents {
	case shouldWaitForLoading(AVAssetResourceLoadingRequestProtocol)
	case didCancelLoading(AVAssetResourceLoadingRequestProtocol)
	/// this event will send when AVAssetResourceLoaderEventsObserver will deinit
	case observerDeinit
}

protocol AVAssetResourceLoaderEventsObserverProtocol {
	var loaderEvents: Observable<AssetLoadingEvents> { get }
	var shouldWaitForLoading: Bool { get set }
}

@objc final class AVAssetResourceLoaderEventsObserver : NSObject {
	internal let publishSubject = PublishSubject<AssetLoadingEvents>()
	var shouldWaitForLoading: Bool
	
	init(shouldWaitForLoading: Bool = true) {
		self.shouldWaitForLoading = shouldWaitForLoading
	}
	
	deinit {
		publishSubject.onNext(.observerDeinit)
	}
}

extension AVAssetResourceLoaderEventsObserver : AVAssetResourceLoaderEventsObserverProtocol {
	var loaderEvents: Observable<AssetLoadingEvents> {
		return publishSubject
	}
}

extension AVAssetResourceLoaderEventsObserver : AVAssetResourceLoaderDelegate {	
	func resourceLoader(resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
		publishSubject.onNext(.shouldWaitForLoading(loadingRequest))
		return shouldWaitForLoading
	}
	
	func resourceLoader(resourceLoader: AVAssetResourceLoader, didCancelLoadingRequest loadingRequest: AVAssetResourceLoadingRequest) {
		publishSubject.onNext(.didCancelLoading(loadingRequest))
	}
}