//
//  WorkerRigMotionProbe.swift
//  NFCTimeSheetsUITests
//
//  HOW A WALK SEES THE RING-THEN-CHECK (TASK-365.8 / iOS P7, decision-83). The mark is
//  `accessibilityHidden` on purpose (a screen reader is never told a ring is loading), so there is
//  no element to wait for and no label to read: the only honest observer is the PICTURE. This file
//  takes pictures - `XCUIScreen.main.screenshot()` in a loop, a few per second - and reduces each
//  to two numbers:
//
//    head    "ink" in the TOP LINE of the block the motion wraps (the receipt's 'Shift finished', the
//            clock card's 'TIME WORKED'). While the motion runs the wrapped content is held back
//            (ConfirmationMotion.Stage.contentOpacity is 0 for the first 80 % of the 0.9 s), so this
//            line is EMPTY for ~720 ms and comes back as the pair leaves.
//    center  "ink" in a box in the middle of the block - where the 88 pt ring and the check are
//            drawn. With the content held back, whatever is there IS the mark.
//
//  A frame with head == 0 and center > 0 is a frame of the motion. A motion is a run of such frames
//  (`episodes`). The walk asserts how many there were - exactly one after a clean ACK, none on every
//  other path - and the driver compares the first frame's wall-clock time with the moment the front
//  released the server's answer.
//
//  INK is "a pixel that differs from the strip's own background (its left-most pixel) by more than
//  96 of 765 channel steps": the field on the running screen, the list background on the idle one,
//  whichever appearance. Nothing here knows a colour.
//
//  WHAT THIS CANNOT SEE: a frame it did not take. A screenshot costs 100-250 ms on this Simulator,
//  so a run of ~720 ms is 3-6 frames; the 900 ms motion cannot hide between two of them, but its
//  exact curve (the ring's 432 ms, the check's 387-567 ms) is ConfirmationMotion's stage maths and
//  worker-motion-check's, not this. What it proves is that the product DREW the held-back content
//  and the mark over it, once, at the moment of the ACK - or never.
//
//  Not part of checks/run.sh (that script is Xcode-free), same as the other WorkerRig* tests.
//

import UIKit
import XCTest

struct MotionSample {
    /// Wall-clock seconds since 1970 at the middle of the capture (host and Simulator share a clock).
    let epoch: Double
    let head: Int
    let center: Int
    var hidden: Bool { head == 0 }
    var ring: Bool { head == 0 && center > 0 }
}

struct MotionEpisode {
    let first: Double
    let last: Double
    let frames: Int
}

enum MotionProbe {
    // MARK: pixels

    private static func crop(_ image: CGImage, scale: CGFloat, rect: CGRect) -> CGImage? {
        let px = CGRect(x: (rect.minX * scale).rounded(.down), y: (rect.minY * scale).rounded(.down),
                        width: (rect.width * scale).rounded(.up), height: (rect.height * scale).rounded(.up))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard px.width >= 1, px.height >= 1 else { return nil }
        return image.cropping(to: px)
    }

