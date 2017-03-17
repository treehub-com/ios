//
//  ViewController.swift
//  Treehub
//
//  Created by John M Clark on 2/7/17.
//  Copyright © 2017 Treehub LLC. All rights reserved.
//

import UIKit
import WebKit
import Zip

class ViewController: UIViewController {

    var webView: WKWebView!
    
    var defaultPackages: [String] = ["app", "test", "package-manager"]
    
    override func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Ensure Library files exist
        let libraryURI = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        // Ensure webview directory exists
        let webviewURI = libraryURI.appendingPathComponent("webview", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: webviewURI.path, withIntermediateDirectories: true, attributes: nil)

        // Ensure webview files exist
        let webviewIndexDest = webviewURI.appendingPathComponent("index.html")
        let webviewIndexSource = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "files/webview")!
        if (!FileManager.default.fileExists(atPath: webviewIndexDest.path)) {
            try! FileManager.default.copyItem(atPath: webviewIndexSource.path, toPath: webviewIndexDest.path)
        }
        
        // Ensure server directory exists
        let serverURI = libraryURI.appendingPathComponent("server", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: serverURI.path, withIntermediateDirectories: true, attributes: nil)
        
        // TODO Ensure server files exist
        
        // Ensure packages directory exists
        let packagesURI = libraryURI.appendingPathComponent("packages", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: packagesURI.path, withIntermediateDirectories: true, attributes: nil)

        
        // TODO Ensure default packages exist
        let packages = installedPackages(path: packagesURI.path)
        
        for package in defaultPackages {
            if (!packages.contains(package)) {
                installPackage(package: package)
            }
        }
        
        // TODO create package.json
        
        // TODO Start Server
        
        // TODO Load WebView
        let content = try! String(contentsOfFile: webviewIndexDest.path)
        webView.loadHTMLString(content, baseURL: packagesURI)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


//    private func ensureDir(dir: String) {
//        let libraryURI = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
//        let uri = libraryURI.appendingPathComponent(dir, isDirectory: true)
//        try? FileManager.default.createDirectory(atPath: uri.path, withIntermediateDirectories: true, attributes: nil)
//    }
    
    private func installedPackages(path: String) -> [String] {
        let paths = try! FileManager.default.contentsOfDirectory(atPath: path)
        return paths.map { aContent in (path as NSString).appendingPathComponent(aContent)}
    }
    
    private func installPackage(package: String, version: String = "latest") {
        print("installing", package, version)
    }
}

