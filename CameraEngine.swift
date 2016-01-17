//
//  CameraEngine.swift
//  X
//
//  Created by Thomas Hocking on 1/15/16.
//  Copyright © 2016 Thomas Hocking. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary
import Photos

extension String {
    
    func stringByAppendingPathComponent(path: String) -> String {
        
        let nsSt = self as NSString
        
        return nsSt.stringByAppendingPathComponent(path)
    }
}

class CameraEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate{
    var session: AVCaptureSession?
    var preview: AVCaptureVideoPreviewLayer?
    var captureQueue: dispatch_queue_t?
    var audioConnection: AVCaptureConnection?
    var videoConnection: AVCaptureConnection?
    
    var encoder:VideoEncoder?
    var isCapturing = false
    var isPaused = false
    var discont = false
    var currentFile = 0
    var timeOffset: CMTime?
    var lastVideo: CMTime?
    var lastAudio: CMTime?
    
    var cx = 0
    var cy = 0
    var channels = UInt32(0)
    var sampleRate = 0.0
    
    init(sender: AnyObject) {
        super.init()
        self.startup()
    }
    
    func startup(){
        self.session = AVCaptureSession()
        
        do {
            
            //let backCamera = self.deviceWithMediaTypeWithPosition(AVMediaTypeVideo, position: AVCaptureDevicePosition.Back)
            let backCamera = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
            let input = try AVCaptureDeviceInput(device: backCamera)
            self.session?.addInput(input)
        } catch let error as NSError{
            print(error)
        }
        
        do {
            let mic = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeAudio)
            let micInput = try AVCaptureDeviceInput(device: mic)
            self.session?.addInput(micInput)
        }catch let error as NSError{
            print(error)
        }
        
