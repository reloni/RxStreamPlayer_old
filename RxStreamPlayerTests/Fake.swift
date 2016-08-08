import Foundation
@testable import RxHttpClient
@testable import RxStreamPlayer
import AVFoundation
import RxSwift

final class FakeDataTask : NSObject, NSURLSessionDataTaskType {
	var originalRequest: NSURLRequest?
	var isCancelled = false
	var resumeInvokeCount = 0
	var resumeClosure: (() -> ())!
	var cancelClosure: (() -> ())?
	
	init(resumeClosure: () -> (), cancelClosure: (() -> ())? = nil) {
		self.resumeClosure = resumeClosure
		self.cancelClosure = cancelClosure
	}
	
	func resume() {
		resumeInvokeCount += 1
		resumeClosure()
	}
	
	func cancel() {
		if !isCancelled {
			cancelClosure?()
			isCancelled = true
		}
	}
}

final class FakeSession : NSURLSessionType {
	var task: FakeDataTask!
	var isFinished = false
	
	var configuration: NSURLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
	
	init(dataTask: FakeDataTask? = nil) {
		task = dataTask
	}
	
	/// Send data as stream (this data should be received through session delegate)
	func sendData(task: NSURLSessionDataTaskType, data: NSData?, streamObserver: NSURLSessionDataEventsObserver) {
		if let data = data {
			streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: self, dataTask: task, data: data))
		}
		// simulate delay
		NSThread.sleepForTimeInterval(0.01)
		streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self, dataTask: task, error: nil))
	}
	
	func sendError(task: NSURLSessionDataTaskType, error: NSError, streamObserver: NSURLSessionDataEventsObserver) {
		streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self, dataTask: task, error: error))
	}
	
	func dataTaskWithRequest(request: NSURLRequest) -> NSURLSessionDataTaskType {
		if task == nil { fatalError("Data task not specified") }
		task.originalRequest = request
		return task
	}
	
	func finishTasksAndInvalidate() {
		// set flag that session was invalidated
		isFinished = true
		
		// invoke cancelation of task
		task?.cancel()
	}
}

final class FakeStreamResourceIdentifier : StreamResourceIdentifier {
	var streamResourceUid: String
	init(uid: String) {
		streamResourceUid = uid
	}
	
	var streamResourceUrl: Observable<String> {
		return Observable.create { observer in
			observer.onNext(self.streamResourceUid)
			
			return NopDisposable.instance
			}.observeOn(ConcurrentDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility))
	}
	
	var streamResourceContentType: ContentType? {
		return nil
	}
}

final class FakeStreamResourceLoader : StreamResourceLoaderType {
	var items: [String]
	func loadStreamResourceByUid(uid: String) -> StreamResourceIdentifier? {
		if items.contains(uid) {
			return FakeStreamResourceIdentifier(uid: uid)
		}
		return nil
	}
	
	init(items: [String] = []) {
		self.items = items
	}
}

final class FakeAVAssetResourceLoadingContentInformationRequest : AVAssetResourceLoadingContentInformationRequestProtocol {
	var byteRangeAccessSupported = false
	var contentLength: Int64 = 0
	var contentType: String? = nil
}

final class FakeAVAssetResourceLoadingDataRequest : AVAssetResourceLoadingDataRequestProtocol {
	let respondedData = NSMutableData()
	var currentOffset: Int64 = 0
	var requestedOffset: Int64 = 0
	var requestedLength: Int = 0
	func respondWithData(data: NSData) {
		respondedData.appendData(data)
		currentOffset += data.length
	}
}

final class FakeAVAssetResourceLoadingRequest : NSObject, AVAssetResourceLoadingRequestProtocol {
	var contentInformationRequest: AVAssetResourceLoadingContentInformationRequestProtocol
	var dataRequest: AVAssetResourceLoadingDataRequestProtocol
	var finished = false
	
	init(contentInformationRequest: AVAssetResourceLoadingContentInformationRequestProtocol, dataRequest: AVAssetResourceLoadingDataRequestProtocol) {
		self.contentInformationRequest = contentInformationRequest
		self.dataRequest = dataRequest
	}
	
	func getContentInformationRequest() -> AVAssetResourceLoadingContentInformationRequestProtocol? {
		return contentInformationRequest
	}
	
	func getDataRequest() -> AVAssetResourceLoadingDataRequestProtocol? {
		return dataRequest
	}
	
