import Foundation
import AVFoundation
import RxSwift
@testable import RxHttpClient
@testable import RxStreamPlayer

public class FakeRequest : NSMutableURLRequestType {
	public var HTTPMethod: String? = "GET"
	var headers = [String: String]()
	public var URL: NSURL?
	public var allHTTPHeaderFields: [String: String]? {
		return headers
	}
	
	public init(url: NSURL? = nil) {
		self.URL = url
	}
	
	public func addValue(value: String, forHTTPHeaderField: String) {
		headers[forHTTPHeaderField] = value
	}
	
	public func setHttpMethod(method: String) {
		HTTPMethod = method
	}
}

public class FakeResponse : NSURLResponseType, NSHTTPURLResponseType {
	public var expectedContentLength: Int64
	public var MIMEType: String?
	
	public init(contentLenght: Int64) {
		expectedContentLength = contentLenght
	}
}

public enum FakeDataTaskMethods {
	case resume(FakeDataTask)
	case suspend(FakeDataTask)
	case cancel(FakeDataTask)
}

public class FakeDataTask : NSURLSessionDataTaskType {
	@available(*, unavailable, message="completion unavailiable. Use FakeSession.sendData instead (session observer will used to send data)")
	var completion: DataTaskResult?
	let taskProgress = PublishSubject<FakeDataTaskMethods>()
	var originalRequest: NSMutableURLRequestType?
	var isCancelled = false
	var resumeInvokeCount = 0
	
	public init(completion: DataTaskResult?) {
		//self.completion = completion
	}
	
	public func resume() {
		resumeInvokeCount += 1
		taskProgress.onNext(.resume(self))
	}
	
	public func suspend() {
		taskProgress.onNext(.suspend(self))
	}
	
	public func cancel() {
		if !isCancelled {
			taskProgress.onNext(.cancel(self))
			isCancelled = true
		}
	}
	
	public func getOriginalMutableUrlRequest() -> NSMutableURLRequestType? {
		return originalRequest
	}
}

public class FakeSession : NSURLSessionType {
	var task: FakeDataTask?
	var isInvalidatedAndCanceled = false
	
	public var configuration: NSURLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
	
	public init(fakeTask: FakeDataTask? = nil) {
		task = fakeTask
	}
	
	/// Send data as stream (this data should be received through session delegate)
	public func sendData(task: NSURLSessionDataTaskType, data: NSData?, streamObserver: NSURLSessionDataEventsObserver) {
		if let data = data {
			streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: self, dataTask: task, data: data))
		}
		// simulate delay
		NSThread.sleepForTimeInterval(0.01)
		streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self, dataTask: task, error: nil))
	}
	
	public func sendError(task: NSURLSessionDataTaskType, error: NSError, streamObserver: NSURLSessionDataEventsObserver) {
		streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self, dataTask: task, error: error))
	}
	
	public func dataTaskWithURL(url: NSURL, completionHandler: DataTaskResult) -> NSURLSessionDataTaskType {
		guard let task = self.task else {
			return FakeDataTask(completion: completionHandler)
		}
		//task.completion = completionHandler
		return task
	}
	
	public func dataTaskWithRequest(request: NSMutableURLRequestType, completionHandler: DataTaskResult) -> NSURLSessionDataTaskType {
		fatalError("should not invoke dataTaskWithRequest with completion handler")
		guard let task = self.task else {
			return FakeDataTask(completion: completionHandler)
		}
		//task.completion = completionHandler
		task.originalRequest = request
		return task
	}
	
	public func dataTaskWithRequest(request: NSMutableURLRequestType) -> NSURLSessionDataTaskType {
		guard let task = self.task else {
			return FakeDataTask(completion: nil)
		}
		task.originalRequest = request
		return task
	}
	
	public func invalidateAndCancel() {
		// set flag that session was invalidated and canceled
		isInvalidatedAndCanceled = true
		
		// invoke cancelation of task
		task?.cancel()
	}
}

