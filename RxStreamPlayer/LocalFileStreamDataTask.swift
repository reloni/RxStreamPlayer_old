import Foundation
import RxSwift
import RxHttpClient

final class LocalFileStreamDataTask {
	let uid: String
	var resumed: Bool = false
	internal(set) var cacheProvider: CacheProviderType?
	let filePath: NSURL
	let subject = PublishSubject<StreamTaskEvents>()
	
	init?(uid: String, filePath: String, provider: CacheProviderType? = nil) {
		if !NSFileManager.fileExistsAtPath(filePath, isDirectory: false) { return nil }
		self.uid = uid
		self.filePath = NSURL(fileURLWithPath: filePath)
		if let provider = provider { self.cacheProvider = provider } else {
			self.cacheProvider = MemoryCacheProvider(uid: uid)
		}
	}
}

extension LocalFileStreamDataTask : StreamDataTaskType {
	var taskProgress: Observable<StreamTaskEvents> {
		return subject.shareReplay(0)
	}
	
	func resume() {
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)) { [weak self] in
			guard let object = self, cacheProvider = object.cacheProvider else { return }
			
			guard let data = NSData(contentsOfFile: object.filePath.path!) else {
				object.subject.onNext(StreamTaskEvents.success(cache: nil))
				object.subject.onCompleted()
				return
			}
			
			object.resumed = true
			let response = LocalFileResponse(expectedContentLength: Int64(data.length),
			                                 mimeType: MimeTypeConverter.getMimeTypeFromFileExtension(object.filePath.pathExtension!))
			
			object.subject.onNext(StreamTaskEvents.receiveResponse(response))
			
			cacheProvider.setContentMimeTypeIfEmpty(response.getMimeType())
			cacheProvider.appendData(data)
			
			object.subject.onNext(StreamTaskEvents.cacheData(cacheProvider))
			object.subject.onNext(StreamTaskEvents.success(cache: nil))
			
			object.resumed = false
			object.subject.onCompleted()
		}
	}
	
	func cancel() {
		resumed = false
	}
	
	func suspend() {
		resumed = false
	}
}

struct LocalFileResponse {
	var expectedContentLength: Int64
	var MIMEType: String?
	init(expectedContentLength: Int64, mimeType: String? = nil) {
		self.expectedContentLength = expectedContentLength
		self.MIMEType = mimeType
	}
}

extension LocalFileResponse : NSHTTPURLResponseType { }