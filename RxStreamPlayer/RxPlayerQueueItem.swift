import Foundation
import AVFoundation
import RxSwift

public final class RxPlayerQueueItem {
	public var parent: RxPlayerQueueItem? {
		return player.getItemBefore(streamIdentifier)
	}
	public var child: RxPlayerQueueItem? {
		return player.getItemAfter(streamIdentifier)
	}
	public let streamIdentifier: StreamResourceIdentifier
	public let player: RxPlayer
	public var inQueue: Bool {
		return player.getQueueItemByUid(streamIdentifier.streamResourceUid) != nil
	}
	
	public init(player: RxPlayer, streamIdentifier: StreamResourceIdentifier) {
		self.player = player
		self.streamIdentifier = streamIdentifier
	}
}

public func ==(lhs: RxPlayerQueueItem, rhs: RxPlayerQueueItem) -> Bool {
	return lhs.hashValue == rhs.hashValue
}

extension RxPlayerQueueItem : Hashable {
	public var hashValue: Int {
		return streamIdentifier.streamResourceUid.hashValue
	}
}