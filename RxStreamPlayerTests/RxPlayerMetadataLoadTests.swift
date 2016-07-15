import XCTest
@testable import RxStreamPlayer
@testable import RxHttpClient
import AVFoundation
import RxSwift
import RealmSwift

class RxPlayerMetadataLoadTests: XCTestCase {
	let bag = DisposeBag()
	
	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
		Realm.Configuration.defaultConfiguration.inMemoryIdentifier = self.name
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}
	
	func createFileWithChunkData(file: NSURL, destinationDirectory: NSURL, location: Int, length: Int) -> NSURL {
		let rawData = NSData(contentsOfURL: file)!
		let subDataRaw = NSData(data: rawData.subdataWithRange(NSRange(location: location, length: length)))
		
		let subDataFile = destinationDirectory.URLByAppendingPathComponent("\(NSUUID().UUIDString).\(file.lastPathComponent ?? "dat")")
		subDataRaw.writeToURL(subDataFile, atomically: true)
		
		return subDataFile
	}
	
	func testLoadMetadataFromFile() {
		let metadataFile = NSURL(fileURLWithPath: NSBundle(forClass: RxPlayerMetadataLoadTests.self).pathForResource("MetadataTest", ofType: "mp3")!)
		let tempDir = NSFileManager.getOrCreateSubDirectory(NSFileManager.documentsDirectory, subDirName: NSUUID().UUIDString)!
		let subDataFile = createFileWithChunkData(metadataFile, destinationDirectory: tempDir, location: 0, length: 1024 * 220)
		
		let player = RxPlayer()
		let item = player.addLast("http://testitem.com")
		let metadata = player.loadFileMetadata(item.streamIdentifier, file: subDataFile, utilities: StreamPlayerUtilities())
		XCTAssertEqual(metadata?.album, "Of Her")
		XCTAssertEqual(metadata?.artist, "Yusuke Tsutsumi")
		XCTAssertEqual(metadata?.duration?.asTimeString, "04: 27")
		XCTAssertEqual(metadata?.title, "Love")
		XCTAssertNotNil(metadata?.artwork)
		
		tempDir.deleteFile()
	}
	
	func testLoadMetadataFromFile2() {
		let metadataFile = NSURL(fileURLWithPath: NSBundle(forClass: RxPlayerMetadataLoadTests.self).pathForResource("MetadataTest2", ofType: "mp3")!)
		let tempDir = NSFileManager.getOrCreateSubDirectory(NSFileManager.documentsDirectory, subDirName: NSUUID().UUIDString)!
		let subDataFile = createFileWithChunkData(metadataFile, destinationDirectory: tempDir, location: 0, length: 1024 * 5)
		
		let player = RxPlayer()
		let item = player.addLast("http://testitem.com")
		let metadata = player.loadFileMetadata(item.streamIdentifier, file: subDataFile, utilities: StreamPlayerUtilities())
		XCTAssertEqual(metadata?.album, "Red Dust & Spanish Lace")
		XCTAssertEqual(metadata?.artist, "Acoustic Alchemy")
		// in this case AVURLAsset can't provide information about duration
		XCTAssertEqual(metadata?.duration?.asTimeString, "00: 00")
		XCTAssertEqual(metadata?.title, "Mr. Chow")
		XCTAssertNil(metadata?.artwork)
		
		tempDir.deleteFile()
	}
	
	func testNotLoadMetadataFromNotExistedFile() {
		let player = RxPlayer()
		let item = player.addLast("https://testitem.com")
		XCTAssertNil(player.loadFileMetadata(item.streamIdentifier, file: NSURL(fileURLWithPath: "/Documents/File.mp3"), utilities: StreamPlayerUtilities()), "Should not return metadata")
	}
	
	func testLoadMetadataFromCachedFile() {
		let storage = LocalNsUserDefaultsStorage()
		let metadataFile = NSURL(fileURLWithPath: NSBundle(forClass: RxPlayerMetadataLoadTests.self).pathForResource("MetadataTest", ofType: "mp3")!)
		let copiedFile = storage.tempStorageDirectory.URLByAppendingPathComponent("FileWithMetadata.mp3")
		let _ = try? NSFileManager.defaultManager().copyItemAtURL(metadataFile, toURL: copiedFile)
		storage.tempStorageDictionary["https://testitem.com"] = copiedFile.lastPathComponent
		
		let downloadManager = DownloadManager(saveData: false, fileStorage: storage, httpUtilities: FakeHttpUtilities())
		
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let item = player.addLast("https://testitem.com")
		
		let metadataLoadExpectation = expectationWithDescription("Should load metadta from local file")
		
		player.loadMetadata(item.streamIdentifier, downloadManager: downloadManager, utilities: StreamPlayerUtilities()).bindNext { result in
			guard case Result.success(let box) = result else { return }
			let metadata = box.value
			XCTAssertEqual(metadata?.album, "Of Her")
			XCTAssertEqual(metadata?.artist, "Yusuke Tsutsumi")
			XCTAssertEqual(metadata?.duration?.asTimeString, "04: 27")
			XCTAssertEqual(metadata?.title, "Love")
			XCTAssertNotNil(metadata?.artwork)
			
			metadataLoadExpectation.fulfill()
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		copiedFile.deleteFile()
	}
	
	func testReceiveErrorWhileLoadMetadata() {
		let storage = LocalNsUserDefaultsStorage()
		
		let streamObserver = NSURLSessionDataEventsObserver()
		let httpUtilities = FakeHttpUtilities()
		httpUtilities.streamObserver = streamObserver
		let session = FakeSession(fakeTask: FakeDataTask(completion: nil))
		httpUtilities.fakeSession = session
		let downloadManager = DownloadManager(saveData: false, fileStorage: storage, httpUtilities: httpUtilities)
		
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let item = player.addLast("https://testitem.com")
		
		let metadataLoadExpectation = expectationWithDescription("Should load metadta from local file")
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel task")
		
		// simulate http request failure and send error
		session.task?.taskProgress.bindNext { e in
			if case FakeDataTaskMethods.resume(let tsk) = e {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
					streamObserver.sessionEventsSubject.onNext(.didCompleteWithError(session: session, dataTask: tsk,
						error: NSError(domain: "HttpRequestTests", code: 17, userInfo: nil)))
				}
			} else if case FakeDataTaskMethods.cancel = e {
				downloadTaskCancelationExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		player.loadMetadata(item.streamIdentifier, downloadManager: downloadManager, utilities: StreamPlayerUtilities()).bindNext { result in
			guard case Result.error(let error) = result else { return }
			//guard case Result.error(let errorType) = result else { return }
			//let error = errorType as NSError
			if (error as NSError).code == 17 {
				metadataLoadExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(1, handler: nil)
	}
	
	func testReturnMetadataFromRemote() {
		let storage = LocalNsUserDefaultsStorage()
		
		let streamObserver = NSURLSessionDataEventsObserver()
		let httpUtilities = FakeHttpUtilities()
		httpUtilities.streamObserver = streamObserver
		let session = FakeSession(fakeTask: FakeDataTask(completion: nil))
		httpUtilities.fakeSession = session
		let downloadManager = DownloadManager(saveData: false, fileStorage: storage, httpUtilities: httpUtilities)
		
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let item = player.addLast("https://testitem.com")
		
		let metadataLoadExpectation = expectationWithDescription("Should load metadta from remote")
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel task")
		
		// simulate http request 
		session.task?.taskProgress.bindNext { e in
			if case FakeDataTaskMethods.resume(let tsk) = e {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
					let response = FakeResponse(contentLenght: 1024 * 256)
					response.MIMEType = "audio/mpeg"
					streamObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: session, dataTask: tsk,
						response: response, completion: { _ in }))
					
					guard let data = NSData(contentsOfURL:
						NSURL(fileURLWithPath: NSBundle(forClass: RxPlayerMetadataLoadTests.self).pathForResource("MetadataTest", ofType: "mp3")!)) else {
							return
					}
					
					streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: session, dataTask: tsk, data: data))
				}
			} else if case FakeDataTaskMethods.cancel = e {
				downloadTaskCancelationExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		player.loadMetadata(item.streamIdentifier, downloadManager: downloadManager, utilities: StreamPlayerUtilities()).bindNext { result in
			guard case Result.success(let box) = result else { return }
			let metadata = box.value
			XCTAssertEqual(metadata?.album, "Of Her")
			XCTAssertEqual(metadata?.artist, "Yusuke Tsutsumi")
			XCTAssertEqual(metadata?.duration?.asTimeString, "04: 27")
			XCTAssertEqual(metadata?.title, "Love")
			XCTAssertNotNil(metadata?.artwork)
			
			metadataLoadExpectation.fulfill()
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(2, handler: nil)
		
		// check if metadata correctly saved in media library
		let track = try! player.mediaLibrary.getTrackByUid(item.streamIdentifier.streamResourceUid)
		XCTAssertEqual(track?.album.name, "Of Her")
		XCTAssertEqual(track?.artist.name, "Yusuke Tsutsumi")
		XCTAssertEqual(track?.duration.asTimeString, "04: 27")
		XCTAssertEqual(track?.title, "Love")
		XCTAssertNotNil(track?.album.artwork)
	}
	
	/// This test send one data chunk that is greather than maximum allowed limit by player.
	/// And this test should test that even in this situation player will correctly infer duration of track
	func testReturnMetadataFromRemoteAndCorrectlyInferDurationWhenOneChunkSended() {
		let metadataFile = NSURL(fileURLWithPath: NSBundle(forClass: RxPlayerMetadataLoadTests.self).pathForResource("MetadataTest2", ofType: "mp3")!)
		let metadataRawData = NSData(contentsOfURL: metadataFile)!
		
		let storage = LocalNsUserDefaultsStorage()
		let streamObserver = NSURLSessionDataEventsObserver()
		let httpUtilities = FakeHttpUtilities()
		httpUtilities.streamObserver = streamObserver
		let session = FakeSession(fakeTask: FakeDataTask(completion: nil))
		httpUtilities.fakeSession = session
		let downloadManager = DownloadManager(saveData: false, fileStorage: storage, httpUtilities: httpUtilities)
		
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let item = player.addLast("https://testitem.com")
		
		let metadataLoadExpectation = expectationWithDescription("Should load metadta from remote")
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel task")
		
		// simulate http request
		session.task?.taskProgress.bindNext { e in
			if case FakeDataTaskMethods.resume(let tsk) = e {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
					let response = FakeResponse(contentLenght: Int64(metadataRawData.length))
					response.MIMEType = "audio/mpeg"
					streamObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: session, dataTask: tsk,
						response: response, completion: { _ in }))
					
					// return data chunk greather than maximum allowed by player
					let dataToSend = metadataRawData.subdataWithRange(NSRange(location: 0, length: Int(player.matadataMaximumLoadLength) + 1))
					streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: session, dataTask: tsk, data: dataToSend))
				}
			} else if case FakeDataTaskMethods.cancel = e {
				downloadTaskCancelationExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		player.loadMetadata(item.streamIdentifier, downloadManager: downloadManager, utilities: StreamPlayerUtilities()).bindNext { result in
			guard case Result.success(let box) = result else { return }
			let metadata = box.value
			XCTAssertEqual(metadata?.album, "Red Dust & Spanish Lace")
			XCTAssertEqual(metadata?.artist, "Acoustic Alchemy")
			XCTAssertEqual(metadata?.duration?.asTimeString, "03: 08")
			XCTAssertEqual(metadata?.title, "Mr. Chow")
			XCTAssertNil(metadata?.artwork)
			
			metadataLoadExpectation.fulfill()
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(2, handler: nil)
	}
	
	/// This test send one data chunk that is greather than maximum allowed limit by player, and and after that continues to send data.
	/// And this test should test that even in this situation player will correctly infer duration of track
	func testReturnMetadataFromRemoteAndCorrectlyInferDurationWhenFirstBigChunkSended() {
		let metadataFile = NSURL(fileURLWithPath: NSBundle(forClass: RxPlayerMetadataLoadTests.self).pathForResource("MetadataTest2", ofType: "mp3")!)
		let metadataRawData = NSData(contentsOfURL: metadataFile)!
		
		let storage = LocalNsUserDefaultsStorage()
		let streamObserver = NSURLSessionDataEventsObserver()
		let httpUtilities = FakeHttpUtilities()
		httpUtilities.streamObserver = streamObserver
		let session = FakeSession(fakeTask: FakeDataTask(completion: nil))
		httpUtilities.fakeSession = session
		let downloadManager = DownloadManager(saveData: false, fileStorage: storage, httpUtilities: httpUtilities)
		
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let item = player.addLast("https://testitem.com")
		
		let metadataLoadExpectation = expectationWithDescription("Should load metadta from remote")
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel task")
		
		var canceled = false
		var sendedDataLength = 0
		
		// simulate http request
		session.task?.taskProgress.bindNext { e in
			if case FakeDataTaskMethods.resume(let tsk) = e {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
					let response = FakeResponse(contentLenght: Int64(metadataRawData.length))
					response.MIMEType = "audio/mpeg"
					streamObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: session, dataTask: tsk,
						response: response, completion: { _ in }))
					
					var currentOffset = 0
					let sendDataChunk = Int(player.matadataMaximumLoadLength) + 1
					while !canceled {
						if metadataRawData.length - currentOffset > sendDataChunk {
							let range = NSMakeRange(currentOffset, sendDataChunk)
							currentOffset += sendDataChunk
							sendedDataLength = currentOffset
							let subdata = metadataRawData.subdataWithRange(range)
							dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
								streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: session, dataTask: tsk, data: subdata))
							}
							NSThread.sleepForTimeInterval(0.00002)
						} else {
							let range = NSMakeRange(currentOffset, metadataRawData.length - currentOffset)
							let subdata = metadataRawData.subdataWithRange(range)
							sendedDataLength = metadataRawData.length
							dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
								streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: session, dataTask: tsk, data: subdata))
							}
							break
						}
					}
					
				}
			} else if case FakeDataTaskMethods.cancel = e {
				downloadTaskCancelationExpectation.fulfill()
				canceled = true
			}
			}.addDisposableTo(bag)
		
		player.loadMetadata(item.streamIdentifier, downloadManager: downloadManager, utilities: StreamPlayerUtilities()).bindNext { result in
			guard case Result.success(let box) = result else { return }
			let metadata = box.value
			XCTAssertEqual(metadata?.album, "Red Dust & Spanish Lace")
			XCTAssertEqual(metadata?.artist, "Acoustic Alchemy")
			XCTAssertEqual(metadata?.duration?.asTimeString, "03: 08")
			XCTAssertEqual(metadata?.title, "Mr. Chow")
			XCTAssertNil(metadata?.artwork)
			
			metadataLoadExpectation.fulfill()
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(2, handler: nil)
		
		XCTAssertNotEqual(sendedDataLength, metadataRawData.length)
	}
	
	func testLoadChunkedMetadataFromRemote() {
		let metadataFile = NSURL(fileURLWithPath: NSBundle(forClass: RxPlayerMetadataLoadTests.self).pathForResource("MetadataTest2", ofType: "mp3")!)
		let metadataRawData = NSData(contentsOfURL: metadataFile)!
		
		let storage = LocalNsUserDefaultsStorage()
		let streamObserver = NSURLSessionDataEventsObserver()
		let httpUtilities = FakeHttpUtilities()
		httpUtilities.streamObserver = streamObserver
		let session = FakeSession(fakeTask: FakeDataTask(completion: nil))
		httpUtilities.fakeSession = session
		let downloadManager = DownloadManager(saveData: false, fileStorage: storage, httpUtilities: httpUtilities)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		let item = player.addLast("https://testitem.com")
		
		let metadataLoadExpectation = expectationWithDescription("Should load metadta from remote")
		let downloadTaskCancelationExpectation = expectationWithDescription("Should cancel task")
		
		var canceled = false
		var sendedDataLength = 0
		
		// simulate http request
		session.task?.taskProgress.observeOn(SerialDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility)).bindNext { e in
			if case FakeDataTaskMethods.resume(let tsk) = e {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
					let response = FakeResponse(contentLenght: Int64(metadataRawData.length))
					response.MIMEType = "audio/mpeg"
					streamObserver.sessionEventsSubject.onNext(.didReceiveResponse(session: session, dataTask: tsk,
						response: response, completion: { _ in }))
					
					var currentOffset = 0
					let sendDataChunk = 1024 * 5
					while !canceled {
						if metadataRawData.length - currentOffset > sendDataChunk {
							let range = NSMakeRange(currentOffset, sendDataChunk)
							currentOffset += sendDataChunk
							sendedDataLength = currentOffset
							let subdata = metadataRawData.subdataWithRange(range)
							dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
								streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: session, dataTask: tsk, data: subdata))
							}
							NSThread.sleepForTimeInterval(0.005)
						} else {
							let range = NSMakeRange(currentOffset, metadataRawData.length - currentOffset)
							let subdata = metadataRawData.subdataWithRange(range)
							sendedDataLength = metadataRawData.length
							dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
								streamObserver.sessionEventsSubject.onNext(.didReceiveData(session: session, dataTask: tsk, data: subdata))
							}
							break
						}
					}
				}
			} else if case FakeDataTaskMethods.cancel = e {
				downloadTaskCancelationExpectation.fulfill()
				canceled = true
			}
			}.addDisposableTo(bag)
		
		player.loadMetadata(item.streamIdentifier, downloadManager: downloadManager, utilities: StreamPlayerUtilities()).bindNext { result in
			guard case Result.success(let box) = result else { return }
			let metadata = box.value
			XCTAssertEqual(metadata?.album, "Red Dust & Spanish Lace")
			XCTAssertEqual(metadata?.artist, "Acoustic Alchemy")
			XCTAssertEqual(metadata?.duration?.asTimeString, "03: 08")
			XCTAssertEqual(metadata?.title, "Mr. Chow")
			XCTAssertNil(metadata?.artwork)
			
			metadataLoadExpectation.fulfill()
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(4, handler: nil)
		
		XCTAssertTrue(sendedDataLength <= Int(Double(player.matadataMaximumLoadLength) * 1.05), "Check sended less data than was set as maximum limit for metadata gequests")
		
		// check if metadata correctly saved in media library
		let track = try! player.mediaLibrary.getTrackByUid(item.streamIdentifier.streamResourceUid)
		XCTAssertEqual(track?.album.name, "Red Dust & Spanish Lace")
		XCTAssertEqual(track?.artist.name, "Acoustic Alchemy")
		XCTAssertEqual(track?.duration.asTimeString, "03: 08")
		XCTAssertEqual(track?.title, "Mr. Chow")
		XCTAssertNil(track?.album.artwork)
	}
		
	func testReturnErrorForItemWithUnknownScheme() {
		let storage = LocalNsUserDefaultsStorage()
		let downloadManager = DownloadManager(saveData: false, fileStorage: storage, httpUtilities: HttpUtilities())

		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let item = player.addLast("wrong://testitem.com")
		
		let metadataLoadExpectation = expectationWithDescription("Should not load metadata for incorrect scheme")
		
		player.loadMetadata(item.streamIdentifier, downloadManager: downloadManager, utilities: StreamPlayerUtilities()).bindNext { result in
			guard case Result.error(let error) = result else { return }
			guard case DownloadManagerErrors.unsupportedUrlSchemeOrFileNotExists(_, let uid) = error else { XCTFail("Should return correct error"); return }
			XCTAssertEqual("wrong://testitem.com", uid)
			metadataLoadExpectation.fulfill()
		}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(1, handler: nil)
	}
}
