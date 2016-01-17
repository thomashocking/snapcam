//
//  VideoEncoder.swift
//  X
//
//  Created by Thomas Hocking on 1/15/16.
//  Copyright © 2016 Thomas Hocking. All rights reserved.
//

import UIKit
import AVFoundation

class VideoEncoder: NSObject {
    var path = ""
    var writer: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?

    
    func encoderForPath(path:String, height:Int, width:Int, channels:UInt32, samples:Float64) -> VideoEncoder{
        let enc = VideoEncoder()
        enc.initPath(path, height: height, width: width, channels: channels, samples: samples)
        return enc
    }
    
    func initPath(path:String, height:Int, width:Int, channels:UInt32, samples:Float64){
        self.path = path
        
        do{
            try NSFileManager.defaultManager().removeItemAtPath(self.path)
        }catch let error as NSError{
            print(error)
        }
        
        let url = NSURL.fileURLWithPath(self.path)
        
        do{
            writer = try AVAssetWriter(URL: url, fileType: AVFileTypeQuickTimeMovie)
        }catch let error as NSError{
            print(error)
        }
        
        var settings = [AVVideoCodecKey:AVVideoCodecH264, AVVideoWidthKey:NSNumber(int: Int32(width)),  AVVideoHeightKey:NSNumber(int: Int32(height))]
        
        videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: settings)
        videoInput!.expectsMediaDataInRealTime = true
        writer!.addInput(videoInput!)
        //kAudioFormatMPEG4AAC)
        print(kAudioFormatProperty_AvailableEncodeNumberChannels)
           
        settings = [AVFormatIDKey:NSNumber(unsignedInt: kAudioFormatMPEG4AAC), AVNumberOfChannelsKey:NSNumber(int: Int32(channels)), AVSampleRateKey:NSNumber(float: Float(samples)), AVEncoderBitRateKey:NSNumber(int: 64000)]
        
        audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: settings)
        audioInput!.expectsMediaDataInRealTime = true
        writer!.addInput(audioInput!)
        
    }
    
    
    func finishWithCompletionHandler( handler: ()->() ){
        self.writer?.finishWritingWithCompletionHandler(handler)
    }
    
    func encodeFrame(sampleBuffer:CMSampleBufferRef, isVideo:Bool) -> Bool{
        if CMSampleBufferDataIsReady(sampleBuffer){
            if self.writer?.status == .Unknown{
                let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                self.writer?.startWriting()
                self.writer?.startSessionAtSourceTime(startTime)
            }
            if self.writer?.status == .Failed{
                print("writer error")
                return false
            }
            if isVideo{
                if self.videoInput!.readyForMoreMediaData{
                    self.videoInput?.appendSampleBuffer(sampleBuffer)
                    return true
                }
            }else{
                if self.audioInput!.readyForMoreMediaData{
                    self.audioInput?.appendSampleBuffer(sampleBuffer)
                    return true
                }
            }
        }
        return false
    }
    
}
