import UIKit
import WebKit

public protocol TLSessionDelegate: class {
    func prepareWebViewConfiguration(configuration: WKWebViewConfiguration, forSession session: TLSession)

    func session(session: TLSession, didInitializeWebView webView: WKWebView)
    func session(session: TLSession, didProposeVisitToLocation location: NSURL)
    
    func sessionDidStartRequest(session: TLSession)
    func session(session: TLSession, didFailRequestForVisitable visitable: TLVisitable, withError error: NSError)
    func session(session: TLSession, didFailRequestForVisitable visitable: TLVisitable, withStatusCode statusCode: Int)
    func sessionDidFinishRequest(session: TLSession)
}

public class TLSession: NSObject, TLWebViewDelegate, TLVisitDelegate, TLVisitableDelegate {
    public weak var delegate: TLSessionDelegate?

    var initialized: Bool = false
    var refreshing: Bool = false

    lazy var webView: TLWebView = {
        let configuration = WKWebViewConfiguration()
        self.delegate?.prepareWebViewConfiguration(configuration, forSession: self)
        let webView = TLWebView(configuration: configuration)
        webView.delegate = self
        return webView
    }()
    
    // MARK: Visiting

    public var currentVisitable: TLVisitable?
    private var lastIssuedVisit: TLVisit?
    private var topmostVisit: TLVisit?

    public func visit(visitable: TLVisitable) {
        visitVisitable(visitable, action: .Advance)
    }
    
    func visitVisitable(visitable: TLVisitable, action: TLVisitAction) {
        if let location = visitable.location {
            let visit: TLVisit

            if initialized {
                visit = TLJavaScriptVisit(visitable: visitable, action: action, webView: webView)
            } else {
                visit = TLColdBootVisit(visitable: visitable, action: action, webView: webView)
            }

            lastIssuedVisit?.cancel()
            lastIssuedVisit = visit

            visit.delegate = self
            visit.start()
        }
    }

    public func reload() {
        if let visitable = currentVisitable {
            initialized = false
            visitVisitable(visitable, action: .Advance)
            activateVisitable(visitable)
        }
    }

    // MARK: TLWebViewDelegate

    func webView(webView: TLWebView, didProposeVisitToLocation location: NSURL) {
        delegate?.session(self, didProposeVisitToLocation: location)
    }

    func webViewDidInvalidatePage(webView: TLWebView) {
        if let visitable = currentVisitable {
            visitable.updateScreenshot()
            topmostVisit?.cancel()

            visitable.showScreenshot()
            visitable.showActivityIndicator()

            reload()
        }
    }

    // MARK: TLVisitDelegate

    func visitDidInitializeWebView(visit: TLVisit) {
        initialized = true
        delegate?.session(self, didInitializeWebView: webView)
        visit.visitable.didLoadResponse?()
    }

    func visitWillStart(visit: TLVisit) {
        visit.visitable.showScreenshot()
        activateWebViewForVisitable(visit.visitable)
    }
   
    func visitDidStart(visit: TLVisit) {
        if !visit.hasSnapshot {
            visit.visitable.showActivityIndicator()
        }
    }

    func visitDidRestoreSnapshot(visit: TLVisit) {
        visit.visitable.hideScreenshot()
        visit.visitable.hideActivityIndicator()
        visit.visitable.didRestoreSnapshot?()
    }

    func visitDidLoadResponse(visit: TLVisit) {
        visit.visitable.didLoadResponse?()
    }

    func visitDidComplete(visit: TLVisit) {
        visit.visitable.hideScreenshot()
        visit.visitable.hideActivityIndicator()

        if refreshing {
            refreshing = false
            visit.visitable.didRefresh()
        }
    }

    func visitDidFail(visit: TLVisit) {
        visit.visitable.hideScreenshot()
        visit.visitable.hideActivityIndicator()
        deactivateVisitable(visit.visitable)
    }

    // MARK: TLVisitDelegate - Request

    func visitRequestDidStart(visit: TLVisit) {
        delegate?.sessionDidStartRequest(self)
    }

    func visitRequestDidFinish(visit: TLVisit) {
        delegate?.sessionDidFinishRequest(self)
    }

    func visit(visit: TLVisit, requestDidFailWithError error: NSError) {
        delegate?.session(self, didFailRequestForVisitable: visit.visitable, withError: error)
    }

    func visit(visit: TLVisit, requestDidFailWithStatusCode statusCode: Int) {
        delegate?.session(self, didFailRequestForVisitable: visit.visitable, withStatusCode: statusCode)
    }

    // MARK: TLVisitableDelegate

    public func visitableViewWillAppear(visitable: TLVisitable) {
        if let topmostVisit = self.topmostVisit, lastIssuedVisit = self.lastIssuedVisit {
            let topmostVisitable = topmostVisit.visitable
            if visitable === topmostVisitable && visitable.viewController.isMovingToParentViewController() {
                // Back swipe gesture canceled
                if topmostVisit.state == .Completed {
                    // Top visitable was fully loaded before the gesture began
                    lastIssuedVisit.cancel()
                } else {
                    // Top visitable was *not* fully loaded before the gesture began
                    visitVisitable(visitable, action: .Advance)
                }
            } else if lastIssuedVisit.visitable !== visitable || lastIssuedVisit.state == .Canceled {
                // Navigating backward
                visitVisitable(visitable, action: .Restore)
            }
        }
    }
    
    public func visitableViewDidAppear(visitable: TLVisitable) {
        if lastIssuedVisit?.visitable === visitable {
            self.topmostVisit = lastIssuedVisit
        }

        activateVisitable(visitable)

        if let visit = self.topmostVisit where visit.visitable === visitable {
            if visit.state == .Completed {
                visitable.hideActivityIndicator()
                visitable.hideScreenshot()
            } else {
                visit.completeNavigation()
            }
        }
    }

    public func visitableViewWillDisappear(visitable: TLVisitable) {
        visitable.updateScreenshot()
        visitable.showScreenshot()
    }

    public func visitableDidRequestRefresh(visitable: TLVisitable) {
        if visitable === currentVisitable {
            refreshing = true
            visitable.willRefresh()
            reload()
        }
    }

    func activateVisitable(visitable: TLVisitable) {
        currentVisitable = visitable
        activateWebViewForVisitable(visitable)
    }

    func deactivateVisitable(visitable: TLVisitable) {
        deactivateWebViewForVisitable(visitable)
    }

    func activateWebViewForVisitable(visitable: TLVisitable) {
        if !webView.isDescendantOfView(visitable.viewController.view) {
            if currentVisitable != nil && currentVisitable !== visitable {
                deactivateWebViewForVisitable(currentVisitable!)
            }
            visitable.activateWebView(webView)
        }
    }

    func deactivateWebViewForVisitable(visitable: TLVisitable) {
        visitable.deactivateWebView()
    }
}
