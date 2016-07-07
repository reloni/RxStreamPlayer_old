# Copy RxHttpClient.framework, because it's used as submodule and may be changed while development
if [ -d ./XCodeBuild ]
then
cp -R ./XCodeBuild/Products/Debug-iphonesimulator/RxHttpClient.framework ./Dependencies/iOS
fi