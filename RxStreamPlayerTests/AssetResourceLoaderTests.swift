import XCTest
import RxSwift
@testable import RxStreamPlayer
@testable import RxHttpClient

class AssetResourceLoaderTests: XCTestCase {
	var bag: DisposeBag!
	var request: NSURLRequest!
	var session: FakeSession!
	var httpClient: HttpClient!
	var avAssetObserver: AVAssetResourceLoaderEventsObserver!
	var cacheTask: StreamDataTaskType!
	let waitTime = 4.0
	
	override func setUp() {
		super.setUp()
		
		bag = DisposeBag()
		request = NSURLRequest(URL: NSURL(string: "https://test.com")!)
		let fakeTask = FakeDataTask(resumeClosure: { fatalError("Resume closure should be overriden") })
		fakeTask.originalRequest = request
		session = FakeSession(dataTask: fakeTask)
		httpClient = HttpClient(session: session)
		cacheTask = StreamDataTask(taskUid: NSUUID().UUIDString,
		                           dataTask: session.dataTaskWithRequest(request),
		                           sessionEvents: httpClient.sessionObserver.sessionEvents,
		                           cacheProvider: MemoryCacheProvider(uid: NSUUID().UUIDString))

		avAssetObserver = AVAssetResourceLoaderEventsObserver()
	}
	
	override func tearDown() {
		super.tearDown()
		bag = nil
		request = nil
		session = nil
		cacheTask = nil
		avAssetObserver = nil
	}
	
	func testReceiveResponseAndGetCorrectUtiTypeFromResponseMimeType() {
		let fakeResponse = NSURLResponse(URL: NSURL(baseUrl: "http://test.com")!,
		                                 MIMEType: "audio/mpeg",
		                                 expectedContentLength: 26,
		                                 textEncodingName: nil)
		
		let assetRequest = FakeAVAssetResourceLoadingRequest(contentInformationRequest: FakeAVAssetResourceLoadingContentInformationRequest(),
		                                                     dataRequest: FakeAVAssetResourceLoadingDataRequest())
		
		session.task.resumeClosure = { _ in
			XCTAssertEqual(self.session.task.originalRequest?.URL, self.request.URL, "Check correct task url")
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [unowned self] in
				self.avAssetObserver.publishSubject.onNext(.shouldWaitForLoading(assetRequest))
				
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: self.session, dataTask: self.session.task, response: fakeResponse, completion: { _ in }))
				
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self.session, dataTask: self.session.task, error: nil))
			}
			
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [unowned self] in
				NSThread.sleepForTimeInterval(0.2)
				self.avAssetObserver.publishSubject.onNext(.observerDeinit)
			}
		}
		
		let assetLoadCompletion = expectationWithDescription("Should complete asset loading")
		
		cacheTask.taskProgress.loadWithAsset(assetEvents: avAssetObserver.loaderEvents, targetAudioFormat: nil)
			.doOnCompleted {
				XCTAssertEqual(26, assetRequest.contentInformationRequest.contentLength, "Check content lenge of response")
				XCTAssertEqual(assetRequest.contentInformationRequest.contentType, "public.mp3", "Should get mime from response and convert to correct uti")
				assetLoadCompletion.fulfill()
			}.subscribe().addDisposableTo(bag)
		cacheTask.resume()
		
		waitForExpectationsWithTimeout(waitTime, handler: nil)
	}
	
	func testOverrideContentType() {
		let fakeResponse = NSURLResponse(URL: NSURL(baseUrl: "http://test.com")!,
		                                 MIMEType: "audio/mpeg",
		                                 expectedContentLength: 26,
		                                 textEncodingName: nil)
		
		let assetRequest = FakeAVAssetResourceLoadingRequest(contentInformationRequest: FakeAVAssetResourceLoadingContentInformationRequest(),
		                                                     dataRequest: FakeAVAssetResourceLoadingDataRequest())
		
		session.task.resumeClosure = {
			XCTAssertEqual(self.session.task.originalRequest?.URL, self.request.URL, "Check correct task url")
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [unowned self] in
				self.avAssetObserver.publishSubject.onNext(.shouldWaitForLoading(assetRequest))
				
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: self.session, dataTask: self.session.task, response: fakeResponse, completion: { _ in }))
				
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self.session, dataTask: self.session.task, error: nil))
			}
			
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [unowned self] in
				NSThread.sleepForTimeInterval(0.2)
				self.avAssetObserver.publishSubject.onNext(.observerDeinit)
			}
		}
		
		let assetLoadCompletion = expectationWithDescription("Should complete asset loading")
		
		cacheTask.taskProgress.loadWithAsset(assetEvents: avAssetObserver.loaderEvents, targetAudioFormat: ContentType.aac).doOnCompleted {
			XCTAssertEqual(26, assetRequest.contentInformationRequest.contentLength, "Check content lenge of responce")
			XCTAssertEqual("public.aac-audio", assetRequest.contentInformationRequest.contentType, "Should return correct overriden uti type")
			assetLoadCompletion.fulfill()
			}.subscribe().addDisposableTo(bag)
		cacheTask.resume()
		
		waitForExpectationsWithTimeout(waitTime, handler: nil)
	}
	
