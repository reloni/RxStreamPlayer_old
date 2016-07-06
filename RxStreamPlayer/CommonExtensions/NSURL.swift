import Foundation

extension NSURL {
	public func fileExists() -> Bool {
		if let path = path {
			return NSFileManager.fileExistsAtPath(path, isDirectory: false)
		}
		return false
	}
	
	public func deleteFile() {
		if fileExists() {
			let _ = try? NSFileManager.defaultManager().removeItemAtURL(self)
		}
	}
}