import Foundation

extension Dictionary {
	init(_ elements: [Element]){
		self.init()
		for (k, v) in elements {
			self[k] = v
		}
	}
}