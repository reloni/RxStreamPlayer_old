import XCTest
import RxSwift
import RxTests
import OHHTTPStubs
@testable import RxStreamPlayer
@testable import RxHttpClient

class DownloadManagerTests: XCTestCase {
	let bag = DisposeBag()
	let httpClient = HttpClient(session: FakeSession(dataTask: FakeDataTask( resumeClosure: { _ in })))
	
	let defaultFakeResponse = NSURLResponse(URL: NSURL(baseUrl: "http://test.com")!,
	                                 MIMEType: "audio/mpeg",
	                                 expectedContentLength: 0,
	                                 textEncodingName: nil)
	
	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}
	
	func testCreateLocalFileStreamTask() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let file = NSFileManager.temporaryDirectory.URLByAppendingPathComponent("\(NSUUID().UUIDString).dat")
		NSFileManager.defaultManager().createFileAtPath(file.path!, contents: nil, attributes: nil)
		let task = try! manager.createDownloadTask(file.path!, priority: .High).toBlocking().first()
		XCTAssertTrue(task is LocalFileStreamDataTask, "Should create instance of LocalFileStreamDataTask")
		XCTAssertEqual(1, manager.pendingTasks.count, "Should add task to pending tasks")
		XCTAssertEqual(PendingTaskPriority.High, manager.pendingTasks.first?.1.priority, "Should create pending task with correct priority")
		let _ = try? NSFileManager.defaultManager().removeItemAtURL(file)
	}
	
	func testNotCreateLocalFileStreamTaskForNotExistedFile() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let file = NSFileManager.temporaryDirectory.URLByAppendingPathComponent("\(NSUUID().UUIDString).dat")
		do {
			try manager.createDownloadTask(file.path!, priority: .Normal).toBlocking().first()
		} catch DownloadManagerErrors.unsupportedUrlScheme {	}
		catch {
			XCTFail("Incorrect error was thrown")
		}
		//XCTAssertNil(task, "Should not create a task")
		XCTAssertEqual(0, manager.pendingTasks.count, "Should not add task to pending tasks")
	}
	
	func testCreateUrlStreamTask() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let task = try! manager.createDownloadTask("https://somelink.com", priority: .Normal).toBlocking().first()
		XCTAssertTrue(task is RxHttpClient.StreamDataTask, "Should create instance of StreamDataTask")
		XCTAssertEqual(1, manager.pendingTasks.count, "Should add task to pending tasks")
	}
	
	func testNotCreateStreamTaskForIncorrectScheme() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		do {
			try manager.createDownloadTask("incorrect://somelink.com", priority: .Normal).toBlocking().first()
		} catch DownloadManagerErrors.unsupportedUrlScheme { }
		catch {
			XCTFail("Incorrect error was thrown")
		}
		XCTAssertEqual(0, manager.pendingTasks.count, "Should not add task to pending tasks")
	}
	
	func testReturnPendingTask() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let file = NSFileManager.temporaryDirectory.URLByAppendingPathComponent("\(NSUUID().UUIDString).dat")
		NSFileManager.defaultManager().createFileAtPath(file.path!, contents: nil, attributes: nil)
		// create task and add it to pending tasks
		let newTask = LocalFileStreamDataTask(uid: file.path!.streamResourceUid, filePath: file.path!)!
		manager.pendingTasks[newTask.uid] = PendingTask(task: newTask)
		
		// create download task for same file
		let task = try! manager.createDownloadTask(file.path!, priority: .Normal).toBlocking().first() as? LocalFileStreamDataTask
		XCTAssertTrue(newTask === task, "Should return same instance of task")
		XCTAssertEqual(1, manager.pendingTasks.count, "Should not add new task to pending tasks")
		file.deleteFile()
	}
	
	func testReturnLocalFileStreamTaskForUrlIfExistedInStorage() {
		let fileStorage = LocalNsUserDefaultsStorage()
		let manager = DownloadManager(saveData: false, fileStorage: fileStorage, httpClient: httpClient)
		// create new file in temp storage directory
		let file = fileStorage.tempStorageDirectory.URLByAppendingPathComponent("\(NSUUID().UUIDString).dat")
		NSFileManager.defaultManager().createFileAtPath(file.path!, contents: nil, attributes: nil)
		// save this file in fileStorageCache
		fileStorage.tempStorageDictionary["https://somelink.com"] = file.lastPathComponent!
		// create download task
		let task = try! manager.createDownloadTask("https://somelink.com", priority: .Normal).toBlocking().first()
		XCTAssertTrue(task is LocalFileStreamDataTask, "Should create instance of LocalFileStreamDataTask, because file exists in cache")
		XCTAssertEqual(1, manager.pendingTasks.count, "Should add task to pending tasks")
		let _ = try? NSFileManager.defaultManager().removeItemAtURL(file)
	}
	
	func testThreadSafetyForCreationNewTask() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		for _ in 0...100 {
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [unowned self] in
				let fakeResource = FakeStreamResourceIdentifier(uid: "https://somelink.com")
				manager.createDownloadTask(fakeResource, priority: .Normal).subscribe().addDisposableTo(self.bag)
			}
		}
		
		NSThread.sleepForTimeInterval(0.5)
		XCTAssertEqual(1, manager.pendingTasks.count, "Check only one task created")
	}
	
	func testThreadSafetyForCreateObservable() {
		let session = FakeSession(dataTask: FakeDataTask(resumeClosure: { _ in }))
		let httpClient = HttpClient(session: session)
		
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		for _ in 0...10 {
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
				let fakeResource = FakeStreamResourceIdentifier(uid: "https://somelink.com")
				manager.createDownloadObservable(fakeResource, priority: .Normal).subscribe().addDisposableTo(self.bag)
			}
		}
		
		NSThread.sleepForTimeInterval(0.5)
		XCTAssertEqual(1, manager.pendingTasks.count, "Check only one task created")
		XCTAssertEqual(session.task?.resumeInvokeCount, 1)
	}
	
	func testDownloadObservableForIncorrectUrl() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		let errorExpectation = expectationWithDescription("Should send error message")
		manager.createDownloadObservable("wrong://test.com", priority: .Normal).doOnError { error in
			if case DownloadManagerErrors.unsupportedUrlScheme(_, let uid) = error {
				XCTAssertEqual(uid, "wrong://test.com", "Check returned correct uid in error info")
			} else {
				XCTFail("Incorrect error returned")
			}
			
			errorExpectation.fulfill()
			}.subscribe().addDisposableTo(bag)
		waitForExpectationsWithTimeout(1, handler: nil)
	}
	
	func testDownloadObservableForNotExistedFile() {
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		let errorExpectation = expectationWithDescription("Should send error message")
		manager.createDownloadObservable("/Path/To/Not/existed.file", priority: .Normal).doOnError { error in
			if case DownloadManagerErrors.unsupportedUrlScheme(let url, let uid) = error {
				XCTAssertEqual(uid, "/Path/To/Not/existed.file", "Check returned correct uid in error info")
				XCTAssertEqual(url, "/Path/To/Not/existed.file", "Check returned correct url in error info")
			} else {
				XCTFail("Incorrect error returned")
			}
			
			errorExpectation.fulfill()
			
			}.subscribe().addDisposableTo(bag)
		waitForExpectationsWithTimeout(1, handler: nil)
	}
	
	func testCorrectCreateAndDisposeDownloadObservable() {
		let session = FakeSession()
		let httpClient = HttpClient(session: session)
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel underlying task")
		
		let resumeActions = {
			let fakeUrlEvents = [
				SessionDataEvents.didReceiveResponse(session: session,
					dataTask: session.task,
					response: self.defaultFakeResponse,
					completion: { _ in }),
				SessionDataEvents.didReceiveData(session: session, dataTask: session.task, data: NSData()),
				SessionDataEvents.didCompleteWithError(session: session, dataTask: session.task, error: nil)
			]
			
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { _ in
				for event in fakeUrlEvents {
					// send events to session observer (simulates NSURLSession behavior)
					httpClient.sessionObserver.sessionEventsSubject.onNext(event)
					// simulate delay
					NSThread.sleepForTimeInterval(0.005)
				}
			}
		}
		
		session.task = FakeDataTask(resumeClosure: resumeActions, cancelClosure: { downloadTaskCancelationExpectation.fulfill() })

		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		let successExpectation = expectationWithDescription("Should receive success message")
		let cacheDataExpectation = expectationWithDescription("Should receive cache data event")
		manager.createDownloadObservable("https://test.com", priority: .Normal).bindNext { e in
			if case StreamTaskEvents.Success = e {
				successExpectation.fulfill()
			} else if case StreamTaskEvents.CacheData(_) = e {
				XCTAssertEqual(1, manager.pendingTasks.count, "Task should be in pending task during processing")
				cacheDataExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertEqual(0, manager.pendingTasks.count, "Should remove task from pending")
	}
	
	func testCorrectCreateAndDisposeDownloadObservableWhenReceiveError() {
		let session = FakeSession()
		let httpClient = HttpClient(session: session)
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel underlying task")
		
		let resumeActions = {
			let fakeUrlEvents = [
				SessionDataEvents.didReceiveResponse(session: session,
					dataTask: session.task,
					response: self.defaultFakeResponse,
					completion: { _ in }),
				SessionDataEvents.didReceiveData(session: session, dataTask: session.task, data: NSData()),
				SessionDataEvents.didCompleteWithError(session: session, dataTask: session.task, error: NSError(domain: "DownloadManagerTests", code: 15, userInfo: nil))
			]
			
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { _ in
				for event in fakeUrlEvents {
					// send events to session observer (simulates NSURLSession behavior)
					httpClient.sessionObserver.sessionEventsSubject.onNext(event)
					// simulate delay
					NSThread.sleepForTimeInterval(0.005)
				}
			}
		}
		
		session.task = FakeDataTask(resumeClosure: resumeActions, cancelClosure: { downloadTaskCancelationExpectation.fulfill() })
		
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		let errorExpectation = expectationWithDescription("Should receive error message")
		manager.createDownloadObservable("https://test.com", priority: .Normal).doOnError { errorType in
			let error = errorType as NSError
			XCTAssertEqual(15, error.code, "Check receive error with correct code")
			errorExpectation.fulfill()
			}.subscribe().addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertEqual(0, manager.pendingTasks.count, "Should remove task from pending")
	}
	
	func testSaveData() {
		let provider = MemoryCacheProvider(uid: NSUUID().UUIDString, contentMimeType: "audio/mpeg")
		let saveData = "some data".dataUsingEncoding(NSUTF8StringEncoding)!
		provider.appendData(saveData)
		let manager = DownloadManager(saveData: true, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let file = manager.saveData(provider)
		if let file = file, restoredData = NSData(contentsOfURL: file) {
			XCTAssertTrue(restoredData.isEqualToData(saveData), "Check saved data equal to cached data")
		} else {
			XCTFail("Failed to restore saved data")
		}
		file?.deleteFile()
	}
	
	func testNotSaveData() {
		let provider = MemoryCacheProvider(uid: NSUUID().UUIDString, contentMimeType: "audio/mpeg")
		let saveData = "some data".dataUsingEncoding(NSUTF8StringEncoding)!
		provider.appendData(saveData)
		// create manager and set saveData to false
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let file = manager.saveData(provider)
		XCTAssertNil(file, "Should not return saved file")
	}
	
	func testCacheCorrectDataIfHasMoreThanOneObservers() {
		let session = FakeSession()
		let httpClient = HttpClient(session: session)
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel underlying task")
		
		let resumeActions = {
			let fakeUrlEvents = [
				SessionDataEvents.didReceiveResponse(session: session,
					dataTask: session.task,
					response: self.defaultFakeResponse,
					completion: { _ in }),
				SessionDataEvents.didReceiveData(session: session, dataTask: session.task, data: "first".dataUsingEncoding(NSUTF8StringEncoding)!),
				SessionDataEvents.didReceiveData(session: session, dataTask: session.task, data: "second".dataUsingEncoding(NSUTF8StringEncoding)!),
				SessionDataEvents.didReceiveData(session: session, dataTask: session.task, data: "third".dataUsingEncoding(NSUTF8StringEncoding)!),
				SessionDataEvents.didReceiveData(session: session, dataTask: session.task, data: "fourth".dataUsingEncoding(NSUTF8StringEncoding)!),
				SessionDataEvents.didCompleteWithError(session: session, dataTask: session.task, error: nil)
			]
			
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { _ in
				for event in fakeUrlEvents {
					// send events to session observer (simulates NSURLSession behavior)
					httpClient.sessionObserver.sessionEventsSubject.onNext(event)
					// simulate delay
					NSThread.sleepForTimeInterval(0.005)
				}
			}
		}
		
		session.task = FakeDataTask(resumeClosure: resumeActions, cancelClosure: { downloadTaskCancelationExpectation.fulfill() })
		
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		// first subscription
		let successExpectation = expectationWithDescription("Should receive success message")
		var cacheDataExpectation: XCTestExpectation? = expectationWithDescription("Should receive CacheData event for first subscription")
		manager.createDownloadObservable("https://test.com", priority: .Normal).bindNext { e in
			if case StreamTaskEvents.Success(let cacheProvider) = e {
				XCTAssertEqual(true, cacheProvider?.getCurrentData().isEqualToData("firstsecondthirdfourth".dataUsingEncoding(NSUTF8StringEncoding)!))
				successExpectation.fulfill()
			} else if case StreamTaskEvents.CacheData = e {
				XCTAssertEqual(1, manager.pendingTasks.count, "Should add only one task to pending")
				cacheDataExpectation?.fulfill()
				cacheDataExpectation = nil
			}
			}.addDisposableTo(bag)
		
		// second subscription
		let successSecondObservableExpectation = expectationWithDescription("Should receive success message")
		var cacheDataSecondExpectation: XCTestExpectation? = expectationWithDescription("Should receive CacheData event for second subscription")
		manager.createDownloadObservable("https://test.com", priority: .Normal).bindNext { e in
			if case StreamTaskEvents.Success(let cacheProvider) = e {
				XCTAssertEqual(true, cacheProvider?.getCurrentData().isEqualToData("firstsecondthirdfourth".dataUsingEncoding(NSUTF8StringEncoding)!))
				successSecondObservableExpectation.fulfill()
			} else if case StreamTaskEvents.CacheData = e {
				XCTAssertEqual(1, manager.pendingTasks.count, "Should add only one task to pending")
				cacheDataSecondExpectation?.fulfill()
				cacheDataSecondExpectation = nil
			}
			}.addDisposableTo(bag)
		
		
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertEqual(0, manager.pendingTasks.count, "Should remove task from pending")
		XCTAssertEqual(1, session.task?.resumeInvokeCount, "Should invoke resume on DataTask only once")
	}
	
	func testCancelTaskWhenObservableDisposing() {
		let taskResumedExpectation = expectationWithDescription("Should start task")
		let session = FakeSession(dataTask: FakeDataTask(resumeClosure: { taskResumedExpectation.fulfill() }))
		let httpClient = HttpClient(session: session)
		
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		
		let disposable = manager.createDownloadObservable("http://test.com", priority: .Normal).subscribe()
		//NSThread.sleepForTimeInterval(0.2)
		waitForExpectationsWithTimeout(1, handler: nil)
		XCTAssertEqual(1, manager.pendingTasks.count)
		XCTAssertEqual(true, manager.pendingTasks.first?.1.task.resumed)
		disposable.dispose()
		NSThread.sleepForTimeInterval(0.2)
		
		XCTAssertEqual(0, manager.pendingTasks.count, "Check remove task from pending")
		XCTAssertEqual(true, session.task?.isCancelled, "Check underlying task canceled")
	}
	
	func testCancelTaskOnlyAfterLastObservableDisposed() {
		let session = FakeSession(dataTask: FakeDataTask(resumeClosure: { _ in}))
		
		let manager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: HttpClient(session: session))
		
		let firstObservable = manager.createDownloadObservable("http://test.com", priority: .Normal).subscribe()
		let secondObservable = manager.createDownloadObservable("http://test.com", priority: .Normal).subscribe()
		let thirdObservable = manager.createDownloadObservable("http://test.com", priority: .Normal).subscribe()
		
		NSThread.sleepForTimeInterval(0.2)
		
		XCTAssertEqual(1, manager.pendingTasks.count, "Check add task to pending")
		
		firstObservable.dispose()
		NSThread.sleepForTimeInterval(0.2)
		
		XCTAssertEqual(1, manager.pendingTasks.count, "Check still has task in pending")
		XCTAssertEqual(false, session.task?.isCancelled, "Check underlying task not canceled")
		
		secondObservable.dispose()
		NSThread.sleepForTimeInterval(0.2)
		
		XCTAssertEqual(1, manager.pendingTasks.count, "Check still has task in pending")
		XCTAssertEqual(false, session.task?.isCancelled, "Check underlying task not canceled")
		
		thirdObservable.dispose()
		NSThread.sleepForTimeInterval(0.2)
		
		XCTAssertEqual(0, manager.pendingTasks.count, "Check remove task from pending")
		XCTAssertEqual(true, session.task?.isCancelled, "Check underlying task canceled")
	}
	
	func testNotStartNewTaskWhenHaveAnotherPendingTask() {
		let session = FakeSession(dataTask: FakeDataTask(resumeClosure: { _ in}))
		
		let httpClient = HttpClient(session: session)
		
		let manager = DownloadManager(saveData: false,
		                              fileStorage: LocalNsUserDefaultsStorage(),
		                              httpClient: httpClient,
		                              simultaneousTasksCount: 1,
		                              runningTaskCheckTimeout: 1)
		
		// create task, start it and add to pending tasks
		let runningTask = StreamDataTask(taskUid: "http://test.com",
		                                 dataTask: session.task!,
		                                 httpClient: httpClient,
		                                 sessionEvents: httpClient.sessionObserver.sessionEvents,
		                                 cacheProvider: nil)
		runningTask.resume()
		manager.pendingTasks[runningTask.uid] = PendingTask(task: runningTask)
		
		// create another task and add to pendings too
		let newTask = StreamDataTask(taskUid: "http://test2.com",
		                             dataTask: session.task!,
		                             httpClient: httpClient,
		                             sessionEvents: httpClient.sessionObserver.sessionEvents,
		                             cacheProvider: nil)
		manager.pendingTasks[newTask.uid] = PendingTask(task: newTask)
		
		// create PublishSubject, that will simutale task check interval
		let interval = PublishSubject<Int>()
		// start monitoring of second task
		manager.monitorTask(newTask.uid, monitoringInterval: interval).subscribe().addDisposableTo(bag)
		
		XCTAssertEqual(false, newTask.resumed, "Check new task not started")
		interval.onNext(1)
		NSThread.sleepForTimeInterval(0.2)
		XCTAssertEqual(false, newTask.resumed, "Check new task not started after monitoring tick")
		
		interval.onNext(1)
		NSThread.sleepForTimeInterval(0.2)
		XCTAssertEqual(false, newTask.resumed, "Check new task not started after monitoring tick")
		
		// cancel current task
		runningTask.cancel()
		interval.onNext(1)
		NSThread.sleepForTimeInterval(0.2)
		XCTAssertEqual(true, newTask.resumed, "Check new task started after completion of previous task")
	}
}
