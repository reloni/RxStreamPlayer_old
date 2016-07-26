import Foundation
import AVFoundation

struct AudioItemMetadata {
	var resourceUid: String
	let metadata: [String: AnyObject?]
	init(resourceUid: String, metadata: [String: AnyObject?]) {
		self.metadata = metadata
		self.resourceUid = resourceUid
	}
	var title: String? {
		return metadata["title"] as? String
	}
	
	var artist: String? {
		return metadata["artist"] as? String
	}
	
	var album: String? {
		return metadata["albumName"] as? String
	}
	
	var artwork: NSData? {
		return metadata["artwork"] as? NSData
	}
	
	var duration: Float? {
		return metadata["duration"] as? Float
	}
}

extension AudioItemMetadata: MediaItemMetadataType { }