//	func testReceiveNewLoadingRequest() {
//		let assetRequest = FakeAVAssetResourceLoadingRequest(contentInformationRequest: FakeAVAssetResourceLoadingContentInformationRequest(),
//		                                                     dataRequest: FakeAVAssetResourceLoadingDataRequest())
//		
//		let expectation = expectationWithDescription("Should receive result from asset loader")
//		var result: (receivedResponse: NSHTTPURLResponseProtocol?, utiType: String?, resultRequestCollection: [Int: AVAssetResourceLoadingRequestProtocol])?
//		cacheTask.taskProgress.loadWithAsset(assetEvents: avAssetObserver.loaderEvents, targetAudioFormat: nil).bindNext { e in
//			guard case Result.success(let box) = e else { return }
//			result = box.value
//			expectation.fulfill()
//			}.addDisposableTo(bag)
//		
//		self.avAssetObserver.publishSubject.onNext(.ShouldWaitForLoading(assetRequest))
//		self.streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self.session, dataTask: FakeDataTask(completion: nil), error: nil))
//		
//		waitForExpectationsWithTimeout(1, handler: nil)
//		
//		XCTAssertEqual(1, result?.resultRequestCollection.count)
//		XCTAssertEqual(assetRequest.hash, result?.resultRequestCollection.first?.1.hash)
//	}
	
//	func testNotCacheSameLoadingRequestMoreThanOnce() {
//		let assetRequest = FakeAVAssetResourceLoadingRequest(contentInformationRequest: FakeAVAssetResourceLoadingContentInformationRequest(),
//		                                                     dataRequest: FakeAVAssetResourceLoadingDataRequest())
//		
//		let assetLoadingCompletion = expectationWithDescription("Should complete asset loading")
//		
//		var result: (receivedResponse: NSHTTPURLResponseProtocol?, utiType: String?, resultRequestCollection: [Int: AVAssetResourceLoadingRequestProtocol])?
//		cacheTask.taskProgress.loadWithAsset(assetEvents: avAssetObserver.loaderEvents, targetAudioFormat: nil).bindNext { e in
//			guard case Result.success(let box) = e else { return }
//			result = box.value
//			assetLoadingCompletion.fulfill()
//			}.addDisposableTo(bag)
//		
//		avAssetObserver.publishSubject.onNext(.ShouldWaitForLoading(assetRequest))
//		avAssetObserver.publishSubject.onNext(.ShouldWaitForLoading(assetRequest))
//		avAssetObserver.publishSubject.onNext(.ShouldWaitForLoading(assetRequest))
//		
//		self.streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self.session, dataTask: FakeDataTask(completion: nil), error: nil))
//		
//		waitForExpectationsWithTimeout(1, handler: nil)
//		
//		XCTAssertEqual(1, result?.resultRequestCollection.count)
//		XCTAssertEqual(assetRequest.hash, result?.resultRequestCollection.first?.1.hash)
//	}
	
