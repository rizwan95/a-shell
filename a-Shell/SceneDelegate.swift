//
//  SceneDelegate.swift
//  a-Shell
//
//  Created by Nicolas Holzschuch on 30/06/2019.
//  Copyright © 2019 AsheKube. All rights reserved.
//

import UIKit
import SwiftUI
import WebKit
import ios_system

var messageHandlerAdded = false
var externalKeyboardPresent: Bool?
let endOfTransmission = "\u{0004}"  // control-D, used to signal end of transmission
let escape = "\u{001B}"
let toolbarHeight: CGFloat = 35

// Need: dictionary connecting userContentController with output streams.


var screenWidth: CGFloat {
    if screenOrientation.isPortrait {
        return UIScreen.main.bounds.size.width
    } else {
        return UIScreen.main.bounds.size.height
    }
}
var screenHeight: CGFloat {
    if screenOrientation.isPortrait {
        return UIScreen.main.bounds.size.height
    } else {
        return UIScreen.main.bounds.size.width
    }
}
var screenOrientation: UIInterfaceOrientation {
    return UIApplication.shared.statusBarOrientation
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate, WKScriptMessageHandler {
    var window: UIWindow?
    var webView: WKWebView?
    var contentView: ContentView?
    var width = 80
    var height = 80
    var stdin_pipe: Pipe? = nil
    var stdout_pipe: Pipe? = nil
    var persistentIdentifier: String? = nil
    var stdin_file: UnsafeMutablePointer<FILE>? = nil
    var stdout_file: UnsafeMutablePointer<FILE>? = nil
    private let commandQueue = DispatchQueue(label: "executeCommand", qos: .utility) // low priority
    // Buttons and toolbars:

    var fontSize: CGFloat {
        let deviceModel = UIDevice.current.model
        if (deviceModel.hasPrefix("iPad")) {
            let minFontSize: CGFloat = screenWidth / 50
            // print("Screen width = \(screenWidth), fontSize = \(minFontSize)")
            if (minFontSize > 18) { return 18.0 }
            else { return minFontSize }
        } else {
            let minFontSize: CGFloat = screenWidth / 23
            // print("Screen width = \(screenWidth), fontSize = \(minFontSize)")
            if (minFontSize > 15) { return 15.0 }
            else { return minFontSize }
        }
    }
    
    @objc private func tabAction(_ sender: UIBarButtonItem) {
        webView?.evaluateJavaScript("window.term_.io.onVTKeystroke(\"" + "\u{0009}" + "\");") { (result, error) in
            if error != nil {
                print(error)
            }
            if (result != nil) {
                print(result)
            }
        }
    }

    @objc private func upAction(_ sender: UIBarButtonItem) {
        webView?.evaluateJavaScript("window.term_.io.onVTKeystroke(\"" + escape + "[A\");") { (result, error) in
            if error != nil {
                print(error)
            }
            if (result != nil) {
                print(result)
            }
        }
    }
    
    @objc private func downAction(_ sender: UIBarButtonItem) {
        webView?.evaluateJavaScript("window.term_.io.onVTKeystroke(\"" + escape + "[B\");") { (result, error) in
            if error != nil {
                print(error)
            }
            if (result != nil) {
                print(result)
            }
            
        }
    }
    
    @objc private func leftAction(_ sender: UIBarButtonItem) {
        webView?.evaluateJavaScript("window.term_.io.onVTKeystroke(\"" + escape + "[D\");") { (result, error) in
            if error != nil {
                print(error)
            }
            if (result != nil) {
                print(result)
            }
            
        }
    }

    @objc private func rightAction(_ sender: UIBarButtonItem) {
        webView?.evaluateJavaScript("window.term_.io.onVTKeystroke(\"" + escape + "[C\");") { (result, error) in
            if error != nil {
                print(error)
            }
            if (result != nil) {
                print(result)
            }
            
        }
    }

    var tabButton: UIBarButtonItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
        let tabButton = UIBarButtonItem(image: UIImage(systemName: "arrow.right.to.line.alt")!.withConfiguration(configuration), style: .plain, target: self, action: #selector(tabAction(_:)))
        tabButton.tintColor = .black
        return tabButton
    }

    
    var upButton: UIBarButtonItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
        let upButton = UIBarButtonItem(image: UIImage(systemName: "arrow.up")!.withConfiguration(configuration), style: .plain, target: self, action: #selector(upAction(_:)))
        upButton.tintColor = .black
        return upButton
    }
    
    var downButton: UIBarButtonItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
        let downButton = UIBarButtonItem(image: UIImage(systemName: "arrow.down")!.withConfiguration(configuration), style: .plain, target: self, action: #selector(downAction(_:)))
        downButton.tintColor = .black
        return downButton
    }
    
    var leftButton: UIBarButtonItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
        let leftButton = UIBarButtonItem(image: UIImage(systemName: "arrow.left")!.withConfiguration(configuration), style: .plain, target: self, action: #selector(leftAction(_:)))
        leftButton.tintColor = .black
        return leftButton
    }

    var rightButton: UIBarButtonItem {
        let configuration = UIImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
        let rightButton = UIBarButtonItem(image: UIImage(systemName: "arrow.right")!.withConfiguration(configuration), style: .plain, target: self, action: #selector(rightAction(_:)))
        rightButton.tintColor = .black
        return rightButton
    }

    public lazy var editorToolbar: UIToolbar = {
        var toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: (self.webView?.bounds.width)!, height: toolbarHeight))
        toolbar.items = [tabButton, UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil), upButton, downButton, leftButton, rightButton]
        return toolbar
    }()
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let cmd:String = message.body as! String
        if (cmd.hasPrefix("shell:")) {
            // Set COLUMNS to term width:
            setenv("COLUMNS", "\(width)".toCString(), 1);
            var command = cmd
            command.removeFirst("shell:".count)
            // set up streams for feedback:
            // Create new pipes for our own stdout/stderr
            // Get file for stdin that can be read from
            // Create new pipes for our own stdout/stderr
            stdin_pipe = Pipe()
            guard stdin_pipe != nil else { return }
            stdin_file = fdopen(stdin_pipe!.fileHandleForReading.fileDescriptor, "r")
            guard stdin_file != nil else { return }
            // Get file for stdout/stderr that can be written to
            stdout_pipe = Pipe()
            guard stdout_pipe != nil else { return }
            stdout_file = fdopen(stdout_pipe!.fileHandleForWriting.fileDescriptor, "w")
            guard stdout_file != nil else { return }
            // Call the following functions when data is written to stdout/stderr.
            stdout_pipe!.fileHandleForReading.readabilityHandler = self.onStdout
            commandQueue.async {
                thread_stdin = nil
                thread_stdout = nil
                thread_stderr = nil
                // Make sure we're running the right session
                ios_switchSession(self.persistentIdentifier?.toCString())
                ios_setStreams(self.stdin_file, self.stdout_file, self.stdout_file)
                // Execute command:
                ios_system(command)
                // Send info to the stdout handler that the command has finished:
                let writeOpen = fcntl(self.stdout_pipe!.fileHandleForWriting.fileDescriptor, F_GETFD)
                let readOpen = fcntl(self.stdout_pipe!.fileHandleForReading.fileDescriptor, F_GETFD)
                if (writeOpen >= 0) {
                    // Pipe is still open, send information to close it, once all output has been processed.
                    self.stdout_pipe!.fileHandleForWriting.write(endOfTransmission.data(using: .utf8)!)
                } else {
                    // Pipe has been closed, ready to run new command:
                    DispatchQueue.main.async {
                        self.webView?.evaluateJavaScript("window.term_.io.print(window.prompt); window.commandRunning = ''; ") { (result, error) in
                            if error != nil {
                                print(error)
                            }
                            if (result != nil) {
                                print(result)
                            }
                        }
                    }
                }
            }
        } else if (cmd.hasPrefix("width:")) {
            var command = cmd
            command.removeFirst("width:".count)
            width = Int(command) ?? 80

        } else if (cmd.hasPrefix("height:")) {
            var command = cmd
            command.removeFirst("height:".count)
            height = Int(command) ?? 80
        } else if (cmd.hasPrefix("input:")) {
            var command = cmd
            command.removeFirst("input:".count)
            guard let data = command.data(using: .utf8) else { return }
            ios_switchSession(self.persistentIdentifier?.toCString())
            ios_setStreams(self.stdin_file, self.stdout_file, self.stdout_file)
            guard stdin_pipe != nil else { return }
            stdin_pipe!.fileHandleForWriting.write(data)
        } else {
            // Usually debugging information
            NSLog("JavaScript message: \(message.body)")
        }
    }
    
    private var webContentView: UIView? {
        for subview in (webView?.scrollView.subviews)! {
            if subview.classForCoder.description() == "WKContentView" {
                return subview
            }
            // on iPhones, adding the toolbar has changed the name of the view:
            if subview.classForCoder.description() == "WKApplicationStateTrackingView_CustomInputAccessoryView" {
                return subview
            }
        }
        return nil
    }
    

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnecting:SceneSession` instead).
        // Use a UIHostingController as window root view controller
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            contentView = ContentView()
            window.rootViewController = UIHostingController(rootView: contentView)
            window.autoresizesSubviews = true
            self.window = window
            window.makeKeyAndVisible()
            self.persistentIdentifier = session.persistentIdentifier
            ios_switchSession(self.persistentIdentifier?.toCString())
            webView = contentView?.webview.webView
            // add a contentController that is specific to each webview
            webView?.configuration.userContentController = WKUserContentController()
            webView?.configuration.userContentController.add(self, name: "aShell") 
            if (!UIDevice.current.model.hasPrefix("iPad")) {
                // toolbar for iPhones and iPod touch
                webView?.addInputAccessoryView(toolbar: self.editorToolbar)
            } else {
                webContentView?.inputAssistantItem.leadingBarButtonGroups = [UIBarButtonItemGroup(barButtonItems:
                    [tabButton
                ], representativeItem: nil)]
                webContentView?.inputAssistantItem.trailingBarButtonGroups = [UIBarButtonItemGroup(barButtonItems:
                    [upButton, downButton,
                     leftButton, rightButton,
                ], representativeItem: nil)]
            }
            // Add a callback to change the buttons every time the user changes the input method:
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidChange), name: UITextInputMode.currentInputModeDidChangeNotification, object: nil)
            // And another to be called each time the keyboard is resized (including when an external KB is connected):
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidChange), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        }
    }

    
    @objc private func keyboardDidChange(notification: NSNotification) {
        let info = notification.userInfo
        let keyboardFrame = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        guard (keyboardFrame != nil) else { return }
        // resize webview
        
        if (!UIDevice.current.model.hasPrefix("iPad")) {
            // iPhones and iPod touch
            // iPhones or iPads: there is a toolbar at the bottom:
            if (keyboardFrame!.size.height <= toolbarHeight) {
                // Only the toolbar is left, hide it:
                self.editorToolbar.isHidden = true
                self.editorToolbar.isUserInteractionEnabled = false
            } else {
                self.editorToolbar.isHidden = false
                self.editorToolbar.isUserInteractionEnabled = true
            }
            return
        }
        
        // iPads:
        // Is there an external keyboard connected?
        if (info != nil) {
            // "keyboardFrameEnd" is a CGRect corresponding to the size of the keyboard plus the button bar.
            // It's 55 when there is an external keyboard connected, 300+ without.
            // Actual values may vary depending on device, but 60 seems a good threshold.
            externalKeyboardPresent = keyboardFrame!.size.height < 60
            webContentView?.inputAssistantItem.leadingBarButtonGroups = [UIBarButtonItemGroup(barButtonItems:
                [tabButton
            ], representativeItem: nil)]
            webContentView?.inputAssistantItem.trailingBarButtonGroups = [UIBarButtonItemGroup(barButtonItems:
                [upButton, downButton,
                 leftButton, rightButton,
            ], representativeItem: nil)]
        }
    }

    
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not neccessarily discarded (see `application:didDiscardSceneSessions` instead).
        NSLog("sceneDidDisconnect: \(scene).")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        NSLog("sceneDidBecomeActive: \(scene).")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        NSLog("sceneWillResignActive: \(scene).")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        NSLog("sceneWillEnterForeground: \(scene).")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        
        // TODO: save command history
        // TODO: + currently running command? (if it is an editor, say)
        NSLog("sceneDidEnterBackground: \(scene).")
    }

    // Called when the stdout file handle is written to
    private var dataBuffer = Data()

    private func outputToWebView(string: String) {
        guard (webView != nil) else { return }
        var parsedString = string.replacingOccurrences(of: "\"", with: "\\\"")
        while (parsedString.count > 0) {
            guard let firstReturn = parsedString.firstIndex(of: "\n") else {
                var command = "window.term_.io.print(\"" + parsedString + "\");"
                DispatchQueue.main.async {
                    self.webView!.evaluateJavaScript(command) { (result, error) in
                        if error != nil {
                            NSLog("Error in print; offending line = \(parsedString)")
                            print(error)
                        }
                        if (result != nil) {
                            print(result)
                        }
                    }
                }
                return
            }
            let firstLine = parsedString[..<firstReturn]
            var command = "window.term_.io.println(\"" + firstLine + "\");"
            DispatchQueue.main.async {
                self.webView!.evaluateJavaScript(command) { (result, error) in
                    if error != nil {
                        NSLog("Error in println; offending line = \(firstLine)")
                        print(error)
                    }
                    if (result != nil) {
                        print(result)
                    }
                }
            }
            parsedString.removeFirst(firstLine.count + 1)
        }
    }
    
    private func onStdout(_ stdout: FileHandle) {
        let data = stdout.availableData
        guard (data.count > 0) else {
            return
        }
        if let string = String(data: data, encoding: String.Encoding.utf8) {
            outputToWebView(string: string)
            if (string.contains(endOfTransmission)) {
                // Finished processing the output, can get back to prompt:
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript("window.term_.io.print(window.prompt); window.commandRunning = ''; ") { (result, error) in
                        if error != nil {
                            print(error)
                        }
                        if (result != nil) {
                            print(result)
                        }
                    }
                }
            }
        } else {
            NSLog("Couldn't convert data in stdout")
        }
    }
    
}
