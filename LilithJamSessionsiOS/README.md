# Lilith Jam Sessions iOS

This is v1 iOS plumbing only. The reusable visualizer and analyzer live in
`LilithVisualCore`; the iOS stub package target renders synthetic
audio-reactive visuals through `LilithJamSessionsiOSView`.

`LilithJamSessionsiOSApp.swift` is the native SwiftUI app entry source for a
future iOS app target. Link that target with the `LilithJamSessionsiOSStub`
package product.

Full iOS media playback is intentionally deferred.
