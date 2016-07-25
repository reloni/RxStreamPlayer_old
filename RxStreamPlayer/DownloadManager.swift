import Foundation
import RxSwift
import RxHttpClient

public protocol DownloadManagerType {
	func createDownloadObservable(identifier: StreamResourceIdentifier, priority: PendingTaskPriority) -> Observable<StreamTaskEvents>
	var saveData: Bool { get }
	var fileStorage: LocalStorageType { get }
}

public enum DownloadManagerErrors : ErrorType {
	case unsupportedUrlScheme(url: String, uid: String)
	case unsupportedUrl(url: String, uid: String)
	case fileNotExists(url: String, uid: String)
}

public enum PendingTaskPriority: Int {
	case Low = 0
	case Normal = 1
	case High = 2
}

final class PendingTask {
	let task: StreamDataTaskType
	var priority: PendingTaskPriority
	var taskDependenciesCount: UInt = 1
	init(task: StreamDataTaskType, priority: PendingTaskPriority = .Normal) {
		self.task = task
		self.priority = priority
	}
}

public final class DownloadManager {
	internal let serialScheduler: SerialDispatchQueueScheduler = SerialDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility)
	internal var pendingTasks = [String: PendingTask]()
	internal let simultaneousTasksCount: UInt
	internal let runningTaskCheckTimeout: Double
	internal let httpClient: HttpClientType
	
	public let saveData: Bool
	public let fileStorage: LocalStorageType
	
	internal init(saveData: Bool = false, fileStorage: LocalStorageType = LocalNsUserDefaultsStorage(), httpClient: HttpClientType,
	              simultaneousTasksCount: UInt, runningTaskCheckTimeout: Double) {
		self.saveData = saveData
		self.fileStorage = fileStorage
		self.httpClient = httpClient
		self.simultaneousTasksCount = simultaneousTasksCount == 0 ? 1 : simultaneousTasksCount
		self.runningTaskCheckTimeout = runningTaskCheckTimeout <= 0.0 ? 1.0 : runningTaskCheckTimeout
	}
	
	public convenience init(saveData: Bool = false, fileStorage: LocalStorageType = LocalNsUserDefaultsStorage(), httpClient: HttpClientType) {
		self.init(saveData: saveData, fileStorage: fileStorage, httpClient: httpClient, simultaneousTasksCount: 1, runningTaskCheckTimeout: 5)
	}
	
	internal func saveData(cacheProvider: CacheProviderType?) -> NSURL? {
		if let cacheProvider = cacheProvider where saveData {
			return fileStorage.saveToTempStorage(cacheProvider)
		}
		
		return nil
	}
	
	internal func removePendingTask(uid: String, force: Bool = false) {
		guard let pendingTask = self.pendingTasks[uid] else {
			self.pendingTasks[uid] = nil
			return
		}
		
		pendingTask.taskDependenciesCount -= 1
		if pendingTask.taskDependenciesCount <= 0 || force {
			pendingTask.task.cancel()
			self.pendingTasks[uid] = nil
		}
	}
	
	internal func getPendingOrLocalTask(identifier: StreamResourceIdentifier, priority: PendingTaskPriority) -> StreamDataTaskType? {
		if let runningTask = pendingTasks[identifier.streamResourceUid] {
			runningTask.taskDependenciesCount += 1
			if runningTask.priority.rawValue < priority.rawValue {
				runningTask.priority = priority
			}
			
			return runningTask.task
		}
		
		if let file = fileStorage.getFromStorage(identifier.streamResourceUid), path = file.path {
			let task = LocalFileStreamDataTask(uid: identifier.streamResourceUid, filePath: path,
			                                   provider:	fileStorage.createCacheProvider(identifier.streamResourceUid,	targetMimeType: identifier.streamResourceContentType?.definition.MIME))
			if let task = task {
				let pending = PendingTask(task: task, priority: priority)
				pendingTasks[identifier.streamResourceUid] = pending
				return pending.task
			}
		}
		
		return nil
	}
	
	internal func createDownloadTask(identifier: StreamResourceIdentifier, priority: PendingTaskPriority) -> Observable<StreamDataTaskType> {
		return Observable.create { [weak self] observer in
			guard let object = self else { observer.onCompleted(); return NopDisposable.instance }
			
			// check pending tasks
			if let task = object.getPendingOrLocalTask(identifier, priority: priority) {
				observer.onNext(task)
				observer.onCompleted()
				return NopDisposable.instance
			}
			
			let disposable = Observable<Void>.combineLatest(identifier.streamResourceUrl.observeOn(object.serialScheduler),
																											identifier.streamResourceType.observeOn(object.serialScheduler)) { result in
				// check pending tasks again before create new one
				if let task = object.getPendingOrLocalTask(identifier, priority: priority) {
					observer.onNext(task)
					observer.onCompleted()
					return
				}
				
				if let runningTask = object.pendingTasks[identifier.streamResourceUid] {
					runningTask.taskDependenciesCount += 1
					if runningTask.priority.rawValue < priority.rawValue {
						runningTask.priority = priority
					}
					
					observer.onNext(runningTask.task)
					observer.onCompleted()
					return
				}
				
				if let file = object.fileStorage.getFromStorage(identifier.streamResourceUid), path = file.path {
					let task = LocalFileStreamDataTask(uid: identifier.streamResourceUid, filePath: path, provider: object.fileStorage.createCacheProvider(identifier.streamResourceUid,
						targetMimeType: identifier.streamResourceContentType?.definition.MIME))
					
					guard let localTask = task else {
						observer.onError(DownloadManagerErrors.fileNotExists(url: path, uid: identifier.streamResourceUid))
						return
					}
					object.pendingTasks[identifier.streamResourceUid] = PendingTask(task: localTask, priority: priority)
						
					observer.onNext(localTask)
					observer.onCompleted()
					return
				}
				
				let resourceType = result.1
				let resourceUrl = result.0
				
				if resourceType == .LocalResource {
					let task = LocalFileStreamDataTask(uid: identifier.streamResourceUid, filePath: resourceUrl,
						provider: object.fileStorage.createCacheProvider(identifier.streamResourceUid,
							targetMimeType: identifier.streamResourceContentType?.definition.MIME))
					if let task = task {
						object.pendingTasks[identifier.streamResourceUid] = PendingTask(task: task, priority: priority)
						
						observer.onNext(task)
						return
					} else {
						//observer.onNext(nil)
						observer.onError(DownloadManagerErrors.fileNotExists(url: resourceUrl, uid: identifier.streamResourceUid))
						return
					}
				}
				
				guard resourceType == .HttpResource || resourceType == .HttpsResource else {
					//observer.onNext(nil); return
					observer.onError(DownloadManagerErrors.unsupportedUrlScheme(url: resourceUrl, uid: identifier.streamResourceUid))
					return
				}
				
				guard let url = NSURL(baseUrl: resourceUrl, parameters: nil) else {
					//observer.onNext(nil)
					observer.onError(DownloadManagerErrors.unsupportedUrl(url: resourceUrl, uid: identifier.streamResourceUid))
					return
				}
			
				let urlRequest = object.httpClient.createUrlRequest(url, headers: (identifier as? StreamHttpResourceIdentifier)?.streamHttpHeaders)
				
				let task = object.httpClient.createStreamDataTask(identifier.streamResourceUid,
					request: urlRequest,
					cacheProvider: object.fileStorage.createCacheProvider(identifier.streamResourceUid,	targetMimeType: identifier.streamResourceContentType?.definition.MIME))
				/*
				let task = object.fileStorage.createStreamDataTask(identifier.streamResourceUid, request: urlRequest,
					sessionConfiguration: NSURLSession.defaultConfig,
					cacheProvider: object.fileStorage.createCacheProvider(identifier.streamResourceUid,
						targetMimeType: identifier.streamResourceContentType?.definition.MIME))*/
				
				object.pendingTasks[identifier.streamResourceUid] = PendingTask(task: task, priority: priority)
				observer.onNext(task)
			}.doOnCompleted { observer.onCompleted() }.subscribeOn(object.serialScheduler).subscribe()
			
			return AnonymousDisposable {
				disposable.dispose()
			}
			}.subscribeOn(serialScheduler)
	}
	
	internal func monitorTask(identifier: StreamResourceIdentifier,
	                          monitoringInterval: Observable<Int>) -> Observable<Void> {
		
		return Observable<Void>.create { [weak self] observer in
			guard let object = self, pendingTask = object.pendingTasks[identifier.streamResourceUid] else { observer.onCompleted(); return NopDisposable.instance }
			
			if (object.pendingTasks.filter { $0.1.task.resumed &&
				$0.1.priority.rawValue >= pendingTask.priority.rawValue }.count < Int(object.simultaneousTasksCount)) {
				dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) {	pendingTask.task.resume() }
				observer.onNext()
				observer.onCompleted()
				return NopDisposable.instance
			}
			
			return monitoringInterval.observeOn(object.serialScheduler).bindNext { _ in
				guard !pendingTask.task.resumed else { return }
				
				if (object.pendingTasks.filter { $0.1.task.resumed &&
					$0.1.priority.rawValue >= pendingTask.priority.rawValue }.count < Int(object.simultaneousTasksCount)) {
					pendingTask.task.resume()
					observer.onNext()
					observer.onCompleted()
				}
			}
		}
	}
}

