import Foundation
import AVFoundation
import RxSwift
import MobileCoreServices
import RxHttpClient

public struct ContentTypeDefinition {
	public let MIME: String
	public let UTI: String
	public let fileExtension: String
	
	public init(mime: String, uti: String, fileExtension: String) {
		self.MIME = mime
		self.UTI = uti
		self.fileExtension = fileExtension
	}
	
	public static func getUtiFromMime(mimeType: String) -> String? {
		guard let contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType, nil) else { return nil }
		
		return contentType.takeRetainedValue() as String
	}
	
	public static func getFileExtensionFromUti(utiType: String) -> String? {
		guard let ext = UTTypeCopyPreferredTagWithClass(utiType, kUTTagClassFilenameExtension) else { return nil }
		
		return ext.takeRetainedValue() as String
	}
	
	public static func getUtiTypeFromFileExtension(ext: String) -> String? {
		guard let contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext, nil) else { return nil }
		return contentType.takeRetainedValue() as String
	}
	
	public static func getFileExtensionFromMime(mimeType: String) -> String? {
		guard let uti = getUtiFromMime(mimeType) else { return nil }
		return getFileExtensionFromUti(uti)
	}
	
	public static func getTypeDefinitionFromMime(mimeType: String) -> ContentTypeDefinition? {
		guard let uti = getUtiFromMime(mimeType), ext = getFileExtensionFromUti(uti) else { return nil }
		return ContentTypeDefinition(mime: mimeType, uti: uti, fileExtension: ext)
	}
		
	public static func getMimeTypeFromFileExtension(ext: String) -> String? {
		guard let uti = getUtiTypeFromFileExtension(ext), mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType) else { return nil }
		return mime.takeRetainedValue() as String
	}
	
	public static func getMimeTypeFromUti(uti: String) -> String? {
		guard let mime = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType) else { return nil }
		return mime.takeRetainedValue() as String
	}
}

public enum ContentType: String {
	case mp3 = "audio/mpeg"
	case aac = "audio/aac"
	public var definition: ContentTypeDefinition {
		switch self {
		case .mp3:
			return ContentTypeDefinition(mime: "audio/mpeg", uti: "public.mp3", fileExtension: "mp3")
		case .aac:
			return ContentTypeDefinition(mime: "audio/aac", uti: "public.aac-audio", fileExtension: "aac")
		}
	}
}

protocol StreamTaskEventsType { }
extension StreamTaskEvents : StreamTaskEventsType { }

extension Observable where Element : StreamTaskEventsType {
	internal func loadWithAsset(assetEvents assetLoaderEvents: Observable<AssetLoadingEvents>,
	                                        targetAudioFormat: ContentType? = nil) -> Observable<Void> {
			
			// local variables
			var resourceLoadingRequests = [Int: AVAssetResourceLoadingRequestProtocol]()
			var response: NSHTTPURLResponseType?
			var cacheProvider: CacheProviderType?
			
			
			// functions
			// get uti type of request or from targetAudioFormat
			func getUtiType() -> String? {
				return targetAudioFormat?.definition.UTI ?? {
					guard let response = response else { return nil }
					return ContentTypeDefinition.getUtiFromMime(response.getMimeType())
					}()
			}
			
			// processing requests
			func processRequests(cacheProvider: CacheProviderType) {
				resourceLoadingRequests.map { key, loadingRequest in
					if let contentInformationRequest = loadingRequest.getContentInformationRequest(), response = response {
						contentInformationRequest.byteRangeAccessSupported = true
						contentInformationRequest.contentLength = response.expectedContentLength
						contentInformationRequest.contentType = getUtiType()
					}
					
					if let dataRequest = loadingRequest.getDataRequest() {
						if respondWithData(cacheProvider.getCurrentData(), respondingDataRequest: dataRequest) {
							loadingRequest.finishLoading()
							return key
						}
					}
					return -1
					
					}.filter { $0 != -1 }.forEach { index in resourceLoadingRequests.removeValueForKey(index)
				}
			}
			
			
			// responding to request with data
			func respondWithData(data: NSData, respondingDataRequest: AVAssetResourceLoadingDataRequestProtocol) -> Bool {
				let startOffset = respondingDataRequest.currentOffset != 0 ? respondingDataRequest.currentOffset : respondingDataRequest.requestedOffset
				let dataLength = Int64(data.length)
				
				if dataLength < startOffset {
					return false
				}
				
				let unreadBytesLength = dataLength - startOffset
				let responseLength = min(Int64(respondingDataRequest.requestedLength), unreadBytesLength)
				
				if responseLength == 0 {
					return false
				}
				let range = NSMakeRange(Int(startOffset), Int(responseLength))
				
				let dataToRespond = data.subdataWithRange(range)
				respondingDataRequest.respondWithData(dataToRespond)
				
				return Int64(respondingDataRequest.requestedLength) <= respondingDataRequest.currentOffset + responseLength - respondingDataRequest.requestedOffset
			}
			
			let scheduler = SerialDispatchQueueScheduler(globalConcurrentQueueQOS: DispatchQueueSchedulerQOS.Utility)
			
			return Observable<Void>.create { observer in
				let assetEvents = assetLoaderEvents.observeOn(scheduler).bindNext { e in
					switch e {
					case .didCancelLoading(let loadingRequest):
						resourceLoadingRequests.removeValueForKey(loadingRequest.hash)
						if let cacheProvider = cacheProvider {
							processRequests(cacheProvider)
						}
					case .shouldWaitForLoading(let loadingRequest):
						if !loadingRequest.finished {
							resourceLoadingRequests[loadingRequest.hash] = loadingRequest
							if let cacheProvider = cacheProvider {
								processRequests(cacheProvider)
							}
						}
					case .observerDeinit:
						observer.onCompleted()
					}
				}
				
				let streamEvents = self.observeOn(scheduler).catchError { error in
					observer.onError(error)
					return Observable.empty()
					}.bindNext { e in
						switch e as! StreamTaskEvents {
						case .success(let provider):
							if let provider = provider {
								cacheProvider = provider
								processRequests(provider)
							}
						case .receiveResponse(let receivedResponse): response = receivedResponse
						case .cacheData(let provider):
							cacheProvider = provider
							processRequests(provider)
						default: break
						}
				}
				
				return AnonymousDisposable {
					assetEvents.dispose()
					streamEvents.dispose()
				}
			}.shareReplay(0)
	}
}