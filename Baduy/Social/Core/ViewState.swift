import SwiftUI

// Explicitly select SwiftUI's stable property wrapper. Xcode 27 also exports a
// same-named State macro; this alias keeps the iOS 18 implementation macro-free.
typealias ViewState<Value> = SwiftUI.State<Value>
