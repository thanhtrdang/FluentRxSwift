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

// MARK: - UITextField -
extension ControlPropertyType where E == String? {
    public func asTextDriver(throttle: RxTimeInterval = 0.3, distinctUntilChanged: Bool = true) -> Driver<String> {
        var driver = orEmpty.asDriver().throttle(throttle)
        if distinctUntilChanged {
           driver = driver.distinctUntilChanged()
        }
        
        return driver
    }
}

// MARK: - App states -
class RxApplicationDelegateProxy: DelegateProxy, UIApplicationDelegate, DelegateProxyType {
    
    /**
     For more information take a look at `DelegateProxyType`.
     */
    static func currentDelegateFor(_ object: AnyObject) -> AnyObject? {
        let application: UIApplication = object as! UIApplication
        return application.delegate
    }
    
    /**
     For more information take a look at `DelegateProxyType`.
     */
    static func setCurrentDelegate(_ delegate: AnyObject?, toObject object: AnyObject) {
        let application: UIApplication = object as! UIApplication
        application.delegate = delegate as? UIApplicationDelegate
    }
    
    /**
     This is an override to make sure that the original appDelegate is not deallocated
     
     Technically this creates a retain cycle. In this special case that is not a problem
     because UIApplication exists as long as the app exists anyway.
     
     It is necessary to retain the original AppDelegate because when RxApplicationDelegateProxy
     replaces the original delegate with the proxy it normally only keeps a weak reference
     to the original delegate to forward events to the original delegate.
     
     For other delegates this is the correct behaviour because other delegates usually are
     owned by another class (often a UIViewController). In case of the default app delegate
     it is different because there is no class that owns it. When the application is initialized
     the app delegate is explicitly initialized and allocated when UIApplicationMain() is called.
     Because of this the first app delegate is released when another object is set as app delegate
     
     And that makes it necessary to retain the orignal app delegate when the proxy is set
     as new delegate.
     
     Thanks to Michał Ciuba (https://twitter.com/MichalCiuba) who suggested this approach in
     his answer to my question on Stack Overflow:
     http://stackoverflow.com/questions/35575305/transform-uiapplicationdelegate-methods-into-rxswift-observables
     */
    override func setForwardToDelegate(_ delegate: AnyObject?, retainDelegate: Bool) {
        super.setForwardToDelegate(delegate, retainDelegate: true)
    }
}

/**
 UIApplication states
 
 There are two more app states in the Apple Docs ("Not running" and "Suspended").
 I decided to ignore those two states because there are no UIApplicationDelegate
 methods for those states.
 */
public enum AppState: Equatable {
    /**
     The application is running in the foreground.
     */
    case active
    /**
     The application is running in the foreground but not receiving events.
     Possible reasons:
     - The user has opens Notification Center or Control Center
     - The user receives a phone call
     - A system prompt is shown (e.g. Request to allow Push Notifications)
     */
    case inactive
    /**
     The application is in the background because the user closed it.
     */
    case background
    /**
     The application is about to be terminated by the system
     */
    case terminated
}

/**
 Equality function for AppState
 */
public func ==(lhs: AppState, rhs: AppState) -> Bool {
    switch (lhs, rhs) {
    case (.active, .active),
         (.inactive, .inactive),
         (.background, .background),
         (.terminated, .terminated):
        return true
    default:
        return false
    }
}

public struct RxAppState {
    /**
     Allows for the app version to be stored by default in the main bundle from `CFBundleShortVersionString` or
     a custom implementation per app.
     */
    public static var currentAppVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
}

extension RxSwift.Reactive where Base: UIApplication {
    
    /**
     Keys for NSUserDefaults
     */
    fileprivate var isFirstLaunchKey:   String { return "RxAppState_isFirstLaunch" }
    fileprivate var numDidOpenAppKey:   String { return "RxAppState_numDidOpenApp" }
    fileprivate var lastAppVersionKey:  String { return "RxAppState_lastAppVersion" }
    
    /**
     App versions
     */
    fileprivate var appVersions: (last: String, current: String) {
        return (last: UserDefaults.standard.string(forKey: self.lastAppVersionKey) ?? "",
                current: RxAppState.currentAppVersion ?? "")
    }
    
    /**
     Reactive wrapper for `delegate`.
     
     For more information take a look at `DelegateProxyType` protocol documentation.
     */
    public var delegate: DelegateProxy {
        return RxApplicationDelegateProxy.proxyForObject(base)
    }
    