//	func testRemoveCanceledLoadingRequest() {
//		let assetRequest1 = FakeAVAssetResourceLoadingRequest(contentInformationRequest: FakeAVAssetResourceLoadingContentInformationRequest(),
//		                                                      dataRequest: FakeAVAssetResourceLoadingDataRequest())
//		let assetRequest2 = FakeAVAssetResourceLoadingRequest(contentInformationRequest: FakeAVAssetResourceLoadingContentInformationRequest(),
//		                                                      dataRequest: FakeAVAssetResourceLoadingDataRequest())
//		
//		let assetLoadingCompletion = expectationWithDescription("Should complete asset loading")
//		
//		var result: (receivedResponse: NSHTTPURLResponseProtocol?, utiType: String?, resultRequestCollection: [Int: AVAssetResourceLoadingRequestProtocol])?
//		cacheTask.taskProgress.loadWithAsset(assetEvents: avAssetObserver.loaderEvents, targetAudioFormat: nil).bindNext { e in
//			guard case Result.success(let box) = e else { return }
//			result = box.value
//			assetLoadingCompletion.fulfill()
//			}.addDisposableTo(bag)
//		
//		avAssetObserver.publishSubject.onNext(.ShouldWaitForLoading(assetRequest1))
//		avAssetObserver.publishSubject.onNext(.ShouldWaitForLoading(assetRequest1))
//		avAssetObserver.publishSubject.onNext(.ShouldWaitForLoading(assetRequest2))
//		avAssetObserver.publishSubject.onNext(.DidCancelLoading(assetRequest1))
//		
//		self.streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self.session, dataTask: FakeDataTask(completion: nil), error: nil))
//		
//		waitForExpectationsWithTimeout(1, handler: nil)
//		
//		XCTAssertEqual(1, result?.resultRequestCollection.count)
//		XCTAssertEqual(assetRequest2.hash, result?.resultRequestCollection.first?.1.hash)
//	}
	
	func testRespondWithCorrectDataForOneContentRequest() {
		let contentRequest = FakeAVAssetResourceLoadingContentInformationRequest()
		contentRequest.contentLength = 0
		let dataRequest = FakeAVAssetResourceLoadingDataRequest()
		dataRequest.requestedLength = 22
		let assetRequest = FakeAVAssetResourceLoadingRequest(contentInformationRequest: contentRequest,
		                                                     dataRequest: dataRequest)
		
		let testData = ["First", "Second", "Third", "Fourth"]
		let sendedData = NSMutableData()
		
		session.task.resumeClosure = {
			XCTAssertEqual(self.session.task.originalRequest?.URL, self.request.URL, "Check correct task url")
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [unowned self] in
				let fakeResponse = NSURLResponse(URL: NSURL(baseUrl: "http://test.com")!,
				                                 MIMEType: "audio/mpeg",
				                                 expectedContentLength: dataRequest.requestedLength,
				                                 textEncodingName: nil)
				
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: self.session, dataTask: self.session.task, response: fakeResponse, completion: { _ in }))
				
				for i in 0...testData.count - 1 {
					let sendData = testData[i].dataUsingEncoding(NSUTF8StringEncoding)!
					sendedData.appendData(sendData)
					self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didReceiveData(session: self.session, dataTask: self.session.task, data: sendData))
					// simulate delay
					NSThread.sleepForTimeInterval(0.01)
				}
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self.session, dataTask: self.session.task, error: nil))
				self.avAssetObserver.publishSubject.onNext(.observerDeinit)
			}
		}
		
		let assetLoadingCompletion = expectationWithDescription("Should complete asset loading")
		
		cacheTask.taskProgress.loadWithAsset(assetEvents: avAssetObserver.loaderEvents, targetAudioFormat: nil).doOnCompleted {
			assetLoadingCompletion.fulfill()
			}.subscribe().addDisposableTo(bag)
		
		avAssetObserver.publishSubject.onNext(.shouldWaitForLoading(assetRequest))
		cacheTask.resume()
		
		
		waitForExpectationsWithTimeout(waitTime, handler: nil)
		
		XCTAssertTrue(sendedData.isEqualToData(dataRequest.respondedData), "Check correct data sended to dataRequest")
		//XCTAssertEqual(0, result?.resultRequestCollection.count, " Check remove loading request from collection of pending requests")
		XCTAssertTrue(assetRequest.finished, "Check loading request if finished")
		XCTAssertTrue(contentRequest.byteRangeAccessSupported, "Should set byteRangeAccessSupported to true")
		XCTAssertEqual(contentRequest.contentLength, Int64(dataRequest.requestedLength), "Check correct content length")
		XCTAssertEqual(contentRequest.contentType, "public.mp3", "Check correct mime type")
	}
	
	func testRespondWithCorrectDataForTwoConcurrentRequests() {
		let contentRequest1 = FakeAVAssetResourceLoadingContentInformationRequest()
		contentRequest1.contentLength = 0
		let dataRequest1 = FakeAVAssetResourceLoadingDataRequest()
		dataRequest1.requestedLength = 11
		let assetRequest1 = FakeAVAssetResourceLoadingRequest(contentInformationRequest: contentRequest1,
		                                                      dataRequest: dataRequest1)
		
		let contentRequest2 = FakeAVAssetResourceLoadingContentInformationRequest()
		contentRequest2.contentLength = 0
		let dataRequest2 = FakeAVAssetResourceLoadingDataRequest()
		dataRequest2.requestedLength = 11
		dataRequest2.currentOffset = 11
		dataRequest2.requestedOffset = 11
		let assetRequest2 = FakeAVAssetResourceLoadingRequest(contentInformationRequest: contentRequest2,
		                                                      dataRequest: dataRequest2)
		
		let testData = ["First", "Second", "Third", "Fourth"]
		let sendedData = NSMutableData()
		
		session.task.resumeClosure = {
			XCTAssertEqual(self.session.task.originalRequest?.URL, self.request.URL, "Check correct task url")
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [unowned self] in
				let fakeResponse = NSURLResponse(URL: NSURL(baseUrl: "http://test.com")!,
				                                 MIMEType: "audio/mpeg",
				                                 expectedContentLength: 22,
				                                 textEncodingName: nil)
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: self.session, dataTask: self.session.task, response: fakeResponse, completion: { _ in }))
				
				self.avAssetObserver.publishSubject.onNext(.shouldWaitForLoading(assetRequest1))
				self.avAssetObserver.publishSubject.onNext(.shouldWaitForLoading(assetRequest2))
				
				for i in 0...testData.count - 1 {
					let sendData = testData[i].dataUsingEncoding(NSUTF8StringEncoding)!
					sendedData.appendData(sendData)
					self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didReceiveData(session: self.session, dataTask: self.session.task, data: sendData))
					// simulate delay
					NSThread.sleepForTimeInterval(0.01)
				}
				
				self.httpClient.sessionObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: self.session, dataTask: self.session.task, error: nil))
				
				self.avAssetObserver.publishSubject.onNext(.observerDeinit)
			}
		}
		
		let assetLoadingCompletion = expectationWithDescription("Should complete asset loading")
		
		cacheTask.taskProgress.loadWithAsset(assetEvents: avAssetObserver.loaderEvents, targetAudioFormat: nil).doOnCompleted {
			assetLoadingCompletion.fulfill()
			}.subscribe().addDisposableTo(bag)
		
		cacheTask.resume()
		
		waitForExpectationsWithTimeout(waitTime, handler: nil)
		
		XCTAssertTrue(sendedData.subdataWithRange(NSMakeRange(0, 11)).isEqualToData(dataRequest1.respondedData), "Check half of data sended to first dataRequest")
		XCTAssertTrue(sendedData.subdataWithRange(NSMakeRange(11, 11)).isEqualToData(dataRequest2.respondedData), "Check second half of data sended to secondRequest")
		//XCTAssertEqual(0, result?.resultRequestCollection.count, "Check remove loading request from collection of pending requests")
		
		XCTAssertTrue(assetRequest1.finished, "Check loading first request if finished")
		XCTAssertTrue(contentRequest1.byteRangeAccessSupported, "Should set first request byteRangeAccessSupported to true")
		XCTAssertEqual(contentRequest1.contentLength, 22, "Check correct content length of first request")
		XCTAssertEqual(contentRequest1.contentType, "public.mp3", "Check correct mime type of first")
	}
	
	func testAvUrlAssetResourceLoaderUseDelegateWhenCustomSchemeProvided() {
		let utilities = StreamPlayerUtilities()
		let asset = utilities.createavUrlAsset(NSURL(baseUrl: "fake://test.com", parameters: nil)!)
		let observer = AVAssetResourceLoaderEventsObserver()
		asset.getResourceLoader().setDelegate(observer, queue: dispatch_get_global_queue(QOS_CLASS_UTILITY, 0))
		
		let expectation = expectationWithDescription("Should invoke resource loader observer methods")
		
		let bag = DisposeBag()
		observer.loaderEvents.bindNext { event in
			if case AssetLoadingEvents.shouldWaitForLoading = event { expectation.fulfill() }
		}.addDisposableTo(bag)
		
		asset.loadValuesAsynchronouslyForKeys(["duration"], completionHandler: nil)
		
		waitForExpectationsWithTimeout(waitTime, handler: nil)
	}
}
