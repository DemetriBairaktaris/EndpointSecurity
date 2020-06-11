//
//  AppDelegate.swift
//  drive_native
//
//  Created by admin on 6/7/20.
//  Copyright © 2020 admin. All rights reserved.
//

import Cocoa
import SystemExtensions

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        print("request replacement....")
        return OSSystemExtensionRequest.ReplacementAction.replace
        
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        print("System extension needs user approval.")
        
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        print("System extension request finished")
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        print("System extension request did not complete successfully")
        print(error)
    }
    

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        // Create an activation request and assign a delegate to
        // receive reports of success or failure.
        let hydratorID = "com.iManage.drive0.drive-native.hydrator"
        print("Requesting " + hydratorID)
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: hydratorID,
                             queue: DispatchQueue.main)
        request.delegate = self

        // Submit the request to the system.
        let extensionManager = OSSystemExtensionManager.shared
        extensionManager.submitRequest(request)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("termination...")
        print("Requesting deactivation of system extention")
        
    }
    
    


}

