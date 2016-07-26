import Foundation

public protocol StreamResourceLoaderType {
	func loadStreamResourceByUid(uid: String) -> StreamResourceIdentifier?
}