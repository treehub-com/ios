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
    var server: WKWebView! // TODO replace this with JavascriptCore

    var filesURL: URL!
    var packagesURL: URL!
    
    var defaultPackages: [String] = ["app", "test", "package-manager"]
    var installingPackages: [String: Bool] = [:]
    var packagesJSON: JSON = JSON(data: "{}".data(using: .utf8)!)
    
    override func loadView() {
        // Set URLs
        let libraryURL = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.filesURL = libraryURL.appendingPathComponent("files", isDirectory: true)
        self.packagesURL = libraryURL.appendingPathComponent("packages", isDirectory: true)

        // Set webview
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
        // Ensure html directory exists/populated
        try? FileManager.default.createDirectory(atPath: self.filesURL.path, withIntermediateDirectories: true, attributes: nil)
        let files = try! FileManager.default.contentsOfDirectory(atPath: Bundle.main.bundleURL.appendingPathComponent("files", isDirectory: true).path)

        for file in files {
            let source = Bundle.main.bundleURL.appendingPathComponent("files/" + file)
            let dest = self.filesURL.appendingPathComponent(file)
            // TODO don't always overwrite
            if (FileManager.default.fileExists(atPath: dest.path)) {
                try! FileManager.default.removeItem(at: dest)
            }
            try! FileManager.default.copyItem(atPath: source.path, toPath: dest.path)
        }

        // Ensure packages directory exists
        try? FileManager.default.createDirectory(atPath: packagesURL.path, withIntermediateDirectories: true, attributes: nil)
        
    }

    private func installDefaultPackages() {
        let packages = try! FileManager.default.contentsOfDirectory(atPath: self.packagesURL.path)

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
            let content = try! String(contentsOfFile: self.filesURL.appendingPathComponent("index.html").path)
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
        // _ files
        webserver.addHandler(forMethod: "GET", pathRegex: "/_/.*", request: GCDWebServerRequest.self, processBlock: {request in
            let path = request?.path.replacingOccurrences(of: "/_/", with: "")
            let content = try! String(contentsOfFile: self.filesURL.appendingPathComponent(path!).path)
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "text/html")
        })
        // POST requests
        webserver.addDefaultHandler(forMethod: "POST", request: GCDWebServerRequest.self, processBlock: {request in
            let content = "{}"
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "application/json")
        })

        webserver.start(withPort: 8985, bonjourName: "Treehub")

    }

    private func createPackagesJSON() {
        let installedPackages = try! FileManager.default.contentsOfDirectory(atPath: packagesURL.path)

        for package in installedPackages {
            let json = try! String(contentsOfFile: packagesURL.appendingPathComponent(package + "/treehub.json").path)
            self.packagesJSON[package] = JSON(data: json.data(using: .utf8, allowLossyConversion: false)!)
        }
    }

    private func startServer() {
        let contentController = WKUserContentController();
        contentController.add(self, name: "packages");
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        self.server = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        self.server.load(URLRequest(url: URL(string:"http://localhost:8985/_/server.html")!))

        // TODO load routes

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

