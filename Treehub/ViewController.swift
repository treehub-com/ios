//
//  ViewController.swift
//  Treehub
//
//  Created by John M Clark on 2/7/17.
//  Copyright © 2017 Treehub LLC. All rights reserved.
//

import Alamofire
import GCDWebServers
import PromiseKit
import SwiftyJSON
import UIKit
import WebKit
import Zip

class ViewController: UIViewController, WKScriptMessageHandler {

    var webview: WKWebView!
    var webserver: GCDWebServer!
    var server: WKWebView! // TODO replace this with JavascriptCore
    var serverLoaded: ((_ error: Error?) -> Void)! // Called via server.js after routes are loaded to resolve a promise

    var requests: [String: GCDWebServerCompletionBlock] = [:]

    var filesURL: URL!
    var packagesURL: URL!
    
    var defaultPackages: [String] = ["app", "api", "package-manager"]

    override func loadView() {
        // Set URLs
        let libraryURL = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.filesURL = Bundle.main.bundleURL.appendingPathComponent("files", isDirectory: true)
        self.packagesURL = libraryURL.appendingPathComponent("packages", isDirectory: true)

        // Set webview
        self.webview = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        self.view = webview
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.startWebserver()
        self.webview.load(URLRequest(url: URL(string:"http://localhost:8985")!))
        
        
        self.ensureDefaultPackages()
            .then { _ in
                return self.startServer()
            }
            .then { _ in
                self.webview.evaluateJavaScript("window._load()", completionHandler: nil)
            }
            .catch { error in
                print(error)
            }

    }

