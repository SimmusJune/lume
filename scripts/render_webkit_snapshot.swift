import AppKit
import Foundation
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let inputURL: URL
    private let outputURL: URL
    private let width: Int
    private let height: Int

    init(inputURL: URL, outputURL: URL, width: Int, height: Int) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.width = width
        self.height = height

        let configuration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height), configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    func start() {
        let request = URLRequest(url: inputURL)
        webView.load(request)
        RunLoop.main.run()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: self.width, height: self.height)
            config.snapshotWidth = NSNumber(value: self.width)

            webView.takeSnapshot(with: config) { image, error in
                if let error {
                    fputs("Snapshot failed: \(error)\n", stderr)
                    exit(1)
                }

                guard let image else {
                    fputs("Snapshot failed: no image\n", stderr)
                    exit(1)
                }

                guard
                    let tiff = image.tiffRepresentation,
                    let rep = NSBitmapImageRep(data: tiff),
                    let png = rep.representation(using: .png, properties: [:])
                else {
                    fputs("PNG encoding failed\n", stderr)
                    exit(1)
                }

                do {
                    try png.write(to: self.outputURL)
                    exit(0)
                } catch {
                    fputs("Write failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fputs("Navigation failed: \(error)\n", stderr)
        exit(1)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fputs("Provisional navigation failed: \(error)\n", stderr)
        exit(1)
    }
}

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift render_webkit_snapshot.swift <input> <output> <width>x<height>\n", stderr)
    exit(1)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let size = CommandLine.arguments[3]

let parts = size.split(separator: "x")
guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else {
    fputs("Invalid size: \(size)\n", stderr)
    exit(1)
}

_ = NSApplication.shared
let renderer = Renderer(inputURL: input, outputURL: output, width: width, height: height)
renderer.start()
