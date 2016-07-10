# Copy frameworks that may be changed while development into dependencies folder, to allow Travis-CI use actual version for testing
cp -R $1/Debug-iphonesimulator/RxHttpClient.framework ./Dependencies/iOS
exit 0