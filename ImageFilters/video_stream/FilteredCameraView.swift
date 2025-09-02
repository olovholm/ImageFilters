//
//  FilteredCameraView.swift
//  ImageFilters
//
//  Created by Ola Loevholm on 02/09/2025.
//

import SwiftUI
import AVFoundation
import Metal
import MetalKit

struct FilteredCameraView: NSViewRepresentable {
    
    final class Renderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        
        // Metal
        let device: MTLDevice
        let queue: MTLCommandQueue
        let library: MTLLibrary
        var invertPSO: MTLComputePipelineState?
        var textureCache: CVMetalTextureCache?
    
        // Capture
        let session = AVCaptureSession()
        let videoOutput = AVCaptureVideoDataOutput()
        
        // UI target
        weak var mtkView: MTKView?
        
        // Filter toggle/params
        var enableInvert = true
        
        
        init?(mtkView: MTKView) {
            guard let dev = MTLCreateSystemDefaultDevice(),
                  let q = dev.makeCommandQueue(),
                  let lib = try? dev.makeDefaultLibrary(bundle: .main) else { return nil }
            
            self.device = dev
            self.queue = q
            self.library = lib
            self.mtkView = mtkView
            
            super.init()
            
            mtkView.device = dev
            mtkView.framebufferOnly = false
            mtkView.isPaused = true
            mtkView.enableSetNeedsDisplay = true
            
            CVMetalTextureCacheCreate(nil, nil, dev, nil, &textureCache)
            buildPipeline()
            configureCapture()
            
        }
        
        private func buildPipeline() {
            func makePSO(_ name: String) -> MTLComputePipelineState? {
                guard let f = library.makeFunction(name: name) else { return nil }
                return try? device.makeComputePipelineState(function: f)
            }
            invertPSO = makePSO("fx_invert")
        }
        
        private func configureCapture() {
            session.beginConfiguration()
            session.sessionPreset = .high
            
            guard let cam = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            
            let key = kCVPixelBufferPixelFormatTypeKey as String
            videoOutput.videoSettings = [key: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            let queue = DispatchQueue(label: "CameraSampleQueue")
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            
            guard session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                return
            }
            
            session.addOutput(videoOutput)
            
            
            session.commitConfiguration()
            session.startRunning()
            
        }
        
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard let px = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let cache = textureCache,
                  let view = mtkView else {return }
            
            let width  = CVPixelBufferGetWidth(px)
            let height = CVPixelBufferGetHeight(px)
            view.drawableSize = CGSize(width: width, height: height)
                    
            guard let drawable = view.currentDrawable else { return }



            
            var cvInTex: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, px, nil, .bgra8Unorm, width, height, 0, &cvInTex)
            guard let inTex = cvInTex.flatMap({CVMetalTextureGetTexture($0)}) else { return }
            
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            guard let texA = device.makeTexture(descriptor: desc),
                        let texB = device.makeTexture(descriptor: desc)
                  else { return }
            
            // Copy camera frame → texA
                 guard let cmd = queue.makeCommandBuffer(),
                       let blit0 = cmd.makeBlitCommandEncoder()
                 else { return }
                 let size = MTLSize(width: width, height: height, depth: 1)
                 blit0.copy(from: inTex, sourceSlice: 0, sourceLevel: 0,
                            sourceOrigin: .init(x: 0, y: 0, z: 0),
                            sourceSize: size,
                            to: texA, destinationSlice: 0, destinationLevel: 0,
                            destinationOrigin: .init(x: 0, y: 0, z: 0))
                 blit0.endEncoding()

                 var src = texA
                 var dst = texB
            
            func run(_ pso: MTLComputePipelineState, bind: ((MTLComputeCommandEncoder)->Void)? = nil) {
                guard let enc = cmd.makeComputeCommandEncoder() else { return }
                enc.setComputePipelineState(pso)
                enc.setTexture(src, index: 0)
                enc.setTexture(dst, index: 1)
                bind?(enc)
                
                let tw = pso.threadExecutionWidth
                let th = max(1, pso.maxTotalThreadsPerThreadgroup / tw)
                let wtg = MTLSize(width: tw, height: th, depth: 1)
                let tg = MTLSize(width: (width + tw - 1) / tw, height: (height + th - 1) / th, depth: 1)
                enc.dispatchThreadgroups(tg, threadsPerThreadgroup: wtg)
                enc.endEncoding()
                
                swap(&src, &dst)
                
            }
            
            if enableInvert, let p = invertPSO {
                run(p)
            }
            
            if let blit1 = cmd.makeBlitCommandEncoder() {
                let dstTex = drawable.texture
                let copyW = min(src.width,  dstTex.width)
                let copyH = min(src.height, dstTex.height)

                // (Optional) center the image; top-left align if you prefer (0,0)
                let dstOrigin = MTLOrigin(
                    x: max(0, (dstTex.width  - copyW) / 2),
                    y: max(0, (dstTex.height - copyH) / 2),
                    z: 0
                )

                blit1.copy(from: src, sourceSlice: 0, sourceLevel: 0,
                           sourceOrigin: .init(x: 0, y: 0, z: 0),
                           sourceSize:   .init(width: copyW, height: copyH, depth: 1),
                           to: dstTex, destinationSlice: 0, destinationLevel: 0,
                           destinationOrigin: dstOrigin)
                blit1.endEncoding()
            }

            cmd.present(drawable)
            cmd.commit()
        }
    }
    
    @Binding var invert: Bool
    
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        if let r = Renderer(mtkView: view) {
            context.coordinator.renderer = r
            r.enableInvert = invert
        }
        return view
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
            guard let r = context.coordinator.renderer else { return }
            r.enableInvert = invert
        }

        func makeCoordinator() -> Coordinator { Coordinator() }
        final class Coordinator {
            var renderer: Renderer?
        }
    
    
}

