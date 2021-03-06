import XCTest
import RxSwift
@testable import RxStreamPlayer
@testable import RxHttpClient
import RealmSwift

class RxPlayerPlayControlsTests: XCTestCase {
	let bag = DisposeBag()
	let httpClient = HttpClient(session: FakeSession(dataTask: FakeDataTask(resumeClosure: { _ in })))
	
	override func setUp() {
		super.setUp()
		// Put setup code here. This method is called before the invocation of each test method in the class.
		Realm.Configuration.defaultConfiguration.inMemoryIdentifier = self.name
	}
	
	override func tearDown() {
		// Put teardown code here. This method is called after the invocation of each test method in the class.
		super.tearDown()
	}
	
	func testCurrentItemObservableReturnNilForNewPlayer() {
		let player = RxPlayer()
		
		let currentItemChangeExpectation = expectationWithDescription("Should send current item")
		player.currentItem.bindNext { item in
			XCTAssertNil(item, "Should return nil")
			currentItemChangeExpectation.fulfill()
			}.addDisposableTo(bag)
		
		waitForExpectationsWithTimeout(1, handler: nil)
	}
	
	func testStartPlaying() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		XCTAssertFalse(player.playing, "Playing property should be false")
		
		let preparingExpectation = expectationWithDescription("Should rise PreparingToPlay event")
		let playStartedExpectation = expectationWithDescription("Should invoke Start on internal player")
		let currentItemChangeExpectation = expectationWithDescription("Should change current item")
		
		let playingItem = "https://test.com/track1.mp3"
		player.playerEvents.bindNext { e in
			if case PlayerEvents.PreparingToPlay(let item) = e {
				XCTAssertEqual(playingItem.streamResourceUid, item.streamIdentifier.streamResourceUid, "Check correct item preparing to play")
				preparingExpectation.fulfill()
			} else if case PlayerEvents.Started = e {
				playStartedExpectation.fulfill()
			}
		}.addDisposableTo(bag)
		
		player.currentItem.filter { $0 != nil }.bindNext { item in
			XCTAssertEqual(playingItem.streamResourceUid, item?.streamIdentifier.streamResourceUid, "Check correct item send as new current item")
			currentItemChangeExpectation.fulfill()
		}.addDisposableTo(bag)
		
