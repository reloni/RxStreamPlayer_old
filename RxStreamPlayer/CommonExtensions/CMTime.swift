import Foundation
import AVFoundation

extension CMTime {	
	public var safeSeconds: Float64? {
		let sec = CMTimeGetSeconds(self)
		return isnan(sec) ? nil : sec
	}
}