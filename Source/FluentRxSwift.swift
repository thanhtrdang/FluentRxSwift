//
//  FluentRxSwift.swift
//  FluentRxSwift
//
//  Created by Thanh Dang on 5/25/17.
//  Copyright © 2017 Thanh Dang. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

//MARK: NSObject -
//https://github.com/RxSwiftCommunity/NSObject-Rx

public extension NSObject {
    fileprivate struct AssociatedKeys {
        static var DisposeBag = "rx_disposeBag"
    }
    
    fileprivate func doLocked(_ closure: () -> Void) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        closure()
    }
    
    var rx_disposeBag: DisposeBag {
        get {
            var disposeBag: DisposeBag!
            doLocked {
                let lookup = objc_getAssociatedObject(self, &AssociatedKeys.DisposeBag) as? DisposeBag
                if let lookup = lookup {
                    disposeBag = lookup
                } else {
                    let newDisposeBag = DisposeBag()
                    self.rx_disposeBag = newDisposeBag
                    disposeBag = newDisposeBag
                }
            }
            return disposeBag
        }
        
        set {
            doLocked {
                objc_setAssociatedObject(self, &AssociatedKeys.DisposeBag, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
}

public extension Reactive where Base: NSObject {
    var disposeBag: DisposeBag {
        get { return base.rx_disposeBag }
        set { base.rx_disposeBag = newValue }
    }
}

//MARK: - Basic extensions -
//https://github.com/RxSwiftCommunity/RxSwiftUtilities
//https://github.com/RxSwiftCommunity/RxSwiftExt
//https://github.com/RxSwiftCommunity/RxOptional

//MARK: - Keyboard -
//https://github.com/RxSwiftCommunity/RxKeyboard

public class RxKeyboard: NSObject {
    
    // MARK: Public
    /// Get a singleton instance.
    public static let instance = RxKeyboard()
    
    /// An observable keyboard frame.
    public let frame: Driver<CGRect>
    
    /// An observable visible height of keyboard. Emits keyboard height if the keyboard is visible
    /// or `0` if the keyboard is not visible.
    public let visibleHeight: Driver<CGFloat>
    
    /// Same with `visibleHeight` but only emits values when keyboard is about to show. This is
    /// useful when adjusting scroll view content offset.
    public let willShowVisibleHeight: Driver<CGFloat>
    
    // MARK: Private
    fileprivate let panRecognizer = UIPanGestureRecognizer()
    
    // MARK: Initializing
    override init() {
        let defaultFrame = CGRect(
            x: 0,
            y: UIScreen.main.bounds.height,
            width: UIScreen.main.bounds.width,
            height: 0
        )
        let frameVariable = Variable<CGRect>(defaultFrame)
        frame = frameVariable.asDriver().distinctUntilChanged()
        visibleHeight = frame.map { UIScreen.main.bounds.height - $0.origin.y }
        willShowVisibleHeight = visibleHeight
            .scan((visibleHeight: 0, isShowing: false)) { lastState, newVisibleHeight in
                return (visibleHeight: newVisibleHeight, isShowing: lastState.visibleHeight == 0)
            }
            .filter { state in state.isShowing }
            .map { state in state.visibleHeight }
        
        super.init()
        
        // keyboard will change frame
        let willChangeFrame = NotificationCenter.default.rx.notification(.UIKeyboardWillChangeFrame)
            .map { notification -> CGRect in
                let rectValue = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue
                return rectValue?.cgRectValue ?? defaultFrame
            }
            .map { frame -> CGRect in
                if frame.origin.y < 0 { // if went to wrong frame
                    var newFrame = frame
                    newFrame.origin.y = UIScreen.main.bounds.height - newFrame.height
                    return newFrame
                }
                return frame
        }
        
        // keyboard will hide
        let willHide = NotificationCenter.default.rx.notification(.UIKeyboardWillHide)
            .map { notification -> CGRect in
                let rectValue = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue
                return rectValue?.cgRectValue ?? defaultFrame
            }
            .map { frame -> CGRect in
                if frame.origin.y < 0 { // if went to wrong frame
                    var newFrame = frame
                    newFrame.origin.y = UIScreen.main.bounds.height
                    return newFrame
                }
                return frame
        }
        
        // pan gesture
        let didPan = panRecognizer.rx.event
            .withLatestFrom(frameVariable.asObservable()) { ($0, $1) }
            .flatMap { (gestureRecognizer, frame) -> Observable<CGRect> in
                guard case .changed = gestureRecognizer.state,
                    let window = UIApplication.shared.windows.first,
                    frame.origin.y < UIScreen.main.bounds.height
                    else { return .empty() }
                let origin = gestureRecognizer.location(in: window)
                var newFrame = frame
                newFrame.origin.y = max(origin.y, UIScreen.main.bounds.height - frame.height)
                return .just(newFrame)
        }
        
        // merge into single sequence
        Observable.of(didPan, willChangeFrame, willHide).merge()
            .bind(to: frameVariable)
            .disposed(by: rx_disposeBag)
        
        // gesture recognizer
        panRecognizer.delegate = self
        NotificationCenter.default.rx.notification(.UIApplicationDidFinishLaunching)
            .map { _ in Void() }
            .startWith(Void()) // when RxKeyboard is initialized before UIApplication.window is created
            .subscribe(onNext: { _ in
                UIApplication.shared.windows.first?.addGestureRecognizer(self.panRecognizer)
            })
            .disposed(by: rx_disposeBag)
    }
}

// MARK: UIGestureRecognizerDelegate
extension RxKeyboard: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let point = touch.location(in: gestureRecognizer.view)
        var view = gestureRecognizer.view?.hitTest(point, with: nil)
        while let candidate = view {
            if let scrollView = candidate as? UIScrollView,
                case .interactive = scrollView.keyboardDismissMode {
                return true
            }
            view = candidate.superview
        }
        return false
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer === panRecognizer
    }
    
}

//MARK: - Data (Realm, SQLite, Firebase) -

//MARK: - Network -

//MARK: - Gesture -

//MARK: - Core Motion -

//MARK: - Multipeer -

//MARK: - Google Maps