        self.captureQueue = dispatch_queue_create("video capture", DISPATCH_QUEUE_SERIAL)
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.setSampleBufferDelegate(self, queue: self.captureQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_32BGRA)]
        self.session?.addOutput(videoOutput)
        
        var vc:AVCaptureConnection?
        for connection:AVCaptureConnection in videoOutput.connections as! [AVCaptureConnection]{
            for port:AVCaptureInputPort in connection .inputPorts as! [AVCaptureInputPort]{
                if port.mediaType == AVMediaTypeVideo{
                    vc = connection
                }
            }
        }
        
        print(vc?.videoOrientation)
        vc?.videoOrientation = .Portrait
        
        self.videoConnection = videoOutput.connectionWithMediaType(AVMediaTypeVideo)
        let actual = videoOutput.videoSettings
        self.cy = (actual["Height"]?.integerValue)!
        self.cx = (actual["Width"]?.integerValue)!
        
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: self.captureQueue)
        self.session?.addOutput(audioOutput)
        self.audioConnection = audioOutput.connectionWithMediaType(AVMediaTypeAudio)
        
        self.session?.startRunning()
        self.preview = AVCaptureVideoPreviewLayer(session: self.session)
        self.preview?.videoGravity = AVLayerVideoGravityResizeAspectFill
    }
    
    func startCapture(){
        let lockQueue = dispatch_queue_create("LockQueue", nil)
        dispatch_sync(lockQueue) {
            // code
            if !self.isCapturing{
                self.isPaused = false
                self.discont = false
                self.timeOffset = CMTimeMake(0, 0)
                self.isCapturing = true
            }
        }
    }
    
    func stopCapture(){
        let lockQueue = dispatch_queue_create("LockQueue", nil)
        dispatch_sync(lockQueue) {
            // code
            if self.isCapturing{
                let fileName = String(format: "capture%d.mp4", arguments: [self.currentFile])
                let path = NSTemporaryDirectory().stringByAppendingString(fileName)
                let url = NSURL.fileURLWithPath(path)
                self.currentFile++
                
                self.isCapturing = false
                dispatch_async(self.captureQueue!, { () -> Void in
                    self.encoder?.finishWithCompletionHandler({ () -> () in
                        self.isCapturing = false
                        self.encoder = nil
                        PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
                            PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(url)
                            }, completionHandler: { (done, error) -> Void in
                                do {
                                    print("save complete!")
                                    try NSFileManager.defaultManager().removeItemAtPath(path)
                                }catch let error as NSError{
                                    print(error)
                                }
                        })
                    })
                })
            }
        }
    }
    
    func adjustTime(sample:CMSampleBufferRef, offset:CMTime) -> CMSampleBufferRef{
        var count = CMItemCount()
        CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count)
        
        var info = [CMSampleTimingInfo](count: count,
            repeatedValue: CMSampleTimingInfo(duration: CMTimeMake(0, 0),
                presentationTimeStamp: CMTimeMake(0, 0),
                decodeTimeStamp: CMTimeMake(0, 0)))
        CMSampleBufferGetSampleTimingInfoArray(sample, count, &info, &count);
        
        for i in 0..<count {
            info[i].decodeTimeStamp = CMTimeSubtract(info[i].decodeTimeStamp, offset);
            info[i].presentationTimeStamp = CMTimeSubtract(info[i].presentationTimeStamp, offset);
        }
        
        var out : CMSampleBuffer? = nil
        CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, &info, &out)
        return out!
    }
    
    func setAudioFormat(fmt:CMFormatDescriptionRef){
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)
        self.sampleRate = asbd.memory.mSampleRate
        self.channels = asbd.memory.mChannelsPerFrame
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, var didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        var isVideo = true
        let lockQueue = dispatch_queue_create("LockQueue2", nil)
        dispatch_sync(lockQueue) {
            // code
            if !self.isCapturing {
                return
            }
            
            if connection != self.videoConnection{
                isVideo = false
            }
            
            if self.encoder == nil && !isVideo{
                let fmt = CMSampleBufferGetFormatDescription(sampleBuffer)
                self.setAudioFormat(fmt!)
                let fileName = String(format: "capture%d.mp4", arguments: [self.currentFile])
                let path =  NSTemporaryDirectory().stringByAppendingPathComponent(fileName)
                self.encoder = VideoEncoder().encoderForPath(path, height: self.cy, width: self.cx, channels: self.channels, samples: self.sampleRate)
            }
            if self.discont{
                if isVideo{
                    return
                }
                self.discont = false
                var pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let last = isVideo ? self.lastVideo : self.lastAudio

                if (last!.flags.rawValue & CMTimeFlags.Valid.rawValue) != 0{
                    if ((self.timeOffset?.flags.rawValue)! & CMTimeFlags.Valid.rawValue != 0){
                        pts = CMTimeSubtract(pts, self.timeOffset!)
                    }
                    let offset = CMTimeSubtract(pts, last!)
                    if self.timeOffset?.value == 0{
                        self.timeOffset = offset
                    }else{
                        self.timeOffset = CMTimeAdd(self.timeOffset!, offset)
                    }
                }
               
                self.lastAudio?.flags = CMTimeFlags()
                self.lastVideo?.flags = CMTimeFlags()
            }
            
            if self.timeOffset?.value > 0 {
                sampleBuffer = self.adjustTime(sampleBuffer, offset: self.timeOffset!)
            }
            
            var pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            var dur = CMSampleBufferGetDuration(sampleBuffer)
            if dur.value > 0{
                pts = CMTimeAdd(pts, dur)
            }
            
            if isVideo{
                self.lastVideo = pts
            }else{
                self.lastAudio = pts
            }
            
        }
        self.encoder?.encodeFrame(sampleBuffer, isVideo: isVideo)
    }
    
    func shutDown(){
        if self.session != nil{
            self.session?.stopRunning()
            self.session = nil
        }
        self.encoder?.finishWithCompletionHandler({ () -> () in
            print("Done")
        })
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        return self.preview!
    }
    
    
   /* func deviceWithMediaTypeWithPosition(mediaType: NSString, position: AVCaptureDevicePosition) -> AVCaptureDevice {
        let devices: NSArray = AVCaptureDevice.devicesWithMediaType(mediaType as String)
        var captureDevice: AVCaptureDevice = devices.firstObject as! AVCaptureDevice
        for device in devices {
            let d = device as! AVCaptureDevice
            if d.position == position {
                captureDevice = d
                break;
            }
        }
        return captureDevice
    }
    */
    
}
