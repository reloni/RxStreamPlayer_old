# Copy frameworks that may be changed while development into dependencies folder, to allow Travis-CI use actual version for testing
if [ "${CONFIGURATION}" = "Debug" ]; then
	mkdir -p ./Dependencies/iOS
	cp -R $1/Debug-iphonesimulator/RxHttpClient.framework ./Dependencies/iOS
fi
exit 0