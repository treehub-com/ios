//
//  ViewController.swift
//  Treehub
//
//  Created by John M Clark on 2/7/17.
//  Copyright © 2017 Treehub LLC. All rights reserved.
//

import Alamofire
import SwiftyJSON
import UIKit
import WebKit
import Zip

class ViewController: UIViewController {

    var webView: WKWebView!
    
    let libraryURL = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    
    var defaultPackages: [String] = ["app", "test", "package-manager"]
    var installingPackages: [String: Bool] = [:]
    
    override func loadView() {
        self.webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        self.view = webView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.ensureDirectories()
        self.installDefaultPackages() // Will call defaultPackagesInstalled() after packages are installed
    }

    private func ensureDirectories() {

        // Ensure webview directory exists
        let webviewURL = libraryURL.appendingPathComponent("webview", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: webviewURL.path, withIntermediateDirectories: true, attributes: nil)
        
        // Ensure webview files exist
        let webviewIndexDest = webviewURL.appendingPathComponent("index.html")
        let webviewIndexSource = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "files/webview")!
        if (!FileManager.default.fileExists(atPath: webviewIndexDest.path)) {
            try! FileManager.default.copyItem(atPath: webviewIndexSource.path, toPath: webviewIndexDest.path)
        }
        
        // Ensure server directory exists
        let serverURL = libraryURL.appendingPathComponent("server", isDirectory: true)
        try? FileManager.default.createDirectory(atPath: serverURL.path, withIntermediateDirectories: true, attributes: nil)
        
        // TODO Ensure server files exist
        
        // Ensure packages directory exists
        let packagesURL = libraryURL.appendingPathComponent("packages", isDirectory: true)
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

    private func defaultPackagesInstalled() {
        self.createPackagesJSON()
        self.startServer()
        self.loadWebview()
    }

    private func createPackagesJSON() {
        let packagesURL = libraryURL.appendingPathComponent("packages", isDirectory: true)
        let packages = try! FileManager.default.contentsOfDirectory(atPath: packagesURL.path)

        var packagesJSON = JSON(data: "{}".data(using: .utf8)!)

        for package in packages {
            let json = try! String(contentsOfFile: packagesURL.appendingPathComponent(package + "/treehub.json").path)
            packagesJSON[package] = JSON(data: json.data(using: .utf8, allowLossyConversion: false)!)
        }

        try! packagesJSON.rawString()!.write(to: libraryURL.appendingPathComponent("packages.json"), atomically: true, encoding: .utf8)

//        print("packages.json created")
    }

    private func startServer() {
//        print("starting server")
        // TODO
    }

    private func loadWebview() {
        let content = try! String(contentsOfFile: libraryURL.appendingPathComponent("webview/index.html").path)
        self.webView.loadHTMLString(content, baseURL: libraryURL.appendingPathComponent("packages", isDirectory: true))
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
//        print("installing", package, version)
    }
    
    private func unzipPackage(source: URL, destination: URL) {
//        print("unzipping", source, "to", destination)

        do {
        try Zip.unzipFile(source, destination: destination, overwrite: true, password: nil, progress: nil)
        } catch {
            print(error)
        }
    }
}

