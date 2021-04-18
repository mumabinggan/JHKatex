//
//  KatexView.swift
//  UltraMarkDown
//
//  Created by nikesu on 2021/2/19.
//

import UIKit
import WebKit
import Combine

public final class KatexView : UIView {

    public enum KatexViewStatus {
        case loading
        case finished
        case idle
    }

    @Published
    public var status: KatexViewStatus = .idle

    public var latex: String = "" {
        didSet {
            reload()
        }
    }

    public override var intrinsicContentSize: CGSize {
        katexWebView.intrinsicContentSize
    }

    private var cancellables = [AnyCancellable]()
    
    public var maxSize: CGSize = UIScreen.main.bounds.size {
        didSet {
            reload()
        }
    }
    
    public var options = [KatexRenderer.Key : Any]() {
        didSet {
            reload()
        }
    }
    
    public var displayMode : Bool {
        get {
            guard let displayMode = options[.displayMode] as? Bool else {
                return false
            }
            return displayMode
        }
        set {
            options[.displayMode] = newValue
            reload()
        }
    }

    private lazy var katexWebView: KatexWebView = {
        let katexWebView = KatexWebView()
        katexWebView.$status.sink { [weak self] status in
            switch status {
            case .idle:
                self?.status = .idle
            case .loading:
                self?.status = .loading
            case .finished:
                self?.status = .finished
                self?.setNeedsLayout()
                self?.invalidateIntrinsicContentSize()
            }
        }.store(in: &cancellables)
        return katexWebView
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView(frame: .zero)
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(self.scrollView)
        self.scrollView.addSubview(self.katexWebView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public convenience init(frame: CGRect = .zero, latex: String, maxSize: CGSize? = nil, options: [KatexRenderer.Key : Any]? = nil) {
        self.init(frame: frame)
        self.latex = latex
        if let options = options {
            self.options = options
        }
        if let maxSize = maxSize {
            self.maxSize = maxSize
        }
        reload()
    }

    deinit {
        for cancellable in cancellables {
            cancellable.cancel()
        }
    }

    public override func layoutSubviews() {
        if (status == .finished) {
            let contentSize = katexWebView.intrinsicContentSize
            katexWebView.frame.size = contentSize
            scrollView.contentSize = contentSize
            scrollView.isScrollEnabled = frame.width < contentSize.width || frame.height < contentSize.height
            scrollView.frame.size = CGSize(width: min(frame.width, contentSize.width), height: min(frame.height, contentSize.height))
        }
    }
    
    public func reload() {
        katexWebView.frame = CGRect(origin: .zero, size: maxSize)
        katexWebView.loadLatex(latex, options: options)
    }
}


extension KatexView {
    private class KatexWebView: WKWebView, WKUIDelegate, WKNavigationDelegate {

        enum KatexWebViewStatus {
            case loading
            case finished
            case idle
        }

        @Published
        var status: KatexWebViewStatus = .idle

        var contentSize: CGSize = .zero {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        private static var templateHtmlPath: String = {
            guard let path = Bundle.katexBundle?.path(forResource: "katex/index", ofType: "html") else {
                fatalError()
            }
            return path
        }()

        private static var templateHtmlString: String = {
            do {
                let templateHtmlString = try String(contentsOfFile: templateHtmlPath, encoding: .utf8)
                return templateHtmlString
            } catch {
                fatalError()
            }
        }()

        override var intrinsicContentSize: CGSize {
            return contentSize
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let script = """
                [document.body.scrollWidth > document.body.clientWidth ? document.body.scrollWidth : document.getElementById('tex').getBoundingClientRect().width,
                 document.body.scrollHeight > document.body.clientHeight ? document.body.scrollHeight : document.getElementById('container').getBoundingClientRect().height]
            """
            webView.evaluateJavaScript(script) { (result, error) in
                if let result = result as? Array<CGFloat> {
                    print(result)
                    self.contentSize = CGSize(width: result[0], height: result[1])
                    self.status = .finished
                }
            }
        }

        init() {
            super.init(frame: .zero, configuration: WKWebViewConfiguration())

            scrollView.isScrollEnabled = false
            scrollView.isUserInteractionEnabled = false
            scrollView.bounces = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false

            navigationDelegate = self

            isOpaque = false
            backgroundColor = .white

        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func loadLatex(_ latex: String, options: [KatexRenderer.Key : Any]? = nil) {
            let htmlString = getHtmlString(latex: latex, options: options)
            status = .loading
            loadHTMLString(htmlString, baseURL: URL(fileURLWithPath: Self.templateHtmlPath))
        }

        func getHtmlString(latex: String, options: [KatexRenderer.Key : Any]? = nil) -> String {
            let htmlString = Self.templateHtmlString
            guard let insertHtml = KatexRenderer.renderToString(latex: latex, options: options) else {
                return ""
            }
            return htmlString.replacingOccurrences(of: "$LATEX$", with: insertHtml)
        }
    }
}