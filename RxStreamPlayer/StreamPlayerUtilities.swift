import Foundation
import AVFoundation

protocol StreamPlayerUtilitiesProtocol {
	func createavUrlAsset(url: NSURL) -> AVURLAssetProtocol
	func createavPlayerItem(asset: AVURLAssetProtocol) -> AVPlayerItemProtocol
	func createavPlayerItem(url: NSURL) -> AVPlayerItemProtocol
	func createInternalPlayer(hostPlayer: RxPlayer, eventsCallback: (PlayerEvents) -> ()) -> InternalPlayerType
}

struct StreamPlayerUtilities {
	init() { }
}

extension StreamPlayerUtilities: StreamPlayerUtilitiesProtocol {
	func createavUrlAsset(url: NSURL) -> AVURLAssetProtocol {
		return AVURLAsset(URL: url)
	}
	
	func createavPlayerItem(asset: AVURLAssetProtocol) -> AVPlayerItemProtocol {
		return AVPlayerItem(asset: asset as! AVURLAsset)
	}
	
	func createavPlayerItem(url: NSURL) -> AVPlayerItemProtocol {
		return AVPlayerItem(URL: url)
	}
	
	func createInternalPlayer(hostPlayer: RxPlayer, eventsCallback: (PlayerEvents) -> ()) -> InternalPlayerType {
		return InternalPlayer(hostPlayer: hostPlayer, eventsCallback: eventsCallback)
	}
}