    private static func bytes(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int)? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (data, w, h) : nil
    }

    /// Pixels in `rect` (points) that differ from the rect's left-top pixel by more than the threshold.
    static func ink(_ image: CGImage, scale: CGFloat, rect: CGRect) -> Int {
        guard let cropped = crop(image, scale: scale, rect: rect), let (data, w, h) = bytes(cropped) else { return -1 }
        let r0 = Int(data[0]), g0 = Int(data[1]), b0 = Int(data[2])
        var n = 0
        var i = 0
        while i < w * h * 4 {
            let d = abs(Int(data[i]) - r0) + abs(Int(data[i + 1]) - g0) + abs(Int(data[i + 2]) - b0)
            if d > 96 { n += 1 }
            i += 4
        }
        return n
    }

    /// The first band of rows (top to bottom) in `rect` that holds ink, as a rect in points - the top
    /// line of a block. Gaps of up to 3 px inside a glyph row are bridged.
    static func firstBand(_ image: CGImage, scale: CGFloat, rect: CGRect) -> CGRect? {
        guard let cropped = crop(image, scale: scale, rect: rect), let (data, w, h) = bytes(cropped) else { return nil }
        let r0 = Int(data[0]), g0 = Int(data[1]), b0 = Int(data[2])
        var rowHasInk = [Bool](repeating: false, count: h)
        for y in 0..<h {
            var x = 0
            while x < w {
                let i = (y * w + x) * 4
                let d = abs(Int(data[i]) - r0) + abs(Int(data[i + 1]) - g0) + abs(Int(data[i + 2]) - b0)
                if d > 96 { rowHasInk[y] = true; break }
                x += 1
            }
        }
        guard let start = rowHasInk.firstIndex(of: true) else { return nil }
        var end = start
        var gap = 0
        var y = start
        while y < h {
            if rowHasInk[y] { end = y; gap = 0 } else { gap += 1; if gap > 3 { break } }
            y += 1
        }
        let top = rect.minY + CGFloat(start) / scale
        let bottom = rect.minY + CGFloat(end + 1) / scale
        return CGRect(x: rect.minX, y: top, width: rect.width, height: max(bottom - top, 1))
    }

    // MARK: the screen

    static func screenWidth(_ app: XCUIApplication) -> CGFloat { app.windows.firstMatch.frame.width }

    static func scale(of shot: XCUIScreenshot, screenWidth: CGFloat) -> CGFloat {
        guard let cg = shot.image.cgImage, screenWidth > 0 else { return 3 }
        return CGFloat(cg.width) / screenWidth
    }

    /// Where to measure: the top line of the block, found in a picture TAKEN NOW (before the motion),
    /// and a box at the middle of the block's frame.
    struct Geometry {
        let head: CGRect
        let center: CGRect
        let scale: CGFloat
    }

    /// `block` is the frame of the element the motion wraps, `searchHeight` how far below its top the
    /// first line may be. `centerY` overrides the box's vertical middle (the receipt's block is not
    /// one element).
    static func calibrate(app: XCUIApplication, block: CGRect, centerY: CGFloat? = nil,
                          searchHeight: CGFloat = 60) -> Geometry? {
        let width = screenWidth(app)
        let shot = XCUIScreen.main.screenshot()
        guard let cg = shot.image.cgImage else { return nil }
        let s = scale(of: shot, screenWidth: width)
        let search = CGRect(x: 4, y: block.minY, width: width - 8, height: min(searchHeight, block.height))
        guard let band = firstBand(cg, scale: s, rect: search) else { return nil }
        let cy = centerY ?? block.midY
        let box = CGRect(x: width / 2 - 50, y: cy - 50, width: 100, height: 100)
        return Geometry(head: band, center: box, scale: s)
    }

    /// Takes pictures for `seconds`, as fast as the Simulator hands them over. Frames in which the
    /// head line is empty are kept (up to `keep`) so the walk can write the evidence.
    static func record(seconds: TimeInterval, geometry g: Geometry, keep: Int = 14)
        -> (samples: [MotionSample], kept: [(MotionSample, XCUIScreenshot)])
    {
        var samples: [MotionSample] = []
        var kept: [(MotionSample, XCUIScreenshot)] = []
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            let before = Date().timeIntervalSince1970
            let shot = XCUIScreen.main.screenshot()
            let after = Date().timeIntervalSince1970
            guard let cg = shot.image.cgImage else { continue }
            let sample = MotionSample(epoch: (before + after) / 2,
                                      head: ink(cg, scale: g.scale, rect: g.head),
                                      center: ink(cg, scale: g.scale, rect: g.center))
            samples.append(sample)
            if sample.hidden, kept.count < keep { kept.append((sample, shot)) }
        }
        return (samples, kept)
    }

    /// Maximal runs of consecutive hidden frames that contain at least one ring frame.
    static func episodes(_ samples: [MotionSample]) -> [MotionEpisode] {
        var result: [MotionEpisode] = []
        var run: [MotionSample] = []
        func close() {
            if run.contains(where: { $0.ring }), let f = run.first, let l = run.last {
                result.append(MotionEpisode(first: f.epoch, last: l.epoch, frames: run.count))
            }
            run = []
        }
        for s in samples {
            if s.hidden { run.append(s) } else { close() }
        }
        close()
        return result
    }

    /// Pixels in `frame` (points) that are clearly red (r > 180, g and b < 110) in a picture taken now:
    /// what the accessibility tree cannot say about a pill - its colour.
    static func reddishPixels(app: XCUIApplication, frame: CGRect) -> Int {
        let shot = XCUIScreen.main.screenshot()
        guard let cg = shot.image.cgImage else { return -1 }
        let s = scale(of: shot, screenWidth: screenWidth(app))
        guard let cropped = crop(cg, scale: s, rect: frame), let (data, w, h) = bytes(cropped) else { return -1 }
        var n = 0
        var i = 0
        while i < w * h * 4 {
            if data[i] > 180, data[i + 1] < 110, data[i + 2] < 110 { n += 1 }
            i += 4
        }
        return n
    }

    // MARK: evidence

    static func describe(_ samples: [MotionSample]) -> String {
        guard let t0 = samples.first?.epoch else { return "(no frames)" }
        return samples.map { String(format: "%6.0f ms  head %5d  center %5d  %@", ($0.epoch - t0) * 1000, $0.head, $0.center,
                                    $0.ring ? "RING" : ($0.hidden ? "hidden" : "")) }.joined(separator: "\n")
    }

    static func write(_ text: String, name: String) {
        guard let dir = Rig.value("TS_RIG_SHOTS") else { return }
        try? text.write(toFile: "\(dir)/\(name).txt", atomically: true, encoding: .utf8)
    }

    static func writePNG(_ shot: XCUIScreenshot, name: String) {
        guard let dir = Rig.value("TS_RIG_SHOTS") else { return }
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// `<name> <epoch milliseconds>` into marks.txt - a frame's own time, not "now".
    static func mark(_ name: String, atEpoch epoch: Double) {
        guard let dir = Rig.value("TS_RIG_SYNC") else { return }
        let line = "\(name) \(Int(epoch * 1000))\n"
        let url = URL(fileURLWithPath: dir).appendingPathComponent("marks.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
