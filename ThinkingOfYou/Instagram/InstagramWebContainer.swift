//  InstagramWebContainer.swift
//  ThinkingOfYou/Instagram — SwiftUI host for the caged Instagram WKWebView.
//
//  The WKWebView itself is owned by InstagramViewModel (via its
//  InstagramWebCoordinator) so the page, scroll position and login survive
//  mode switches. This representable only parents that view.
//
//  Usage (UI):  InstagramWebContainer(model: env.instagram)

import SwiftUI
import UIKit
import WebKit

struct InstagramWebContainer: UIViewRepresentable {
    let model: InstagramViewModel

    init(model: InstagramViewModel) {
        self.model = model
    }

    func makeUIView(context: Context) -> InstagramWebHostView {
        let host = InstagramWebHostView()
        host.attach(model.webCoordinator.webView)
        return host
    }

    func updateUIView(_ uiView: InstagramWebHostView, context: Context) {
        uiView.attach(model.webCoordinator.webView)
    }

    static func dismantleUIView(_ uiView: InstagramWebHostView, coordinator: Coordinator) {
        uiView.detach()
    }
}

/// Plain container that keeps the shared WKWebView pinned to its bounds.
final class InstagramWebHostView: UIView {
    private weak var hosted: WKWebView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .systemBackground
    }

    func attach(_ webView: WKWebView) {
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
        hosted = webView
    }

    func detach() {
        if let hosted, hosted.superview === self {
            hosted.removeFromSuperview()
        }
        hosted = nil
    }
}
