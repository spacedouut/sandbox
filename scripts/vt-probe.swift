import VideoToolbox
import CoreMedia
import Foundation

var encoded: [CMSampleBuffer] = []
let encCB: VTCompressionOutputCallback = { _, _, status, _, sb in
    guard status == noErr, let s = sb else { return }
    encoded.append(s)
}
var sess: VTCompressionSession?
guard VTCompressionSessionCreate(allocator: nil, width: 1280, height: 720,
    codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
    imageBufferAttributes: nil, compressedDataAllocator: nil,
    outputCallback: encCB, refcon: nil, compressionSessionOut: &sess) == noErr else { print("enc create fail"); exit(1) }
let session = sess!
VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)

let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720]
var pool: CVPixelBufferPool?; CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
var pts = CMTime.zero; let fd = CMTime(value: 1, timescale: 60)
for i in 0..<120 {
    var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, pool!, &pb)
    if let b = pb { CVPixelBufferLockBaseAddress(b, []); if let p = CVPixelBufferGetBaseAddressOfPlane(b, 0) { memset(p, Int32(i % 255), 1280) }; CVPixelBufferUnlockBaseAddress(b, []) }
    VTCompressionSessionEncodeFrame(session, imageBuffer: pb!, presentationTimeStamp: pts, duration: fd, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
    pts = CMTimeAdd(pts, fd)
}
VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
print("encoded:", encoded.count)

var decoded = 0
var lastW = 0, lastH = 0
let decCB: VTDecompressionOutputCallback = { _, _, status, _, img, _, _ in
    if status == noErr, let px = img { decoded += 1; lastW = CVPixelBufferGetWidth(px); lastH = CVPixelBufferGetHeight(px) }
}
var rec = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: decCB, decompressionOutputRefCon: nil)
guard let fmt = CMSampleBufferGetFormatDescription(encoded[0]) else { print("no fmt"); exit(1) }
var dsess: VTDecompressionSession?
guard VTDecompressionSessionCreate(allocator: nil, formatDescription: fmt, decoderSpecification: nil, imageBufferAttributes: nil, outputCallback: &rec, decompressionSessionOut: &dsess) == noErr else { print("dec create fail"); exit(1) }
var hw: CFTypeRef?
VTSessionCopyProperty(dsess!, key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, allocator: nil, valueOut: &hw)
print("hardware accelerated decoder:", (hw as? NSNumber)?.boolValue ?? (hw as? Bool) ?? false)

let t0 = CFAbsoluteTimeGetCurrent()
for s in encoded { VTDecompressionSessionDecodeFrame(dsess!, sampleBuffer: s, flags: [], frameRefcon: nil, infoFlagsOut: nil) }
VTDecompressionSessionWaitForAsynchronousFrames(dsess!)
let dt = CFAbsoluteTimeGetCurrent() - t0
print("decoded \(decoded)/\(encoded.count) frames in \(String(format: "%.2f", dt))s (\(String(format: "%.0f", Double(encoded.count)/dt)) fps), last frame \(lastW)x\(lastH)")
