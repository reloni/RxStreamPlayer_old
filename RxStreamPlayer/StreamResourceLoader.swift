import Foundation
//import SwiftyJSON

public protocol StreamResourceLoaderType {
	func loadStreamResourceByUid(uid: String) -> StreamResourceIdentifier?
}

/*
public class CloudResourceLoader {
	internal let cacheProvider: CloudResourceCacheProviderType
	internal let rootCloudResources: [String: CloudResource]
	public init(cacheProvider: CloudResourceCacheProviderType, rootCloudResources: [String: CloudResource]) {
		self.cacheProvider = cacheProvider
		self.rootCloudResources = rootCloudResources
	}
}

extension CloudResourceLoader : StreamResourceLoaderType {
	public func loadStreamResourceByUid(uid: String) -> StreamResourceIdentifier? {
		guard let rawData = cacheProvider.getRawCachedResource(uid) else { return nil }//, resource = rootCloudResources[rawData.resourceTypeIdentifier] else { return nil }
		
		guard let resource = rootCloudResources[rawData.resourceTypeIdentifier] else { return nil }
		
		return resource.wrapRawData(JSON(data: rawData.rawData)) as? StreamResourceIdentifier
	}
}
*/