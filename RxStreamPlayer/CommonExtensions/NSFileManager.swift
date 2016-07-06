import Foundation

extension NSFileManager {
	static func fileExistsAtPath(path: String, isDirectory: Bool = false) -> Bool {
		var isDir = ObjCBool(isDirectory)
		return NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDir)
	}
	
	static func getOrCreateSubDirectory(directoryUrl: NSURL, subDirName: String) -> NSURL? {
		let newDir = directoryUrl.URLByAppendingPathComponent(subDirName)
		guard let path = newDir.path else { return nil }
		
		guard !NSFileManager.fileExistsAtPath(path, isDirectory: true) else { return newDir }
		
		do
		{
			try NSFileManager.defaultManager().createDirectoryAtPath(path, withIntermediateDirectories: false, attributes: nil)
			return newDir
		} catch let error as NSError {
			NSLog("Error while creating sub directory (Path: \(path). Error: \(error.description), code: \(error.code))")
			return nil
		}
	}
	
	static var documentsDirectory: NSURL {
		return NSFileManager.getDirectory(.DocumentDirectory)
	}
	
	static var temporaryDirectory: NSURL {
		return NSURL(fileURLWithPath: NSTemporaryDirectory())
	}
	
	static func getDirectory(directory: NSSearchPathDirectory) -> NSURL {
		return NSFileManager.defaultManager().URLsForDirectory(directory, inDomains: .UserDomainMask)[0]
	}
	
	static func getDirectorySize(directory: NSURL, recursive: Bool = false) -> UInt64 {
		var result: UInt64 = 0
		let fileManager = NSFileManager.defaultManager()
		if NSFileManager.fileOrDirectoryExistsAtPath(directory.path ?? "", isDirectory: true) {
			guard let contents = try? fileManager.contentsOfDirectoryAtURL(directory, includingPropertiesForKeys: nil, options: .SkipsHiddenFiles) else {
				return result
			}
			
			for content in contents {
				if let path = content.path {
					// if file
					if isFileExistsAtPath(path) {
						if let attrs: NSDictionary = try? fileManager.attributesOfItemAtPath(path) {
							result += attrs.fileSize()
						}
					} else if isDirectoryExistsAtPath(path) && recursive {
						// if directory
						result += getDirectorySize(content, recursive: recursive)
					}
				}
			}
		}
		return result
	}
	
	static func fileOrDirectoryExistsAtPath(path: String, isDirectory: Bool) -> Bool {
		var isDir = ObjCBool(isDirectory)
		if NSFileManager.defaultManager().fileExistsAtPath(path, isDirectory: &isDir) && isDirectory == isDir.boolValue {
			return true
		}
		return false
	}
	
	static func isFileExistsAtPath(pathToFile: String) -> Bool {
		return NSFileManager.fileOrDirectoryExistsAtPath(pathToFile, isDirectory: false)
	}
	
	static func isDirectoryExistsAtPath(pathtoDir: String) -> Bool {
		return NSFileManager.fileOrDirectoryExistsAtPath(pathtoDir, isDirectory: true)
	}
}