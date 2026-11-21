import Cocoa

// One binary, two bundles: the same executable is packaged as UVieMac.app
// (the app) and as UVieIM.app (the input method). The bundle identifier on
// the IM bundle's Info.plist decides which role this process takes.
if InputSourceRuntime.isInputMethodProcess {
    InputSourceRuntime.runServer() // never returns
} else {
    UVieMacApp.main()
}
