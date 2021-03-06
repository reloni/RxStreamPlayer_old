import Foundation
import MediaPlayer

public enum MediaLibraryErroros : ErrorType {
	case emptyPlayListName
}

public protocol MediaLibraryType {
	// metadata
	func getArtists() throws -> MediaCollection<ArtistType>
	func getAlbums() throws -> MediaCollection<AlbumType>
	func getTracks() throws -> MediaCollection<TrackType>
	func getPlayLists() throws -> MediaCollection<PlayListType>
	func getTrackByUid(resource: StreamResourceIdentifier) throws -> TrackType?
	func getMetadataObjectByUid(resource: StreamResourceIdentifier) throws -> MediaItemMetadata?
	func saveMetadata(metadata: MediaItemMetadataType, updateExistedObjects: Bool) throws -> TrackType?
	func saveMetadataSafe(metadata: MediaItemMetadataType, updateExistedObjects: Bool) -> TrackType?
	func isTrackExists(resource: StreamResourceIdentifier) throws -> Bool
	
	// play lists
	func addTracksToPlayList(playList: PlayListType, tracks: [TrackType]) throws -> PlayListType
	func removeTrackFromPlayList(playList: PlayListType, track: TrackType) throws -> PlayListType
	func removeTracksFromPlayList(playList: PlayListType, tracks: [TrackType]) throws -> PlayListType
	func isTrackContainsInPlayList(playList: PlayListType, track: TrackType) throws -> Bool
	func clearPlayList(playList: PlayListType) throws
	func deletePlayList(playList: PlayListType) throws
	func createPlayList(name: String) throws -> PlayListType
	func renamePlayList(playList: PlayListType, newName: String) throws
	//func getAllPlayLists() -> [PlayListType]
	func getPlayListByUid(uid: String) throws -> PlayListType?
	func getPlayListsByName(name: String) throws -> [PlayListType]
	
	func clearLibrary() throws
}

public protocol TrackContainerType {
	var uid: String { get }
}

public protocol ArtistType : TrackContainerType {
	var uid: String { get }
	var name: String { get }
	var albums: MediaCollection<AlbumType> { get }
	func synchronize() -> ArtistType
}
extension ArtistType {
	public func synchronize() -> ArtistType {
		return self
	}
}

public protocol AlbumType : TrackContainerType {
	var uid: String { get }
	var artist: ArtistType { get }
	var tracks: MediaCollection<TrackType> { get }
	var name: String { get }
	var artwork: NSData? { get }
	func synchronize() -> AlbumType
}
extension AlbumType {
	public func synchronize() -> AlbumType {
		return self
	}
}

public protocol TrackType {
	var uid: String { get }
	var title: String { get }
	var duration: Float { get }
	var album: AlbumType { get }
	var artist: ArtistType { get }
	func synchronize() -> TrackType
}
extension TrackType {
	public func synchronize() -> TrackType {
		return self
	}
}

public protocol PlayListType : TrackContainerType {
	var uid: String { get }
	var name: String { get }
	var items: MediaCollection<TrackType> { get }
	func synchronize() -> PlayListType
}
extension PlayListType {
	public func synchronize() -> PlayListType {
		return self
	}
}

public protocol MediaItemMetadataType {
	var resourceUid: String { get }
	var artist: String? { get }
	var title: String? { get }
	var album: String? { get }
	var artwork: NSData? { get }
	var duration: Float? { get }
}

public struct MediaItemMetadata : MediaItemMetadataType {
	public internal(set) var resourceUid: String
	public internal(set) var artist: String?
	public internal(set) var title: String?
	public internal(set) var album: String?
	public internal(set) var artwork: NSData?
	public internal(set) var duration: Float?
	public init(resourceUid: String, artist: String?, title: String?, album: String?, artwork: NSData?, duration: Float?) {
		self.resourceUid = resourceUid
		self.artist = artist
		self.title = title
		self.album = album
		self.artwork = artwork
		self.duration = duration
	}
}

public class MediaCollection<T>  : SequenceType {
	public typealias Generator = MediaCollectionGenerator<T>
	public var first: T? { fatalError("Should be overriden") }
	public var last: T? { fatalError("Should be overriden") }
	public var count: Int { fatalError("Should be overriden") }
	public subscript (index: Int) -> T? { fatalError("Should be overriden")	}
	public func generate() -> MediaCollection.Generator { fatalError("Should be overriden") }
}

public class MediaCollectionGenerator<T> : GeneratorType {
	public typealias Element = T
	let collection: CollectionWrapperType
	var currentIndex = 0
	init(collection: CollectionWrapperType) {
		self.collection = collection
	}
	public func next() -> MediaCollectionGenerator.Element? {
		currentIndex += 1
		if currentIndex > collection.count { return nil }
		return collection[currentIndex - 1] as? T
	}
}

public protocol CollectionWrapperType {
	var count: Int { get }
	subscript (index: Int) -> AnyObject? { get }
}