public class FakeHttpUtilities : HttpUtilitiesType {
	//var fakeObserver: UrlSessionStreamObserverType?
	var streamObserver: NSURLSessionDataEventsObserverType?
	var fakeSession: NSURLSessionType?
	
	public func createUrlRequest(baseUrl: String, parameters: [String : String]?) -> NSMutableURLRequestType? {
		return FakeRequest(url: NSURL(baseUrl: baseUrl, parameters: parameters))
	}
	
	public func createUrlRequest(baseUrl: String, parameters: [String : String]?, headers: [String : String]?) -> NSMutableURLRequestType? {
		let req = createUrlRequest(baseUrl, parameters: parameters)
		headers?.forEach { req?.addValue($1, forHTTPHeaderField: $0) }
		return req
	}
	
	public func createUrlRequest(url: NSURL, headers: [String: String]?) -> NSMutableURLRequestType {
		let req = FakeRequest(url: url)
		headers?.forEach { req.addValue($1, forHTTPHeaderField: $0) }
		return req
	}
	
	public func createUrlSession(configuration: NSURLSessionConfiguration, delegate: NSURLSessionDelegate?, queue: NSOperationQueue?) -> NSURLSessionType {
		guard let session = fakeSession else {
			return FakeSession()
		}
		return session
	}
	
	public func createUrlSessionStreamObserver() -> NSURLSessionDataEventsObserverType {
		//		guard let observer = fakeObserver else {
		//			return FakeUrlSessionStreamObserver()
		//		}
		//		return observer
		guard let observer = streamObserver else {
			return NSURLSessionDataEventsObserver()
		}
		return observer
	}
	
	public func createStreamDataTask(taskUid: String, request: NSMutableURLRequestType, sessionConfiguration: NSURLSessionConfiguration, cacheProvider: CacheProviderType?) -> StreamDataTaskType {
		return StreamDataTask(taskUid: NSUUID().UUIDString, request: request, httpUtilities: self, sessionConfiguration: sessionConfiguration, cacheProvider: cacheProvider)
		//return FakeStreamDataTask(request: request, observer: createUrlSessionStreamObserver(), httpUtilities: self)
	}
}

public class FakeStreamResourceIdentifier : StreamResourceIdentifier {
	public var streamResourceUid: String
	init(uid: String) {
		streamResourceUid = uid
	}
	
	public var streamResourceUrl: Observable<String> {
		return Observable.create { observer in
			observer.onNext(self.streamResourceUid)
			
			return NopDisposable.instance
			}.observeOn(ConcurrentDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility))
	}
	
	public var streamResourceContentType: ContentType? {
		return nil
	}
}

public class FakeStreamResourceLoader : StreamResourceLoaderType {
	var items: [String]
	public func loadStreamResourceByUid(uid: String) -> StreamResourceIdentifier? {
		if items.contains(uid) {
			return FakeStreamResourceIdentifier(uid: uid)
		}
		return nil
	}
	public init(items: [String] = []) {
		self.items = items
	}
}

public class FakeAVAssetResourceLoadingContentInformationRequest : AVAssetResourceLoadingContentInformationRequestProtocol {
	public var byteRangeAccessSupported = false
	public var contentLength: Int64 = 0
	public var contentType: String? = nil
}

public class FakeAVAssetResourceLoadingDataRequest : AVAssetResourceLoadingDataRequestProtocol {
	public let respondedData = NSMutableData()
	public var currentOffset: Int64 = 0
	public var requestedOffset: Int64 = 0
	public var requestedLength: Int = 0
	public func respondWithData(data: NSData) {
		respondedData.appendData(data)
		currentOffset += data.length
	}
}

public class FakeAVAssetResourceLoadingRequest : NSObject, AVAssetResourceLoadingRequestProtocol {
	public var contentInformationRequest: AVAssetResourceLoadingContentInformationRequestProtocol
	public var dataRequest: AVAssetResourceLoadingDataRequestProtocol
	public var finished = false
	
