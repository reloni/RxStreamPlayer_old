import Foundation
import RxSwift
import AVFoundation

internal class QueueSetItem : NSObject {
	let item: StreamResourceIdentifier
	
	init(item: StreamResourceIdentifier) {
		self.item = item
	}
	
	internal override func isEqual(object: AnyObject?) -> Bool {
		guard let obj = object as? QueueSetItem else { return false }
		
		return obj.item.streamResourceUid == self.item.streamResourceUid
	}
	
	internal override var hash: Int {
		return item.streamResourceUid.hash
	}
}

extension StreamResourceIdentifier {
	internal func asQueueSetItem() -> QueueSetItem {
		return QueueSetItem(item: self)
	}
}

extension RxPlayer {	
	public var first: RxPlayerQueueItem? {
		return getItemAtPosition(0)
	}
	
	public var last: RxPlayerQueueItem? {
		return getItemAtPosition(itemsSet.count - 1)
	}
	
	public var currentItems: [RxPlayerQueueItem] {
		return itemsSet.map { RxPlayerQueueItem(player: self, streamIdentifier: ($0 as! QueueSetItem).item) }
	}
	
	public var count: Int {
		return itemsSet.count
	}

	public convenience init(items: [StreamResourceIdentifier], shuffle: Bool = false, repeatQueue: Bool = false) {
		self.init(repeatQueue: repeatQueue)
		
		initWithNewItems(items, shuffle: shuffle)
	}
	
	public func initWithNewItems(items: [StreamResourceIdentifier]) {
		initWithNewItems(items, shuffle: shuffleQueue)
	}
	
	public func initWithNewItems(items: [StreamResourceIdentifier], shuffle: Bool) {
		itemsSet.removeAllObjects()

		current = nil
		if shuffle {
			itemsSet.addObjectsFromArray(items.map { $0.asQueueSetItem() }.shuffle())
		} else {
			itemsSet.addObjectsFromArray(items.map { $0.asQueueSetItem() })
		}
		playerEventsSubject.onNext(.InitWithNewItems(currentItems))
	}
	
	internal func shuffleCurrentQueue() {
		var items = itemsSet.array
		items.shuffleInPlace()
		itemsSet = NSMutableOrderedSet(array: items)
		playerEventsSubject.onNext(.Shuflle(currentItems))
	}
	
	/// Shuffle queue and set current item to nil
	/// forceRestartQueue - if true, set first item in shuffled queue as current
	public func shuffle(forceRestartQueue: Bool = false) {
		current = nil
		shuffleCurrentQueue()
		if forceRestartQueue {
			toNext()
		}
	}
	
	/// Shuffle queue and preserve current item
	public func shuffleAndContinue() {
		shuffleCurrentQueue()
	}
	
	/// Shuffle queue and set current queue item as first
	public func shuffleAndKeepCurrentItemFirst() {
		shuffleCurrentQueue()
		if let current = current {
			addFirst(current.streamIdentifier)
		}
	}
	
	public func toNext(startPlaying: Bool = false) -> RxPlayerQueueItem? {
		playing = startPlaying
		if current == nil {
			current = first
		} else {
			if current?.child == nil {
				if repeatQueue {
					playerEventsSubject.onNext(PlayerEvents.StartRepeatQueue)
				} else {
					playerEventsSubject.onNext(PlayerEvents.FinishPlayingQueue)
				}
			}
			
			current = repeatQueue ? current?.child ?? first : current?.child
		}
		
		return current
	}
	
	public func toPrevious(startPlaying: Bool = false) -> RxPlayerQueueItem? {
		if current == nil {
			playing = startPlaying
			current = first
		} else if current != first {
			playing = startPlaying
			current = current?.parent
		}
		return current
	}
	
	public func remove(item: StreamResourceIdentifier) {
		guard let index = itemsSet.getIndexOfObject(item.asQueueSetItem()) else { return }
		itemsSet.removeObjectAtIndex(index)
		playerEventsSubject.onNext(.RemoveItem(RxPlayerQueueItem(player: self, streamIdentifier: item)))
	}
	
	public func remove(item: RxPlayerQueueItem) {
		remove(item.streamIdentifier)
	}
	
	public func getQueueItemByUid(uid: String) -> RxPlayerQueueItem? {
		let index = itemsSet.indexOfObject(uid.asQueueSetItem())
		return getItemAtPosition(index)
	}
	
	public func getItemAtPosition(position: Int) -> RxPlayerQueueItem? {
		guard let item: QueueSetItem = itemsSet.getObjectAtIndex(position) else { return nil }
		return RxPlayerQueueItem(player: self, streamIdentifier: item.item)
	}
	
	public func getItemAfter(item: StreamResourceIdentifier) -> RxPlayerQueueItem? {
		let index = itemsSet.indexOfObject(item.asQueueSetItem())
		return getItemAtPosition(index + 1)
	}
	
	public func getItemBefore(item: StreamResourceIdentifier) -> RxPlayerQueueItem? {
		let index = itemsSet.indexOfObject(item.asQueueSetItem())
		return getItemAtPosition(index - 1)
	}
	
	public func addLast(item: StreamResourceIdentifier) -> RxPlayerQueueItem {
		return add(item, index: itemsSet.count)
	}
	
	public func addFirst(item: StreamResourceIdentifier) -> RxPlayerQueueItem {
		return add(item, index: 0)
	}
	
	/// Add item in queue after specified item.
	/// If specified item doesn't exist, add to end
	public func addAfter(itemToAdd: StreamResourceIdentifier, afterItem: StreamResourceIdentifier) -> RxPlayerQueueItem {
		let index = itemsSet.getIndexOfObject(afterItem.asQueueSetItem()) ?? itemsSet.count
		return add(itemToAdd, index: index + 1)
	}
	
	/// Add item in queue.
	/// Return instance of RxPlayerQueueItem if item was added.
	/// If item already exists, set item at specified index and return RxPlayerQueueItem with this item
	private func add(item: StreamResourceIdentifier, index: Int) -> RxPlayerQueueItem {
		var addAtIndex = index
		var isItemRemoved = false
		if let currentIndex = itemsSet.getIndexOfObject(item.asQueueSetItem()) {
			if currentIndex == index {
				return RxPlayerQueueItem(player: self, streamIdentifier: item)
			} else {
				itemsSet.removeObject(item.asQueueSetItem())
				if addAtIndex > 0 { addAtIndex -= 1 }
				isItemRemoved = true
			}
		}
		
		if 0..<itemsSet.count + 1 ~= index {
			itemsSet.insertObject(item.asQueueSetItem(), atIndex: addAtIndex)
		} else {
			itemsSet.addObject(item.asQueueSetItem())
		}
		
		let queueItem = RxPlayerQueueItem(player: self, streamIdentifier: item)
		
		if isItemRemoved {
			playerEventsSubject.onNext(.ChangeItemsOrder(self))
		} else {
			playerEventsSubject.onNext(.AddNewItem(queueItem))
		}
		
		return queueItem
	}
}