	func finishLoading() {
		finished = true
	}
}

final class FakeInternalPlayer : InternalPlayerType {
	//public let publishSubject = PublishSubject<PlayerEvents>()
	//public let metadataSubject = BehaviorSubject<AudioItemMetadata?>(value: nil)
	let durationSubject = BehaviorSubject<CMTime?>(value: nil)
	let currentTimeSubject = BehaviorSubject<(currentTime: CMTime?, duration: CMTime?)?>(value: nil)
	let hostPlayer: RxPlayer
	let eventsCallback: (PlayerEvents) -> ()
	
	var nativePlayer: AVPlayerProtocol?
	
	//public var events: Observable<PlayerEvents> { return publishSubject }
	//public var metadata: Observable<AudioItemMetadata?> { return metadataSubject.shareReplay(1) }
	var currentTime: Observable<(currentTime: CMTime?, duration: CMTime?)?> { return currentTimeSubject.shareReplay(1) }
	
	func resume() {
		//publishSubject.onNext(.Resumed)
		eventsCallback(.Resumed)
	}
	
	func pause() {
		//publishSubject.onNext(.Paused)
		eventsCallback(.Paused)
	}
	
	func play(resource: StreamResourceIdentifier) -> Observable<Void> {
		eventsCallback(.Started)
		return Observable.empty()
	}
	
	func stop() {
		//publishSubject.onNext(.Stopped)
		eventsCallback(.Stopped)
	}
	
	func finishPlayingCurrentItem() {
		eventsCallback(.FinishPlayingCurrentItem)
		hostPlayer.toNext(true)
	}
	
	init(hostPlayer: RxPlayer, callback: (PlayerEvents) -> (), nativePlayer: AVPlayerProtocol? = nil) {
		self.hostPlayer = hostPlayer
		self.eventsCallback = callback
		self.nativePlayer = nativePlayer
	}
	
	func getCurrentTimeAndDuration() -> (currentTime: CMTime, duration: CMTime)? {
		fatalError("getCurrentTimeAndDuration not implemented")
	}
}

final class FakeNativePlayer: AVPlayerProtocol {
	var internalItemStatus: Observable<AVPlayerItemStatus?> {
		return Observable.just(nil)
	}
	var rate: Float = 0.0
	func replaceCurrentItemWithPlayerItem(item: AVPlayerItemProtocol?) {
		
	}
	func play() {
		
	}
	func setPlayerRate(rate: Float) {
		
	}
}

struct FakeStreamPlayerUtilities : StreamPlayerUtilitiesProtocol {
	init() {
		
	}
	
	func createavUrlAsset(url: NSURL) -> AVURLAssetProtocol {
		return StreamPlayerUtilities().createavUrlAsset(url)
	}
	
	func createavPlayerItem(url: NSURL) -> AVPlayerItemProtocol {
		return StreamPlayerUtilities().createavPlayerItem(url)
	}
	
	func createavPlayerItem(asset: AVURLAssetProtocol) -> AVPlayerItemProtocol {
		return StreamPlayerUtilities().createavPlayerItem(asset)
	}
	
	func createInternalPlayer(hostPlayer: RxPlayer, eventsCallback: (PlayerEvents) -> ()) -> InternalPlayerType {
		return FakeInternalPlayer(hostPlayer: hostPlayer, callback: eventsCallback)
	}
}

final class FakeNSUserDefaults: NSUserDefaultsType {
	var localCache: [String: AnyObject]
	//["testResource": OAuthResourceBase(id: "testResource", authUrl: "https://test", clientId: nil, tokenId: nil)]
	
	init(localCache: [String: AnyObject]) {
		self.localCache = localCache
	}
	
	convenience init() {
		self.init(localCache: [String: AnyObject]())
	}
	
	func saveData(object: AnyObject, forKey: String) {
		localCache[forKey] = object
	}
	
	func loadData<T>(forKey: String) -> T? {
		return loadRawData(forKey) as? T
	}
	
	func loadRawData(forKey: String) -> AnyObject? {
		return localCache[forKey]
	}
	
	func setObject(value: AnyObject?, forKey: String) {
		guard let value = value else { return }
		saveData(value, forKey: forKey)
	}
	
	func objectForKey(forKey: String) -> AnyObject? {
		return loadRawData(forKey)
	}
}
