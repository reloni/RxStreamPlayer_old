import Foundation
import AVFoundation
import RxSwift
@testable import RxHttpClient
@testable import RxStreamPlayer

final class FakeRequest : NSMutableURLRequestType {
	var HTTPMethod: String? = "GET"
	var headers = [String: String]()
	var URL: NSURL?
	var allHTTPHeaderFields: [String: String]? {
		return headers
	}
	
	init(url: NSURL? = nil) {
		self.URL = url
	}
	
	func addValue(value: String, forHTTPHeaderField: String) {
		headers[forHTTPHeaderField] = value
	}
	
	func setHttpMethod(method: String) {
		HTTPMethod = method
	}
}

final class FakeResponse : NSURLResponseType, NSHTTPURLResponseType {
	var expectedContentLength: Int64
	var MIMEType: String?
	
	init(contentLenght: Int64) {
		expectedContentLength = contentLenght
	}
}

enum FakeDataTaskMethods {
	case resume(FakeDataTask)
	case suspend(FakeDataTask)
	case cancel(FakeDataTask)
}

final class FakeDataTask : NSObject, NSURLSessionDataTaskType {
	@available(*, unavailable, message="completion unavailiable. Use FakeSession.sendData instead (session observer will used to send data)")
	var completion: DataTaskResult?
	let taskProgress = PublishSubject<FakeDataTaskMethods>()
	var originalRequest: NSURLRequestType?
	var isCancelled = false
	var resumeInvokeCount = 0
	
	init(completion: DataTaskResult?) {
		//self.completion = completion
	}
	
	func resume() {
		resumeInvokeCount += 1
		taskProgress.onNext(.resume(self))
	}
	
	func suspend() {
		taskProgress.onNext(.suspend(self))
	}
	
	func cancel() {
		if !isCancelled {
			taskProgress.onNext(.cancel(self))
			isCancelled = true
		}
	}
	
	func getOriginalUrlRequest() -> NSURLRequestType? {
		return originalRequest
	}
}

final class FakeSession : NSURLSessionType {
	var task: FakeDataTask?
	var isInvalidatedAndCanceled = false
	
	var configuration: NSURLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
	
	init(fakeTask: FakeDataTask? = nil) {
		task = fakeTask
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
	
	func dataTaskWithURL(url: NSURL, completionHandler: DataTaskResult) -> NSURLSessionDataTaskType {
		guard let task = self.task else {
			return FakeDataTask(completion: completionHandler)
		}
		//task.completion = completionHandler
		return task
	}
	
	func dataTaskWithRequest(request: NSURLRequestType, completionHandler: DataTaskResult) -> NSURLSessionDataTaskType {
		fatalError("should not invoke dataTaskWithRequest with completion handler")
		guard let task = self.task else {
			return FakeDataTask(completion: completionHandler)
		}
		//task.completion = completionHandler
		task.originalRequest = request
		return task
	}
	
	func dataTaskWithRequest(request: NSURLRequestType) -> NSURLSessionDataTaskType {
		guard let task = self.task else {
			return FakeDataTask(completion: nil)
		}
		task.originalRequest = request
		return task
	}
	
	func invalidateAndCancel() {
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
	
	func createUrlSessionStreamObserver() -> NSURLSessionDataEventsObserverType {
		//		guard let observer = fakeObserver else {
		//			return FakeUrlSessionStreamObserver()
		//		}
		//		return observer
		guard let observer = streamObserver else {
			return NSURLSessionDataEventsObserver()
		}
		return observer
	}
	
	func createStreamDataTask(taskUid: String, dataTask: NSURLSessionDataTaskType, httpClient: HttpClientType,
	                          sessionEvents: Observable<SessionDataEvents>, cacheProvider: CacheProviderType?) -> StreamDataTaskType {
		return StreamDataTask(taskUid: NSUUID().UUIDString, dataTask: dataTask, httpClient: httpClient, sessionEvents: sessionEvents, cacheProvider: cacheProvider)
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