import Foundation
import RxSwift
import MediaPlayer
import RxHttpClient

extension RxPlayer {
	public func getCurrentItemMetadataForNowPlayingCenter() -> [String: AnyObject]? {
		guard let current = current else { return nil }
		guard let meta = (try? mediaLibrary.getMetadataObjectByUid(current.streamIdentifier)) ?? nil else { return nil }
		
		var data = [String: AnyObject]()
		data[MPMediaItemPropertyTitle] = meta.title
		data[MPMediaItemPropertyAlbumTitle] = meta.album
		data[MPMediaItemPropertyArtist] = meta.artist
		data[MPMediaItemPropertyPlaybackDuration] = meta.duration
		data[MPNowPlayingInfoPropertyElapsedPlaybackTime] = internalPlayer.getCurrentTimeAndDuration()?.currentTime.safeSeconds
		data[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1 : 0
		if let artwork = meta.artwork, image = UIImage(data: artwork) {
			data[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(image: image)
		}
		return data
	}
	
	internal func loadFileMetadata(resource: StreamResourceIdentifier, file: NSURL, utilities: StreamPlayerUtilitiesProtocol) -> AudioItemMetadata? {
		guard file.fileExists() else { return nil }
		
		let item = utilities.createavPlayerItem(file)
		var metadataArray = item.getAsset().getMetadata()
		metadataArray["duration"] = item.getAsset().duration.safeSeconds
		return AudioItemMetadata(resourceUid: resource.streamResourceUid, metadata: metadataArray)
	}
	
	public func loadMetadata(resource: StreamResourceIdentifier) -> Observable<Result<MediaItemMetadataType?>> {
		return loadMetadata(resource, downloadManager: downloadManager, utilities: streamPlayerUtilities)
	}
	
	internal func loadMetadata(resource: StreamResourceIdentifier, downloadManager: DownloadManagerType, utilities: StreamPlayerUtilitiesProtocol)
		-> Observable<Result<MediaItemMetadataType?>> {
		return Observable.create { [weak self] observer in
			guard let object = self else { observer.onNext(Result.success(Box(value: nil))); observer.onCompleted(); return NopDisposable.instance }
			
			// check metadata in media library
			if let metadata = (try? object.mediaLibrary.getMetadataObjectByUid(resource)) ?? nil {
				// if metadata exists, simply return it
				observer.onNext(Result.success(Box(value: metadata)))
				observer.onCompleted()
				return NopDisposable.instance
			}
			
			// check if requested resource existed in local storage as a file
			if let localFile = object.downloadManager.fileStorage.getFromStorage(resource.streamResourceUid) {
				// and if so, load metadata from that file
				let metadata = object.loadFileMetadata(resource, file: localFile, utilities: utilities)
				if let metadata = metadata {
					object.mediaLibrary.saveMetadataSafe(metadata, updateExistedObjects: true)
				}
				
				observer.onNext(Result.success(Box(value: metadata)))
				observer.onCompleted()
				return NopDisposable.instance
			}
			
			// create AVURLAsset and set fake url in order to use "streaming"
			let asset = utilities.createavUrlAsset(NSURL(baseUrl: "fake://test.com", parameters: nil)!)
			let assetObserver = AVAssetResourceLoaderEventsObserver()
			asset.getResourceLoader().setDelegate(assetObserver, queue: dispatch_get_global_queue(QOS_CLASS_UTILITY, 0))
			let downloadObservable = downloadManager.createDownloadObservable(resource, priority: .Low)
			
			// counter of loaded data
			var receivedDataLen: UInt = 0
			
			// creating new observable in order to start downloading data and send it to AVAssetResourceLoader
			// and suspend downloading when we reach download limit
			let assetStreamDisposable = Observable<StreamTaskResult>.create { downloadObserver in
				// disposable variable, that will used inside itself in order to suspend downloading
				var downloadDisposable: Disposable?
				
				downloadDisposable = downloadObservable.catchError { error in
					observer.onNext(Result.error(error))
					observer.onCompleted()
					return Observable.empty()
					}.observeOn(SerialDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility)).doOnNext { e in
						if case Result.success(let box) = e {
							if case StreamTaskEvents.CacheData(let prov) = box.value {
								receivedDataLen = UInt(prov.currentDataLength)
								// if we reach maximum amount of allowed data to download
								if receivedDataLen >= object.matadataMaximumLoadLength {
									// dispose download task
									downloadDisposable?.dispose()
								}
							}
							
							// send data to observer (loadWithAsset method will deliver data to AVAssetResourceLoader)
							downloadObserver.onNext(e)
						} else if case Result.error(let error) = e {
							observer.onNext(Result.error(error))
							observer.onCompleted()
						}
				}.subscribe()
				
				return AnonymousDisposable {
					downloadDisposable?.dispose()
				}
			}.loadWithAsset(assetEvents: assetObserver.loaderEvents, targetAudioFormat: resource.streamResourceContentType).subscribe()
			
			// load duration of asset async
			// and when it's loaded, return metadata
			asset.loadValuesAsynchronouslyForKeys(["duration"]) { [weak self] in
				// AVAssetResourceLoader don't hold strong reference to delegate,
				// so do it
				let _ = assetObserver

				var metadataArray = asset.getMetadata()
				metadataArray["duration"] = asset.duration.safeSeconds
				let audioMetadata = AudioItemMetadata(resourceUid: resource.streamResourceUid, metadata: metadataArray)
				
				self?.mediaLibrary.saveMetadataSafe(audioMetadata, updateExistedObjects: true)
				
				#if DEBUG
					NSLog("Metadata for \(resource.streamResourceUid) loaded. Data received: \(receivedDataLen)")
				#endif
				
				observer.onNext(Result.success(Box(value: audioMetadata)))
				observer.onCompleted()
			}
			
			return AnonymousDisposable {
				assetStreamDisposable.dispose()
			}
		}
	}
	
	public func loadMetadataForItemsInQueue() -> Observable<Result<MediaItemMetadataType>> {
		return loadMetadataForItemsInQueue(downloadManager, utilities: streamPlayerUtilities, mediaLibrary: mediaLibrary)
	}
	
	public func loadMetadataAndAddToMediaLibrary(items: [StreamResourceIdentifier]) -> Observable<Result<MediaItemMetadataType>> {
		return Observable.create { [weak self] observer in
			guard let object = self else { observer.onCompleted(); return NopDisposable.instance }
			
			let serialScheduler = SerialDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility)
			let loadDisposable = items.toObservable().observeOn(serialScheduler)
				.flatMap { item -> Observable<Result<MediaItemMetadataType?>> in
					return object.loadMetadata(item)
				}.doOnCompleted { observer.onCompleted() }.bindNext { result in
					if case Result.success(let box) = result, let meta = box.value {
						observer.onNext(Result.success(Box(value: meta)))
					} else if case Result.error(let error) = result {
						observer.onNext(Result.error(error))
					}
			}
			
			return AnonymousDisposable {
				loadDisposable.dispose()
			}
		}
	}
	
	internal func loadMetadataForItemsInQueue(downloadManager: DownloadManagerType, utilities: StreamPlayerUtilitiesProtocol,
	                                          mediaLibrary: MediaLibraryType) -> Observable<Result<MediaItemMetadataType>> {
		return loadMetadataAndAddToMediaLibrary(currentItems.map { $0.streamIdentifier })
	}
}