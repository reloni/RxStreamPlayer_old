# using manual update because carthage can't build frameworks in proper order
carthage update RxSwift --platform iOS
carthage update realm-cocoa --platform iOS
# build RxHttpCliend in Debug configuration to allow unit testsing
carthage update RxHttpClient --platform iOS --configuration Debug
carthage update OHHTTPStubs --platform iOS
