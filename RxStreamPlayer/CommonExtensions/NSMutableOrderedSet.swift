import Foundation

extension NSMutableOrderedSet {
	func getIndexOfObject(object: AnyObject) -> Int? {
		let index = indexOfObject(object)
		return index != NSNotFound ? index : nil
	}
	
	func getAnyObjectAtIndex(index: Int) -> AnyObject? {
		guard index != NSNotFound && index >= 0 && index < count else { return nil }
		return self[index]
	}
	
	func getObjectAtIndex<T>(index: Int) -> T? {
		return getAnyObjectAtIndex(index) as? T
	}
}