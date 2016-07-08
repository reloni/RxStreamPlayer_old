
import Foundation

extension CollectionType {
	func shuffle() -> [Generator.Element] {
		var list = Array(self)
		list.shuffleInPlace()
		return list
	}
}

extension MutableCollectionType where Index == Int {
	mutating func shuffleInPlace() {
		if count < 2 { return }
		
		var isEqual = true
		while(isEqual) {
			for i in 0..<count - 1 {
				let j = Int(arc4random_uniform(UInt32(count - i))) + i
				guard i != j else { continue }
				swap(&self[i], &self[j])
				isEqual = false
			}
		}
	}
}