extension DownloadManager : DownloadManagerType {
	public func createDownloadObservable(identifier: StreamResourceIdentifier, priority: PendingTaskPriority) -> Observable<StreamTaskEvents> {
		return Observable<StreamTaskEvents>.create { [weak self] observer in
			guard let object = self else { observer.onCompleted(); return NopDisposable.instance }
			
			let disposable = object.createDownloadTask(identifier, priority: priority).catchError{ error in
				observer.onError(error)
				return Observable.empty()
				}.flatMapLatest { task -> Observable<Void> in
					let streamTask = task.taskProgress.observeOn(object.serialScheduler).catchError { error in
						object.removePendingTask(identifier.streamResourceUid, force: true)
						observer.onError(error)
						return Observable.empty()
						}.doOnNext { result in
							if case .success(let provider) = result {
								object.saveData(provider)
								object.removePendingTask(identifier.streamResourceUid, force: true)
								observer.onNext(result)
							} else if case .error(let error) = result {
								observer.onError(error)
							}	else {
								observer.onNext(result)
							}
					}
					
					let monitoring = object.monitorTask(identifier, monitoringInterval: Observable<Int>.interval(object.runningTaskCheckTimeout,
						scheduler: object.serialScheduler))
					
					return Observable<Void>.combineLatest(streamTask, monitoring) { _ in }
				}.subscribeOn(object.serialScheduler).subscribe()
			
			return AnonymousDisposable {
				self?.removePendingTask(identifier.streamResourceUid)
				disposable.dispose()
			}
			}.subscribeOn(serialScheduler)
	}
}