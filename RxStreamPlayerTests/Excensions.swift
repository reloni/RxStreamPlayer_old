import Foundation

extension NSFileManager {
	func contentsOfDirectoryAtURL(directory: NSURL) -> [NSURL]? {
		guard let contents = try? contentsOfDirectoryAtURL(directory, includingPropertiesForKeys: nil, options: .SkipsHiddenFiles) else {
			return nil
		}
		return contents
	}
}

extension Float {
	var asTimeString: String {
		let minutes = Int(self / 60)
		return String(format: "%02d: %02d", minutes, Int(self) - minutes * 60)
	}
}