//
//  MetalEngine.swift
//  ImageFilters
//
//  Created by Ola Loevholm on 25/08/2025.
//

import SwiftUI
import Metal
import MetalKit
import CoreImage

// MARK: - Model

struct MetalFilter: Identifiable {
    let id = UUID()
    let name: String              // e.g. "fx_invert"
    var enabled: Bool = false
    let pipeline: MTLComputePipelineState
    var bindParams: ((MTLComputeCommandEncoder) -> Void)? = nil // ← typed
}

// MARK: - Engine

final class MetalEngine {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let ciContext: CIContext
    let library: MTLLibrary

    init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let q = dev.makeCommandQueue(),
              let lib = try? dev.makeDefaultLibrary(bundle: .main) else {
            return nil
        }
        device = dev
        queue   = q
        library = lib
        ciContext = CIContext(mtlDevice: dev)
    }

    /// Discover all kernels with the `fx_` prefix and build pipelines
    func loadAvailableFilters(prefix: String = "fx_") throws -> [MetalFilter] {
        // .functionNames is available on macOS; if you prefer, hardcode a manifest
        let names = library.functionNames.filter { $0.hasPrefix(prefix) }.sorted()
        return try names.map { name in
            let fn = library.makeFunction(name: name)!
            let ps = try device.makeComputePipelineState(function: fn)
            var filter = MetalFilter(name: name, enabled: false, pipeline: ps)
            if name == "fx_posterize" {
                filter.bindParams = { (enc: MTLComputeCommandEncoder) in
                    var levels: Float = 5.0        // choose your value (>= 2)
                    enc.setBytes(&levels,
                                 length: MemoryLayout<Float>.size,
                                 index: 0)
                }
            }
            return filter
        }
    }

    // MARK: Image <-> Texture

    func makeTexture(from image: NSImage) -> MTLTexture? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                            width: cg.width,
                                                            height: cg.height,
                                                            mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        // Upload pixels
        let ctx = CIContext(options: nil)
        let ci = CIImage(cgImage: cg)
        ctx.render(ci, to: tex, commandBuffer: nil, bounds: ci.extent, colorSpace: cg.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        return tex
    }

    func makeImage(from texture: MTLTexture) -> NSImage? {
        // Fast path via CoreImage
        guard let ci = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) else { return nil }
        let extent = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
        guard let cg = ciContext.createCGImage(ci, from: extent) else { return nil }
        let ns = NSImage(cgImage: cg, size: NSSize(width: texture.width, height: texture.height))
        return ns
    }

    // MARK: Apply a chain of compute kernels: inTex -> outTex (ping-pong)

    func apply(filters: [MetalFilter], to input: NSImage) -> NSImage? {
        guard let inTex = makeTexture(from: input) else { return nil }
        let w = inTex.width, h = inTex.height

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: inTex.pixelFormat,
                                                            width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        guard let texA = device.makeTexture(descriptor: desc),
              let texB = device.makeTexture(descriptor: desc) else { return nil }

        // Initialize A with the input pixels
        blitCopy(source: inTex, dest: texA)

        var src = texA
        var dst = texB

        guard let cmdBuf = queue.makeCommandBuffer() else { return nil }

        for f in filters where f.enabled {
            guard let enc = cmdBuf.makeComputeCommandEncoder() else { break }
            enc.setComputePipelineState(f.pipeline)
            enc.setTexture(src, index: 0)
            enc.setTexture(dst, index: 1)

            // Threading: 16x16 is usually fine for 2D image kernels
            let wgp = MTLSize(width: 16, height: 16, depth: 1)
            let tpg = MTLSize(width: (w + wgp.width - 1) / wgp.width,
                              height: (h + wgp.height - 1) / wgp.height,
                              depth: 1)
            enc.dispatchThreadgroups(tpg, threadsPerThreadgroup: wgp)
            enc.endEncoding()

            swap(&src, &dst) // ping-pong
        }

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        return makeImage(from: src) // last written texture
    }

    private func blitCopy(source: MTLTexture, dest: MTLTexture) {
        guard let cb = queue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return }
        let size = MTLSize(width: source.width, height: source.height, depth: 1)
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: .init(x: 0, y: 0, z: 0),
                  sourceSize: size,
                  to: dest, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: .init(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
    }
}
