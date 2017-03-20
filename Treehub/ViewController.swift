//
//  ViewController.swift
//  Treehub
//
//  Created by John M Clark on 2/7/17.
//  Copyright © 2017 Treehub LLC. All rights reserved.
//

import Alamofire
import GCDWebServers
import SwiftyJSON
import UIKit
import WebKit
import Zip

class ViewController: UIViewController, WKScriptMessageHandler {

    var webView: WKWebView!
    var webserver: GCDWebServer!
    
    let libraryURL = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var packagesURL: URL!
    
    var defaultPackages: [String] = ["app", "test", "package-manager"]
    var installingPackages: [String: Bool] = [:]
    var packagesJSON: JSON = JSON(data: "{}".data(using: .utf8)!)
    
    override func loadView() {
        // Load WebView
//        let contentController = WKUserContentController();
//        contentController.add(self, name: "packages");
//
//        let config = WKWebViewConfiguration()
//        config.userContentController = contentController

        self.webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        self.view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.ensureDirectories()
        self.installDefaultPackages() // Will call defaultPackagesInstalled() after packages are installed
        self.startWebserver()
    }

    private func defaultPackagesInstalled() {
        self.createPackagesJSON()
        self.startServer()
        self.loadWebview()
    }


    private func ensureDirectories() {

        // Ensure webview directory exists
        let webviewURL = libraryURL.appendingPathComponent("webview", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: webviewURL.path, withIntermediateDirectories: true, attributes: nil)
        
        // Ensure webview files exist
        let webviewIndexDest = webviewURL.appendingPathComponent("index.html")
        let webviewIndexSource = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "files/webview")!
        // TODO don't always overwrite
        if (FileManager.default.fileExists(atPath: webviewIndexDest.path)) {
            try! FileManager.default.removeItem(at: webviewIndexDest)
        }
        try! FileManager.default.copyItem(atPath: webviewIndexSource.path, toPath: webviewIndexDest.path)

        // Ensure server directory exists
        let serverURL = libraryURL.appendingPathComponent("server", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: serverURL.path, withIntermediateDirectories: true, attributes: nil)
        
        // TODO Ensure server files exist
        
        // Ensure packages directory exists
        self.packagesURL = libraryURL.appendingPathComponent("packages", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: packagesURL.path, withIntermediateDirectories: true, attributes: nil)
    }

    private func installDefaultPackages() {
        let packagesURL = libraryURL.appendingPathComponent("packages", isDirectory: true)
        let packages = try! FileManager.default.contentsOfDirectory(atPath: packagesURL.path)
//        print(packages)
        for package in self.defaultPackages {
            if (!packages.contains(package)) {
                self.installingPackages[package] = true
                self.installPackage(package: package, destination: packagesURL)
            }
        }
        if (self.installingPackages.count == 0) {
            self.defaultPackagesInstalled();
        }
    }

    private func startWebserver() {
        // Load WebServer
        webserver = GCDWebServer()

        // Note that Routes are evaluated last to first

        // Default is to load index.html
        webserver.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self, processBlock: {request in
            let content = try! String(contentsOfFile: self.libraryURL.appendingPathComponent("webview/index.html").path)
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "text/html")
        })
        // Any .js file gets pulled from packages dir
        webserver.addHandler(forMethod: "GET", pathRegex: "/.*\\.js", request: GCDWebServerRequest.self, processBlock: {request in
            let content = try! String(contentsOfFile: self.packagesURL.appendingPathComponent("." + (request?.path)!).path)
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "application/javascript")
        })
        // packages.json
        webserver.addHandler(forMethod: "GET", path: "/packages.json", request: GCDWebServerRequest.self, processBlock: {request in
            return  GCDWebServerDataResponse(data: self.packagesJSON.rawString()?.data(using: .utf8), contentType: "application/json")
        })
        // POST requests
        webserver.addDefaultHandler(forMethod: "POST", request: GCDWebServerRequest.self, processBlock: {request in
            let content = "{}"
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "application/json")
        })

        webserver.start(withPort: 8985, bonjourName: "Treehub")

    }

    private func createPackagesJSON() {
        let packagesURL = libraryURL.appendingPathComponent("packages", isDirectory: true)
        let installedPackages = try! FileManager.default.contentsOfDirectory(atPath: packagesURL.path)

        for package in installedPackages {
            let json = try! String(contentsOfFile: packagesURL.appendingPathComponent(package + "/treehub.json").path)
            self.packagesJSON[package] = JSON(data: json.data(using: .utf8, allowLossyConversion: false)!)
        }

//        print(self.packagesJSON.rawString()!)

//        print("packages.json created")
    }

    private func startServer() {
//        print("starting server")
        // TODO
    }

    private func loadWebview() {
        self.webView.load(URLRequest(url: URL(string:"http://localhost:8985")!))
    }

    /* Javascript Callback Functions */

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let request = JSON(data: (message.body as! String).data(using: .utf8)!)
        print(request)
        if (message.name == "packages") {
            var response = JSON(data: "{}".data(using: .utf8)!)
            response["id"] = request["id"]
            response["status"] = JSON(200)
            response["body"] = JSON(self.packagesJSON.rawString()!)
            print("get packages")
            self.webView.evaluateJavaScript("window._iosMessage(" + response.rawString()! + ");", completionHandler: nil)
        }
    }

    /* Utility Functions */

    private func installPackage(package: String, destination: URL, version: String = "latest") {
        
        let url = URL(string: "https://packages.treehub.com/" + package + "/" + version + ".zip")
        
        let cacheDestination: DownloadRequest.DownloadFileDestination = { _, _ in
            let cachesURI = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let tempURI = cachesURI.appendingPathComponent(package + "-" + version + ".zip")
            
            return (tempURI, [.removePreviousFile, .createIntermediateDirectories])
        }
        
        let destinationURL = destination.appendingPathComponent(package, isDirectory: true)
        try? FileManager.default.createDirectory(atPath: destinationURL.path, withIntermediateDirectories: true, attributes: nil)
        
        Alamofire.download(url!, to: cacheDestination).response { response in
            if response.error == nil {
                self.unzipPackage(source: response.destinationURL!, destination: destinationURL)
            } else {
                // TODO record error
            }
            self.installingPackages[package] = false

            // If we are the last to finish, call defaultPackagesInstalled()
            for (_,value) in self.installingPackages {
                if (value == true) {
                    return;
                }
            }
            self.defaultPackagesInstalled()
        }
    }
    
    private func unzipPackage(source: URL, destination: URL) {
        do {
            try Zip.unzipFile(source, destination: destination, overwrite: true, password: nil, progress: nil)
        } catch {
            print(error)
        }
    }
}