    /**
     Reactive wrapper for `delegate` message `applicationDidBecomeActive(_:)`.
     */
    public var applicationDidBecomeActive: Observable<AppState> {
        return delegate.methodInvoked(#selector(UIApplicationDelegate.applicationDidBecomeActive(_:)))
            .map { _ in
                return .active
        }
    }
    
    /**
     Reactive wrapper for `delegate` message `applicationDidEnterBackground(_:)`.
     */
    public var applicationDidEnterBackground: Observable<AppState> {
        return delegate.methodInvoked(#selector(UIApplicationDelegate.applicationDidEnterBackground(_:)))
            .map { _ in
                return .background
        }
    }
    
    /**
     Reactive wrapper for `delegate` message `applicationWillResignActive(_:)`.
     */
    public var applicationWillResignActive: Observable<AppState> {
        return delegate.methodInvoked(#selector(UIApplicationDelegate.applicationWillResignActive(_:)))
            .map { _ in
                return .inactive
        }
    }
    
    /**
     Reactive wrapper for `delegate` message `applicationWillTerminate(_:)`.
     */
    public var applicationWillTerminate: Observable<AppState> {
        return delegate.methodInvoked(#selector(UIApplicationDelegate.applicationWillTerminate(_:)))
            .map { _ in
                return .terminated
        }
    }
    
    /**
     Observable sequence of the application's state
     
     This gives you an observable sequence of all possible application states.
     
     - returns: Observable sequence of AppStates
     */
    public var appState: Observable<AppState> {
        return Observable.of(
            applicationDidBecomeActive,
            applicationWillResignActive,
            applicationDidEnterBackground,
            applicationWillTerminate
            )
            .merge()
    }
    
    /**
     Observable sequence that emits a value whenever the user opens the app
     
     This is a handy sequence if you want to run some code everytime
     the user opens the app.
     It ignores `applicationDidBecomeActive(_:)` calls when the app was not
     in the background but only in inactive state (because the user
     opened control center or received a call).
     
     Typical use cases:
     - Track when the user opens the app.
     - Refresh data on app start
     
     - returns: Observable sequence of Void
     */
    public var didOpenApp: Observable<Void> {
        return Observable.of(
            applicationDidBecomeActive,
            applicationDidEnterBackground
            )
            .merge()
            .distinctUntilChanged()
            .filter { $0 == .active }
            .map { _ in
                return
        }
    }
    
    /**
     Observable sequence that emits the number of times a user has opened the app
     
     This is a handy sequence if you want to know how many times the user has opened your app
     
     Typical use cases:
     - Ask a user to review your app after when he opens it for the 10th time
     - Track the number of times a user has opened the app
     
     -returns: Observable sequence of Int
     */
    public var didOpenAppCount: Observable<Int> {
        return didOpenApp
            .map { _ in
                let userDefaults = UserDefaults.standard
                var count = userDefaults.integer(forKey: self.numDidOpenAppKey)
                count = min(count + 1, Int.max - 1)
                userDefaults.set(count, forKey: self.numDidOpenAppKey)
                userDefaults.synchronize()
                return count
        }
    }
    
    /**
     Observable sequence that emits if the app is opened for the first time when the user opens the app
     
     This is a handy sequence for all the times you want to run some code only
     when the app is launched for the first time
     
     Typical use case:
     - Show a tutorial to a new user
     
     -returns: Observable sequence of Bool
     */
    public var isFirstLaunch: Observable<Bool> {
        return didOpenApp
            .map { _ in
                let userDefaults = UserDefaults.standard
                let didLaunchBefore = userDefaults.bool(forKey: self.isFirstLaunchKey)
                
                if didLaunchBefore {
                    return false
                } else {
                    userDefaults.set(true, forKey: self.isFirstLaunchKey)
                    userDefaults.synchronize()
                    return true
                }
        }
    }
    
    /**
     Observable sequence that emits if the app is opened for the first time after an app has updated when the user
     opens the app. This does not occur on first launch of a new app install. See `isFirstLaunch` for that.
     
     This is a handy sequence for all the times you want to run some code only when the app is launched for the
     first time after an update.
     
     Typical use case:
     - Show a what's new dialog to users, or prompt review or signup
     
     -returns: Observable sequence of Bool
     */
    public var isFirstLaunchOfNewVersion: Observable<Bool> {
        return didOpenApp
            .map { _ in
                let (lastAppVersion, currentAppVersion) = self.appVersions
                
                if lastAppVersion.isEmpty || lastAppVersion != currentAppVersion {
                    UserDefaults.standard.set(currentAppVersion, forKey: self.lastAppVersionKey)
                    UserDefaults.standard.synchronize()
                }
                
                if !lastAppVersion.isEmpty && lastAppVersion != currentAppVersion {
                    return true
                } else {
                    return false
                }
        }
    }
    
    /**
     Observable sequence that just emits one value if the app is opened for the first time for a new version
     or completes empty if this version of the app has been opened before
     
     This is a handy sequence for all the times you want to run some code only when a new version of the app
     is launched for the first time
     
     Typical use case:
     - Show a what's new dialog to users, or prompt review or signup
     
     -returns: Observable sequence of Void
     */
    public var firstLaunchOfNewVersionOnly: Observable<Void> {
        return Observable.create { observer in
            let (lastAppVersion, currentAppVersion) = self.appVersions
            let isUpgraded = (!lastAppVersion.isEmpty && lastAppVersion != currentAppVersion)
            
            if isUpgraded {
                UserDefaults.standard.set(currentAppVersion, forKey: self.lastAppVersionKey)
                UserDefaults.standard.synchronize()
                observer.onNext()
            }
            observer.onCompleted()
            return Disposables.create {}
        }
    }
    
    /**
     Observable sequence that just emits one value if the app is opened for the first time
     or completes empty if the app has been opened before
     
     This is a handy sequence for all the times you want to run some code only
     when the app is launched for the first time
     
     Typical use case:
     - Show a tutorial to a new user
     
     -returns: Observable sequence of Void
     */
    public var firstLaunchOnly: Observable<Void> {
        return Observable.create { observer in
            let userDefaults = UserDefaults.standard
            let didLaunchBefore = userDefaults.bool(forKey: self.isFirstLaunchKey)
            
            if !didLaunchBefore {
                userDefaults.set(true, forKey: self.isFirstLaunchKey)
                userDefaults.synchronize()
                observer.onNext()
            }
            observer.onCompleted()
            return Disposables.create {}
        }
    }
    
}

//MARK: - Data (Realm, SQLite, Firebase) -

//MARK: - Network -

//MARK: - Gesture -

//MARK: - Core Motion -

//MARK: - Multipeer -

//MARK: - Google Maps
