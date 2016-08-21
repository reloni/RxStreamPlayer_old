# using manual update because carthage can't build frameworks in proper order
carthage update RxSwift --platform iOS
carthage update realm-cocoa --platform iOS
carthage update RxHttpClient --platform iOS
carthage update OHHTTPStubs --platform iOS
