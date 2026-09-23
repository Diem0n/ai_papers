//
//  PixelEyeLogo.swift
//  AIPapers
//
//  The Ask logo: a pixel-art camera whose lens is a separate layer, so the
//  "eye" can blink. Generated from the source SVG (32x32 grid) into
//  polygons; a path with a second subpath is an outer shape with a hole.
//  Draws in whatever foreground style it's given.
//

import SwiftUI

private typealias Polygon = [(x: CGFloat, y: CGFloat)]

private let bodyPaths: [[Polygon]] = [
        [[(25.91, 7.62), (27.43, 7.62), (27.43, 15.24), (25.91, 15.24)]],
        [[(24.38, 28.96), (25.91, 28.96), (25.91, 30.48), (24.38, 30.48)]],
        [[(24.38, 15.24), (25.91, 15.24), (25.91, 18.29), (24.38, 18.29)]],
        [[(24.38, 4.57), (25.91, 4.57), (25.91, 7.62), (24.38, 7.62)]],
        [[(22.86, 27.43), (24.38, 27.43), (24.38, 28.96), (22.86, 28.96)]],
        [[(22.86, 18.29), (24.38, 18.29), (24.38, 19.81), (22.86, 19.81)]],
        [[(22.86, 3.05), (24.38, 3.05), (24.38, 4.57), (22.86, 4.57)]],
        [[(7.62, 30.48), (24.38, 30.48), (24.38, 32.00), (7.62, 32.00)]],
        [[(21.33, 7.62), (22.86, 7.62), (22.86, 15.24), (21.33, 15.24)]],
        [[(19.81, 25.91), (22.86, 25.91), (22.86, 27.43), (19.81, 27.43)]],
        [[(19.81, 19.81), (22.86, 19.81), (22.86, 21.34), (19.81, 21.34)]],
        [[(19.81, 15.24), (21.33, 15.24), (21.33, 16.76), (19.81, 16.76)]],
        [[(19.81, 6.10), (21.33, 6.10), (21.33, 7.62), (19.81, 7.62)]],
        [[(19.81, 1.53), (22.86, 1.53), (22.86, 3.05), (19.81, 3.05)]],
        [[(12.19, 21.34), (12.19, 22.86), (13.71, 22.86), (13.71, 24.38), (12.19, 24.38), (12.19, 25.91), (19.81, 25.91), (19.81, 24.38), (18.29, 24.38), (18.29, 22.86), (19.81, 22.86), (19.81, 21.34)], [(16.76, 24.38), (15.24, 24.38), (15.24, 22.86), (16.76, 22.86)]],
        [[(12.19, 16.76), (19.81, 16.76), (19.81, 18.29), (12.19, 18.29)]],
        [[(12.19, 4.57), (19.81, 4.57), (19.81, 6.10), (12.19, 6.10)]],
        [[(12.19, 0.00), (19.81, 0.00), (19.81, 1.53), (12.19, 1.53)]],
        [[(9.14, 25.91), (12.19, 25.91), (12.19, 27.43), (9.14, 27.43)]],
        [[(9.14, 19.81), (12.19, 19.81), (12.19, 21.34), (9.14, 21.34)]],
        [[(10.67, 15.24), (12.19, 15.24), (12.19, 16.76), (10.67, 16.76)]],
        [[(10.67, 6.10), (12.19, 6.10), (12.19, 7.62), (10.67, 7.62)]],
        [[(9.14, 1.53), (12.19, 1.53), (12.19, 3.05), (9.14, 3.05)]],
        [[(9.14, 7.62), (10.67, 7.62), (10.67, 15.24), (9.14, 15.24)]],
        [[(7.62, 27.43), (9.14, 27.43), (9.14, 28.96), (7.62, 28.96)]],
        [[(7.62, 18.29), (9.14, 18.29), (9.14, 19.81), (7.62, 19.81)]],
        [[(7.62, 3.05), (9.14, 3.05), (9.14, 4.57), (7.62, 4.57)]],
        [[(6.10, 28.96), (7.62, 28.96), (7.62, 30.48), (6.10, 30.48)]],
        [[(6.10, 15.24), (7.62, 15.24), (7.62, 18.29), (6.10, 18.29)]],
        [[(6.10, 4.57), (7.62, 4.57), (7.62, 7.62), (6.10, 7.62)]],
        [[(4.57, 7.62), (6.10, 7.62), (6.10, 15.24), (4.57, 15.24)]],
]

private let lensPaths: [[Polygon]] = [
        [[(13.71, 7.62), (13.71, 9.15), (12.19, 9.15), (12.19, 13.72), (13.71, 13.72), (13.71, 15.24), (18.29, 15.24), (18.29, 13.72), (19.81, 13.72), (19.81, 9.15), (18.29, 9.15), (18.29, 10.67), (16.76, 10.67), (16.76, 9.15), (18.29, 9.15), (18.29, 7.62), (13.71, 7.62)]],
]

private func makePath(_ paths: [[Polygon]], in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 32
    func polygon(_ points: Polygon) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
    var result = Path()
    for subpaths in paths {
        var shape = polygon(subpaths[0])
        for hole in subpaths.dropFirst() { shape = shape.subtracting(polygon(hole)) }
        result.addPath(shape)
    }
    return result
}

private struct PixelBody: Shape {
    func path(in rect: CGRect) -> Path { makePath(bodyPaths, in: rect) }
}

private struct PixelLens: Shape {
    func path(in rect: CGRect) -> Path { makePath(lensPaths, in: rect) }
}

/// `blinkTrigger` blinks the eye each time it changes (bump it on hover).
struct PixelEyeLogo: View {
    var size: CGFloat = 32
    var blinkTrigger: Int = 0

    @State private var lidClosed = false

    // The lens is centred at (16, 11.43) on the 32-unit grid.
    private let lensCenter = UnitPoint(x: 0.5, y: 11.43 / 32)

    var body: some View {
        ZStack {
            PixelBody().fill()
            PixelLens()
                .fill()
                .scaleEffect(x: 1, y: lidClosed ? 0.07 : 1, anchor: lensCenter)
        }
        .frame(width: size, height: size)
        .onChange(of: blinkTrigger) { Task { await blink() } }
    }

    /// Two quick blinks.
    @MainActor
    private func blink() async {
        for _ in 0..<2 {
            withAnimation(.easeIn(duration: 0.07)) { lidClosed = true }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.10)) { lidClosed = false }
            try? await Task.sleep(for: .milliseconds(170))
        }
    }
}
