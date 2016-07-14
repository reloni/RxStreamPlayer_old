import Foundation
import AVFoundation
import RxSwift
import RxHttpClient

public protocol PlayerEventType { }

public enum PlayerEvents : PlayerEventType {
	case AddNewItem(RxPlayerQueueItem)
	case AddNewItems([RxPlayerQueueItem])
	case RemoveItem(RxPlayerQueueItem)
	case Shuflle([RxPlayerQueueItem])
	case InitWithNewItems([RxPlayerQueueItem])
	case CurrentItemChanged(RxPlayerQueueItem?)
	case RepeatChanged(Bool)
	case ShuffleChanged(Bool)
	case ChangeItemsOrder(RxPlayer)
	case PreparingToPlay(RxPlayerQueueItem)
	case Resuming(RxPlayerQueueItem)
	case Resumed
	case Started
	case Stopping(RxPlayerQueueItem)
	case Stopped
	case Pausing(RxPlayerQueueItem)
	case Paused
	case FinishPlayingCurrentItem
	case FinishPlayingQueue
	case StartRepeatQueue
	case Error(ErrorType)
}

public class RxPlayer {
	public var streamResourceLoaders = [StreamResourceLoaderType]()
	public let downloadManager: DownloadManagerType
	public let mediaLibrary: MediaLibraryType
	public internal(set) var playing: Bool = false
	
	internal let streamPlayerUtilities: StreamPlayerUtilitiesProtocol
	internal var itemsSet = NSMutableOrderedSet()
	internal var playerEventsSubject = PublishSubject<PlayerEvents>()
	internal let serialScheduler = SerialDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility)
	internal var uiApplication: UIApplicationType?
	internal var backgroundTaskIdentifier: Int?
	/// Maximum amount of data that would me downloaded in order to retrieve metadata 
	internal let matadataMaximumLoadLength = 1024 * 256
	
	internal lazy var eventsCallback: (PlayerEvents) -> () = {
		return { [weak self] (event: PlayerEvents) in
			self?.playerEventsSubject.onNext(event)
		}
	}()
	
	internal lazy var internalPlayer: InternalPlayerType = { [unowned self] in
		return self.streamPlayerUtilities.createInternalPlayer(self, eventsCallback: self.eventsCallback)
	}()
	
	public var currentItem: Observable<RxPlayerQueueItem?> {
		return Observable.create { [weak self] observer in
			guard let object = self else { observer.onCompleted(); return NopDisposable.instance }
			
			observer.onNext(object.current)
			
			let disposable = object.playerEvents.filter { e in
				if case PlayerEvents.CurrentItemChanged = e { return true }
				return false
				}.map { e -> RxPlayerQueueItem? in
				if case PlayerEvents.CurrentItemChanged(let item) = e {
					return item
				}
				return nil
				}.subscribe(observer)
		
		
			return AnonymousDisposable {
				disposable.dispose()
			}
		}
	}
	
	public var currentItemTime: Observable<(currentTime: CMTime?, duration: CMTime?)?> {
		return internalPlayer.currentTime.shareReplay(0)
	}
	
	public func getCurrentItemTimeAndDuration() -> (currentTime: CMTime, duration: CMTime)? {
		return internalPlayer.getCurrentTimeAndDuration()
	}
	
	public lazy var playerEvents: Observable<PlayerEvents> = {
		return Observable.create { [weak self] observer in
			guard let object = self else { observer.onCompleted(); return NopDisposable.instance }
			
			let first = object.playerEventsSubject.shareReplay(0).doOnError { print("Player event error \($0)") }.observeOn(object.serialScheduler).bindNext { e in
				observer.onNext(e)
			}
			
			return AnonymousDisposable {
				first.dispose()
			}
		}.shareReplay(0)
	}()
		
	internal var currentStreamTask: Disposable?
	internal func startStreamTask() {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {
			self.currentStreamTask?.dispose()
			self.currentStreamTask = self.internalPlayer.play(self.current!.streamIdentifier).doOnNext { [weak self] event in
					//print("internal player event: \(event)")
				if case Result.error(let error) = event {
					if case DownloadManagerErrors.unsupportedUrlSchemeOrFileNotExists = error {
						self?.playerEventsSubject.onNext(PlayerEvents.Error(error))
						self?.toNext(true)
					} else {
						self?.playerEventsSubject.onNext(PlayerEvents.Error(error))
					}
				}
				}
				.catchError { error in
					NSLog("catched error while playing: \((error as NSError).localizedDescription)")
					return Observable.empty()
				}.subscribe()
		}
	}
	internal var _current: RxPlayerQueueItem?
	public var current: RxPlayerQueueItem? {
		get {
			return _current
		}
		set {
			if _current == newValue {
				return
			}
			_current = newValue
			
			playerEventsSubject.onNext(.CurrentItemChanged(_current))
			if playing && _current != nil {
				playerEventsSubject.onNext(.PreparingToPlay(_current!))
				startStreamTask()
			} else if _current == nil {
				playing = false
				internalPlayer.stop()
			}
		}
	}
	
	public var repeatQueue: Bool {
		didSet {
			playerEventsSubject.onNext(.RepeatChanged(repeatQueue))
		}
	}
	
	public var shuffleQueue: Bool {
		didSet {
			playerEventsSubject.onNext(.ShuffleChanged(shuffleQueue))
		}
	}
	
	public init(repeatQueue: Bool, shuffleQueue: Bool, downloadManager: DownloadManagerType,
	              streamPlayerUtilities: StreamPlayerUtilitiesProtocol, mediaLibrary: MediaLibraryType = RealmMediaLibrary()) {
		self.repeatQueue = repeatQueue
		self.shuffleQueue = shuffleQueue
		self.downloadManager = downloadManager
		self.streamPlayerUtilities = streamPlayerUtilities
		self.mediaLibrary = mediaLibrary
	}
	
	public convenience init(repeatQueue: Bool = false, shuffleQueue: Bool = false, saveData: Bool = false) {
		self.init(repeatQueue: repeatQueue, shuffleQueue: shuffleQueue,
		          downloadManager: DownloadManager(saveData: saveData, fileStorage: LocalNsUserDefaultsStorage(persistInformationAboutSavedFiles: saveData),
								httpUtilities: HttpUtilities()), streamPlayerUtilities: StreamPlayerUtilities(), mediaLibrary: RealmMediaLibrary())
	}
	
	public convenience init(repeatQueue: Bool = false, shuffleQueue: Bool = false, downloadManager: DownloadManagerType) {
		self.init(repeatQueue: repeatQueue, shuffleQueue: shuffleQueue, downloadManager: downloadManager, streamPlayerUtilities: StreamPlayerUtilities(),
		          mediaLibrary: RealmMediaLibrary())
	}
}