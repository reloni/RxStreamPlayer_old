import Foundation

public protocol NSUserDefaultsType {
	func saveData(object: AnyObject, forKey: String)
	func loadData<T>(forKey: String) -> T?
	func loadRawData(forKey: String) -> AnyObject?
	func setObject(value: AnyObject?, forKey: String)
	func objectForKey(forKey: String) -> AnyObject?
}

extension NSUserDefaults : NSUserDefaultsType {
	public func saveData(object: AnyObject, forKey: String) {
		let data = NSKeyedArchiver.archivedDataWithRootObject(object)
		NSUserDefaults.standardUserDefaults().setObject(data, forKey: forKey)
	}
	
	public func loadData<T>(forKey: String) -> T? {
		return loadRawData(forKey) as? T
	}
	
	public func loadRawData(forKey: String) -> AnyObject? {
		if let loadedData = NSUserDefaults.standardUserDefaults().objectForKey(forKey) {
			return NSKeyedUnarchiver.unarchiveObjectWithData(loadedData as! NSData)
		}
		return nil
	}
}