		player.play(playingItem)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertTrue(player.playing, "Playing property should be true")
	}
	
	func testPausing() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let pausingExpectation = expectationWithDescription("Should rise Pausing event")
		let pausedExpectation = expectationWithDescription("Should invoke Pause on internal player")
		
		let playingItem = "https://test.com/track1.mp3"
		player.playerEvents.bindNext { e in
			if case PlayerEvents.Pausing(let item) = e {
				XCTAssertEqual(playingItem.streamResourceUid, item.streamIdentifier.streamResourceUid)
				pausingExpectation.fulfill()
			} else if case PlayerEvents.Paused = e {
				pausedExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		player.play(playingItem)
		player.pause()
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertFalse(player.playing, "Playing property should be false")
	}
	
	func testResuming() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		// set fake native player instance,
		// so RxPlayer will think, that player paused and will invoke resume method
		(player.internalPlayer as! FakeInternalPlayer).nativePlayer = FakeNativePlayer()
		
		let resumingExpectation = expectationWithDescription("Should rise Resuming event")
		let resumedExpectation = expectationWithDescription("Should invoke Resume on internal player")
		
		let playingItem = "https://test.com/track1.mp3"
		player.playerEvents.bindNext { e in
			if case PlayerEvents.Resuming(let item) = e {
				XCTAssertEqual(playingItem.streamResourceUid, item.streamIdentifier.streamResourceUid)
				resumingExpectation.fulfill()
			} else if case PlayerEvents.Resumed = e {
				resumedExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		player.play(playingItem)
		player.pause()
		player.resume()
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertTrue(player.playing, "Playing property should be true")
	}
	
	func testResumingWhenNativePlayerIsNil() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		player.initWithNewItems(["https://test.com/track1.mp3", "https://test.com/track2.mp3", "https://test.com/track3.mp3"])
		let playingItem = player.first!.streamIdentifier
		// set current item
		player.current = player.first
		
		let resumingExpectation = expectationWithDescription("Should rise Resuming event")
		let startedExpectation = expectationWithDescription("Should invoke Play on internal player")
		let preparingToPlayExpectation = expectationWithDescription("Should rise PreparingToPlay event")
		
		player.playerEvents.bindNext { e in
			if case PlayerEvents.Resuming(let item) = e {
				XCTAssertEqual(playingItem.streamResourceUid, item.streamIdentifier.streamResourceUid)
				resumingExpectation.fulfill()
			} else if case PlayerEvents.Started = e {
				startedExpectation.fulfill()
			} else if case PlayerEvents.PreparingToPlay(let preparingItem) = e {
				XCTAssertEqual(preparingItem.streamIdentifier.streamResourceUid, playingItem.streamResourceUid)
				preparingToPlayExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		player.resume()
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertTrue(player.playing, "Playing property should be true")
	}
	
	func testStopping() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let stoppingExpectation = expectationWithDescription("Should rise Stopping event")
		let stoppedExpectation = expectationWithDescription("Should invoke Stopped on internal player")
		
		let playingItem = "https://test.com/track1.mp3"
		player.playerEvents.bindNext { e in
			if case PlayerEvents.Stopping(let item) = e {
				XCTAssertEqual(playingItem.streamResourceUid, item.streamIdentifier.streamResourceUid)
				stoppingExpectation.fulfill()
			} else if case PlayerEvents.Stopped = e {
				stoppedExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		
		player.play(playingItem)
		
		player.stop()
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertFalse(player.playing, "Playing property should be false")
		XCTAssertNotNil(player.current)
	}
	
	func testNotResumeWhenCurrentIsNil() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let playingItem = "https://test.com/track1.mp3"
		
		player.initWithNewItems([playingItem])
		
		player.playerEvents.skip(1).bindNext { e in
			XCTFail("Should not rise any events while resuming")
		}.addDisposableTo(bag)
		
		player.resume()
		
		NSThread.sleepForTimeInterval(0.5)
		XCTAssertFalse(player.playing, "Playing property should be false")
	}
	
	func testForceResumeFromNextIfCurrentIsNil() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		
		let playingItems: [StreamResourceIdentifier] = ["https://test.com/track1.mp3", "https://test.com/track2.mp3", "https://test.com/track3.mp3"]
		player.initWithNewItems(playingItems)
		
		let preparingToPlayExpectation = expectationWithDescription("Should rise PrepareToPlay event")
		
		player.playerEvents.bindNext { e in
			if case PlayerEvents.PreparingToPlay(let item) = e {
				XCTAssertEqual(playingItems[0].streamResourceUid, item.streamIdentifier.streamResourceUid, "Should resume from first item")
				preparingToPlayExpectation.fulfill()
			}
		}.addDisposableTo(bag)
		
		player.resume(true)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertTrue(player.playing, "Playing property should be true")
	}
	
	func testPlayUrlAddNewItemToEndAndSetAsCurrent() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		player.initWithNewItems(["https://test.com/track1.mp3", "https://test.com/track2.mp3", "https://test.com/track3.mp3"])
		player.toNext()
		
		let preparingExpectation = expectationWithDescription("Should start play new item")
		let currentItemChangedExpectation = expectationWithDescription("Should change current item")
		
		let newItem = "https://test.com/track4.mp3"
		player.playerEvents.bindNext { e in
			if case PlayerEvents.PreparingToPlay(let item) = e {
				XCTAssertEqual(newItem.streamResourceUid, item.streamIdentifier.streamResourceUid, "Should start playing new item")
				preparingExpectation.fulfill()
			} else if case PlayerEvents.CurrentItemChanged(let changedItem) = e {
				XCTAssertEqual(newItem.streamResourceUid, changedItem?.streamIdentifier.streamResourceUid, "Should set new item as current")
				currentItemChangedExpectation.fulfill()
			}
		}.addDisposableTo(bag)
		
		player.play(newItem, clearQueue: false)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertEqual(4, player.count, "Should have 4 items in queue")
	}
	
	func testSwitchToNextAfterCurrentItemFinishesPlaying() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		player.initWithNewItems(["https://test.com/track1.mp3", "https://test.com/track2.mp3", "https://test.com/track3.mp3"])
		player.toNext()
		
		let expectation = expectationWithDescription("Should switch to next item")
		var skipped = false
		player.currentItem.bindNext { item in
			if !skipped { skipped = true }
			else {
				XCTAssertEqual(item?.streamIdentifier.streamResourceUid, "https://test.com/track2.mp3", "Check current item changed to next")
				expectation.fulfill()
			}
		}.addDisposableTo(bag)
		
		// send notification about finishing current item playing
		(player.internalPlayer as! FakeInternalPlayer).finishPlayingCurrentItem()
		
		waitForExpectationsWithTimeout(1, handler: nil)
		XCTAssertEqual(player.current?.streamIdentifier.streamResourceUid, "https://test.com/track2.mp3", "Check correct current item")
	}
	
	func testSwitchCurrentItemToNilAfterFinishing() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		player.initWithNewItems(["https://test.com/track1.mp3", "https://test.com/track2.mp3", "https://test.com/track3.mp3"])
		player.current = player.last
		
		let expectation = expectationWithDescription("Should switch to next item")
		var skipped = false
		player.currentItem.bindNext { item in
			if !skipped { skipped = true }
			else {
				XCTAssertNil(item, "Current item should be nil")
				expectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		let finishQueueExpectation = expectationWithDescription("Should rise FinishQueueEvent")
		player.playerEvents.bindNext { e in
			if case PlayerEvents.FinishPlayingQueue = e {
				finishQueueExpectation.fulfill()
			}
		}.addDisposableTo(bag)
		
		// send notification about finishing current item playing
		(player.internalPlayer as! FakeInternalPlayer).finishPlayingCurrentItem()
		
		waitForExpectationsWithTimeout(1, handler: nil)
		XCTAssertNil(player.current, "Current item should be nil")
	}
	
	func testRepeatQueue() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: true, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: FakeStreamPlayerUtilities())
		player.initWithNewItems(["https://test.com/track1.mp3", "https://test.com/track2.mp3", "https://test.com/track3.mp3"])
		player.current = player.last
		
		let expectation = expectationWithDescription("Should switch to next item")
		var skipped = false
		player.currentItem.bindNext { item in
			if !skipped { skipped = true }
			else {
				XCTAssertEqual(item?.streamIdentifier.streamResourceUid, "https://test.com/track1.mp3", "Current item should be first item in queue")
				expectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		let repeatQueueExpectation = expectationWithDescription("Should rise RepeatQueue event")
		player.playerEvents.bindNext { e in
			if case PlayerEvents.StartRepeatQueue = e {
				repeatQueueExpectation.fulfill()
			}
			}.addDisposableTo(bag)
		
		// send notification about finishing current item playing
		(player.internalPlayer as! FakeInternalPlayer).finishPlayingCurrentItem()
		
		waitForExpectationsWithTimeout(1, handler: nil)
		XCTAssertEqual(player.current?.streamIdentifier.streamResourceUid, player.first?.streamIdentifier.streamResourceUid, "Current item should be first")
	}
	
	func testSendErrorMessageIfTryingToPlayUnsupportedUrlScheme() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: StreamPlayerUtilities())
		
		let errorExpectation = expectationWithDescription("Should rise error")
		let correctCurrentItemExpectation = expectationWithDescription("Should switch to next item after error")
		player.playerEvents.bindNext { e in
				if case PlayerEvents.CurrentItemChanged(let newItem) = e {
					if newItem?.streamIdentifier.streamResourceUid == "https://test.com/track2.mp3" {
						correctCurrentItemExpectation.fulfill()
					}
			} else if case PlayerEvents.Error(let error) = e {
				if case DownloadManagerErrors.unsupportedUrlScheme(let url, let uid) = error {
					XCTAssertEqual("unsupported://test.com/track1.mp3", url)
					XCTAssertEqual("unsupported://test.com/track1.mp3", uid)
					errorExpectation.fulfill()
				}
			}
		}.addDisposableTo(bag)
		
		player.initWithNewItems(["unsupported://test.com/track1.mp3", "https://test.com/track2.mp3", "https://test.com/track3.mp3"])
		player.resume(true)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertEqual(player.current?.streamIdentifier.streamResourceUid, "https://test.com/track2.mp3", "Test correct current item")
	}
	
	func testSkipAllItemsIfAllUnsupported() {
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpClient: httpClient)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: StreamPlayerUtilities())
		
		let correctCurrentItemExpectation = expectationWithDescription("Should switch to nil after errors")
		player.playerEvents.bindNext { e in
			if case PlayerEvents.CurrentItemChanged(let newItem) = e {
				print(newItem?.streamIdentifier.streamResourceUid)
				if newItem == nil {
					correctCurrentItemExpectation.fulfill()
				}
			}
			}.addDisposableTo(bag)
		
		player.initWithNewItems(["unsupported://test.com/track1.mp3", "unsupported://test.com/track2.mp3", "fake://test.com/track3.mp3"])
		player.resume(true)
		
		waitForExpectationsWithTimeout(1, handler: nil)
		
		XCTAssertNil(player.current, "Should skip all items")
	}

	/*
	func testStartPlayingItemsFromMediaLibraryPlayList() {
		// setup fake http
		let streamObserver = NSURLSessionDataEventsObserver()
		let httpUtilities = FakeHttpUtilities()
		httpUtilities.streamObserver = streamObserver
		let session = FakeSession(fakeTask: FakeDataTask(completion: nil))
		httpUtilities.fakeSession = session
		let httpClient = HttpClient(httpUtilities: httpUtilities)
		
		session.task?.taskProgress.bindNext { e in
			if case FakeDataTaskMethods.resume(let tsk) = e {
				// send random url
				let json: JSON =  JSON(["href": "http://url.com"])
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
					//tsk.completion?(try? json.rawData(), nil, nil)
					session.sendData(tsk, data: try? json.rawData(), streamObserver: httpUtilities.streamObserver as! NSURLSessionDataEventsObserver)
				}
			}
		}.addDisposableTo(bag)
		
		
		// setup cloud resource db
		let realm = try! Realm()
		try! realm.write {
			realm.add(RealmCloudResource(uid: "disk://Music/Track1.mp3", rawData: JSON(["path": "disk://Music/Track1.mp3", "media_type": "audio"]).rawDataSafe()!,
				resourceTypeIdentifier: YandexDiskCloudJsonResource.typeIdentifier))
			realm.add(RealmCloudResource(uid: "disk://Music/Track2.mp3", rawData: JSON(["path": "disk://Music/Track2.mp3", "media_type": "audio"]).rawDataSafe()!,
				resourceTypeIdentifier: YandexDiskCloudJsonResource.typeIdentifier))
			realm.add(RealmCloudResource(uid: "disk://Music/Track3.mp3", rawData: JSON(["path": "disk://Music/Track3.mp3", "media_type": "audio"]).rawDataSafe()!,
				resourceTypeIdentifier: YandexDiskCloudJsonResource.typeIdentifier))
		}
		
		
		// setup media library db
		let lib = RealmMediaLibrary() as MediaLibraryType
		try!lib.saveMetadata(MediaItemMetadata(resourceUid: "disk://Music/Track1.mp3", artist: "Test artist 1", title: "Test title", album: "test album",
			artwork: "test artwork".dataUsingEncoding(NSUTF8StringEncoding), duration: 1.56), updateExistedObjects: true)
		try!lib.saveMetadata(MediaItemMetadata(resourceUid: "disk://Music/Track2.mp3", artist: "Test artist 2 ", title: "Test title", album: "test album",
			artwork: "test artwork".dataUsingEncoding(NSUTF8StringEncoding), duration: 1.56), updateExistedObjects: true)
		try! lib.saveMetadata(MediaItemMetadata(resourceUid: "disk://Music/Track3.mp3", artist: "Test artist 3", title: "Test title", album: "test album",
			artwork: "test artwork".dataUsingEncoding(NSUTF8StringEncoding), duration: 1.56), updateExistedObjects: true)
		var playList = try! lib.createPlayList("test pl")
		playList = try! lib.addTracksToPlayList(playList, tracks: try! lib.getTracks().map { $0 })
		
		let downloadManager = DownloadManager(saveData: false, fileStorage: LocalNsUserDefaultsStorage(), httpUtilities: httpUtilities)
		let player = RxPlayer(repeatQueue: false, shuffleQueue: false, downloadManager: downloadManager, streamPlayerUtilities: StreamPlayerUtilities(), mediaLibrary: lib)
		let oauth = YandexOAuth()
		let cloudResourceLoader = CloudResourceLoader(cacheProvider: RealmCloudResourceCacheProvider(),
		    rootCloudResources: [YandexDiskCloudJsonResource.typeIdentifier: YandexDiskCloudJsonResource.getRootResource(httpClient, oauth: oauth)])
		player.streamResourceLoaders.append(cloudResourceLoader)
		
		player.play(playList)
		
		XCTAssertEqual(player.currentItems.count, 3, "Check queue has three items")
		XCTAssertTrue(player.playing)
		XCTAssertEqual(player.current?.streamIdentifier.streamResourceUid, "disk://Music/Track1.mp3")
	}*/
}