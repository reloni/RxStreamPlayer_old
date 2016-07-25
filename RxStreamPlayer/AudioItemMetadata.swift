import Foundation
import AVFoundation

final class AudioItemMetadata {
	var resourceUid: String
	let metadata: [String: AnyObject?]
	init(resourceUid: String, metadata: [String: AnyObject?]) {
		self.metadata = metadata
		self.resourceUid = resourceUid
	}
	lazy var title: String? = {
		return self.metadata["title"] as? String
	}()
	
	lazy var artist: String? = {
		return self.metadata["artist"] as? String
	}()
	
	lazy var album: String? = {
		return self.metadata["albumName"] as? String
	}()
	
	lazy var artwork: NSData? = {
		return self.metadata["artwork"] as? NSData
	}()
	
	lazy var duration: Float? = {
		return self.metadata["duration"] as? Float
	}()
}

extension AudioItemMetadata: MediaItemMetadataType { }