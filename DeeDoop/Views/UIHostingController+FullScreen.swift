//
//  UIHostingController+FullScreen.swift
//  DeeDoop
//
//  Makes a view report zero safe area insets so SwiftUI content can fill the full window.
//

import UIKit
import ObjectiveC

/// Makes the given view report safeAreaInsets == .zero so it receives the full window frame.
/// Call this on a UIHostingController's view to remove black bars at top/bottom.
func makeViewIgnoreSafeArea(_ view: UIView) {
    guard let viewClass = object_getClass(view) else { return }
    let viewSubclassName = String(cString: class_getName(viewClass)).appending("_IgnoreSafeArea")

    if let viewSubclass = NSClassFromString(viewSubclassName) {
        object_setClass(view, viewSubclass)
    } else {
        guard
            let viewClassNameUtf8 = (viewSubclassName as NSString).utf8String,
            let viewSubclass = objc_allocateClassPair(viewClass, viewClassNameUtf8, 0)
        else { return }

        if let method = class_getInstanceMethod(UIView.self, #selector(getter: UIView.safeAreaInsets)) {
            let block: @convention(block) (AnyObject) -> UIEdgeInsets = { _ in .zero }
            class_addMethod(
                viewSubclass,
                #selector(getter: UIView.safeAreaInsets),
                imp_implementationWithBlock(block),
                method_getTypeEncoding(method)
            )
        }
        objc_registerClassPair(viewSubclass)
        object_setClass(view, viewSubclass)
    }
}