	public init(contentInformationRequest: AVAssetResourceLoadingContentInformationRequestProtocol, dataRequest: AVAssetResourceLoadingDataRequestProtocol) {
		self.contentInformationRequest = contentInformationRequest
		self.dataRequest = dataRequest
	}
	
	public func getContentInformationRequest() -> AVAssetResourceLoadingContentInformationRequestProtocol? {
		return contentInformationRequest
	}
	
	public func getDataRequest() -> AVAssetResourceLoadingDataRequestProtocol? {
		return dataRequest
	}
	
	public func finishLoading() {
		finished = true
	}
}

public class FakeInternalPlayer : InternalPlayerType {
	//public let publishSubject = PublishSubject<PlayerEvents>()
	//public let metadataSubject = BehaviorSubject<AudioItemMetadata?>(value: nil)
	public let durationSubject = BehaviorSubject<CMTime?>(value: nil)
	public let currentTimeSubject = BehaviorSubject<(currentTime: CMTime?, duration: CMTime?)?>(value: nil)
	public let hostPlayer: RxPlayer
	public let eventsCallback: (PlayerEvents) -> ()
	
	public var nativePlayer: AVPlayerProtocol?
	
	//public var events: Observable<PlayerEvents> { return publishSubject }
	//public var metadata: Observable<AudioItemMetadata?> { return metadataSubject.shareReplay(1) }
	public var currentTime: Observable<(currentTime: CMTime?, duration: CMTime?)?> { return currentTimeSubject.shareReplay(1) }
	
	public func resume() {
		//publishSubject.onNext(.Resumed)
		eventsCallback(.Resumed)
	}
	
	public func pause() {
		//publishSubject.onNext(.Paused)
		eventsCallback(.Paused)
	}
	
	public func play(resource: StreamResourceIdentifier) -> Observable<Result<Void>> {
		eventsCallback(.Started)
		return Observable.empty()
	}
	
	public func stop() {
		//publishSubject.onNext(.Stopped)
		eventsCallback(.Stopped)
	}
	
	public func finishPlayingCurrentItem() {
		eventsCallback(.FinishPlayingCurrentItem)
		hostPlayer.toNext(true)
	}
	
	init(hostPlayer: RxPlayer, callback: (PlayerEvents) -> (), nativePlayer: AVPlayerProtocol? = nil) {
		self.hostPlayer = hostPlayer
		self.eventsCallback = callback
		self.nativePlayer = nativePlayer
	}
	
	public func getCurrentTimeAndDuration() -> (currentTime: CMTime, duration: CMTime)? {
		fatalError("getCurrentTimeAndDuration not implemented")
	}
}

public class FakeNativePlayer: AVPlayerProtocol {
	public var internalItemStatus: Observable<AVPlayerItemStatus?> {
		return Observable.just(nil)
	}
	public var rate: Float = 0.0
	public func replaceCurrentItemWithPlayerItem(item: AVPlayerItemProtocol?) {
		
	}
	public func play() {
		
	}
	public func setPlayerRate(rate: Float) {
		
	}
}

public class FakeStreamPlayerUtilities : StreamPlayerUtilitiesProtocol {
	init() {
		
	}
	
	public func createavUrlAsset(url: NSURL) -> AVURLAssetProtocol {
		return StreamPlayerUtilities().createavUrlAsset(url)
	}
	
	public func createavPlayerItem(url: NSURL) -> AVPlayerItemProtocol {
		return StreamPlayerUtilities().createavPlayerItem(url)
	}
	
	public func createavPlayerItem(asset: AVURLAssetProtocol) -> AVPlayerItemProtocol {
		return StreamPlayerUtilities().createavPlayerItem(asset)
	}
	
	public func createInternalPlayer(hostPlayer: RxPlayer, eventsCallback: (PlayerEvents) -> ()) -> InternalPlayerType {
		return FakeInternalPlayer(hostPlayer: hostPlayer, callback: eventsCallback)
	}
}

class FakeNSUserDefaults: NSUserDefaultsType {
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