    private func startWebserver() {
        // Load WebServer
        self.webserver = GCDWebServer()

        // Note that Routes are evaluated last to first

        // Default is to load index.html
        self.webserver.addDefaultHandler(forMethod: "GET", request: GCDWebServerRequest.self, processBlock: {request in
            let content = try! String(contentsOfFile: self.filesURL.appendingPathComponent("index.html").path)
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "text/html")
        })
        // Any .js file gets pulled from packages dir
        self.webserver.addHandler(forMethod: "GET", pathRegex: "/.*\\.js", request: GCDWebServerRequest.self, processBlock: {request in
            let content = try! String(contentsOfFile: self.packagesURL.appendingPathComponent("." + (request?.path)!).path)
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "application/javascript")
        })
        // packages.json
        self.webserver.addHandler(forMethod: "GET", path: "/packages.json", request: GCDWebServerRequest.self, processBlock: {request in
            return  GCDWebServerDataResponse(data: self.getPackagesJSON().rawString()?.data(using: .utf8), contentType: "application/json")
        })
        // _ files
        self.webserver.addHandler(forMethod: "GET", pathRegex: "/_/.*", request: GCDWebServerRequest.self, processBlock: {request in
            let path = request?.path.replacingOccurrences(of: "/_/", with: "")
            let content = try! String(contentsOfFile: self.filesURL.appendingPathComponent(path!).path)
            return  GCDWebServerDataResponse(data: content.data(using: .utf8), contentType: "text/html")
        })
        // POST requests
        self.webserver.addDefaultHandler(forMethod: "POST", request: GCDWebServerDataRequest.self, asyncProcessBlock: { request, completionBlock in
            // TODO handle internal routes in swift
            let path = (request?.path)!

            if path.hasPrefix("/_/") {
                if path == "/_/package/install" {
                    let body = JSON((request as! GCDWebServerDataRequest).data)
                    self.installPackage(package: body["name"].stringValue)
                        .then { _ in
                            completionBlock!(GCDWebServerDataResponse(data: "true".data(using: .utf8), contentType: "application/json"))
                        }
                        .catch { error in
                            print(error)
                        }
                    return
                } else if path == "/_/package/uninstall" {
                    completionBlock!(GCDWebServerDataResponse(data: "true".data(using: .utf8), contentType: "application/json"))
                } else {
                    let response = GCDWebServerDataResponse(data: "{\"message\": \"Unknown Route\"}".data(using: .utf8), contentType: "application/json")
                    response?.statusCode = 404
                    completionBlock!(response)
                }
            } else {
                let id = UUID.init().uuidString
                self.requests[id] = completionBlock
                var serverRequest = JSON(data: "{}".data(using: .utf8)!)
                serverRequest["id"] = JSON.init(stringLiteral: id)
                serverRequest["route"] = JSON.init(stringLiteral: path)
                serverRequest["body"] = JSON.init(stringLiteral: "")
                if (request?.hasBody())! {
                    serverRequest["body"] = JSON.init(stringLiteral: String(data: (request as! GCDWebServerDataRequest).data, encoding: .utf8)!)
                }

                self.server.evaluateJavaScript("request(" + serverRequest.rawString()! + ");", completionHandler: nil)
            }
        })

        self.webserver.start(withPort: 8985, bonjourName: "Treehub")

    }

    private func startServer() -> Promise<Void> {
        // Load routes
        // TODO do this a better way
        var routes = JSON(data: "{}".data(using: .utf8)!)
        for (package, json) in self.getPackagesJSON() {
            if let path = json["route"].string {
                // TODO catch this error
                let packagePath = self.packagesURL.appendingPathComponent(package)
                let route = try! String(contentsOfFile: packagePath.appendingPathComponent(path).path)
                routes[package] = JSON.init(stringLiteral: route)
            }
        }

        let contentController = WKUserContentController();
        contentController.add(self, name: "loaded");
        contentController.add(self, name: "response");

        contentController.addUserScript(WKUserScript(source: "const files = " + routes.rawString()!, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        self.server = WKWebView(frame: .zero, configuration: config)

        self.server.load(URLRequest(url: URL(string:"http://localhost:8985/_/server.html")!)) // Will call loadWebview() after loading routes

        return Promise { fulfill, reject in
            self.serverLoaded = { (_ error: Error?) -> Void in
                if error == nil {
                    fulfill()
                } else {
                    reject(error!)
                }
            }
        }
    }

    private func loadWebview() {
        self.webview.load(URLRequest(url: URL(string:"http://localhost:8985")!))
    }

    /* Javascript Callback Functions */

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.name == "loaded") {
            self.serverLoaded(nil)
        }
        if (message.name == "response") {
            let rawResponse = JSON(data: (message.body as! String).data(using: .utf8)!)
            let id = rawResponse["id"].string!
            if let completionHandler = self.requests[id] {
                let response = GCDWebServerDataResponse(data: rawResponse["body"].rawString()?.data(using: .utf8), contentType: "application/json")
                response?.statusCode = rawResponse["status"].int!
                completionHandler(response)
                self.requests.removeValue(forKey: id)
            }
        }
    }

    /* Utility Functions */

    private func ensureDefaultPackages() -> Promise<Void> {
        // Ensure packages directory exists
        try? FileManager.default.createDirectory(atPath: packagesURL.path, withIntermediateDirectories: true, attributes: nil)

        // Get installed packages
        let packages = try! FileManager.default.contentsOfDirectory(atPath: self.packagesURL.path)

        var promises: [Promise<Void>] = []

        for package in self.defaultPackages {
            if (!packages.contains(package)) {
                promises.append(self.installPackage(package: package))
            }
        }
        if (promises.count > 0) {
            return join(promises)
        }

        return Promise { fulfill, reject in
            fulfill()
        }
    }

    private func installPackage(package: String, version: String = "latest") -> Promise<Void> {
        
        let url = URL(string: "https://packages.treehub.com/" + package + "/" + version + ".zip")
        
        let cacheDestination: DownloadRequest.DownloadFileDestination = { _, _ in
            let cachesURI = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let tempURI = cachesURI.appendingPathComponent(package + "-" + version + ".zip")
            
            return (tempURI, [.removePreviousFile, .createIntermediateDirectories])
        }
        
        let destinationURL = self.packagesURL.appendingPathComponent(package, isDirectory: true)
        try? FileManager.default.createDirectory(atPath: destinationURL.path, withIntermediateDirectories: true, attributes: nil)

        return Promise { fulfill, reject in
            Alamofire.download(url!, to: cacheDestination).response { response in
                if response.error == nil {
                    do {
                        try Zip.unzipFile(response.destinationURL!, destination: destinationURL, overwrite: true, password: nil, progress: nil)
                        fulfill()
                    } catch {
                        reject(error)
                    }
                } else {
                    reject(response.error!)
                }
            }
        }
    }

    private func getPackagesJSON() -> JSON {
        let installedPackages = try! FileManager.default.contentsOfDirectory(atPath: packagesURL.path)

        var packagesJSON: JSON = JSON(data: "{}".data(using: .utf8)!)

        for package in installedPackages {
            let json = try! String(contentsOfFile: self.packagesURL.appendingPathComponent(package + "/treehub.json").path)
            packagesJSON[package] = JSON(data: json.data(using: .utf8, allowLossyConversion: false)!)
        }
        return packagesJSON
    }
}

