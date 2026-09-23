//
//  SankeyView.swift
//  AIPapers
//
//  Swift Charts has no Sankey mark, so this lays nodes out by hand and draws
//  the ribbons as Canvas bezier bands. Presentational only — the flow data
//  comes from AnalyticsService.sankey. Any number of columns.
//
//  Labels are laid out separately from the nodes: every node gets one,
//  stacked so they can't overlap, on a solid pill so they stay readable over
//  the ribbons. (Tiny nodes used to get no label at all.)
//

import SwiftUI
import AppKit

struct SankeyView: View {
    let nodes: [AnalyticsService.SankeyNode]
    let links: [AnalyticsService.SankeyLink]

    private let nodeWidth: CGFloat = 10
    private let nodeGap: CGFloat = 4
    private let leftMargin: CGFloat = 215
    private let rightMargin: CGFloat = 90
    private let labelHeight: CGFloat = 15

    /// Grows with the densest column so every label gets its own line.
    private var chartHeight: CGFloat {
        let densest = Dictionary(grouping: nodes, by: \.column).values.map(\.count).max() ?? 0
        return max(460, CGFloat(densest) * (labelHeight + 1) + 20)
    }

    var body: some View {
        Canvas { context, size in
            let layout = makeLayout(size: size)

            for ribbon in layout.ribbons {
                context.fill(ribbon.path, with: .color(color(for: ribbon.area).opacity(0.26)))
            }
            for node in nodes {
                guard let rect = layout.rects[node.id] else { continue }
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color(for: node.area)))
            }
            drawLabels(in: &context, layout: layout, size: size)
        }
        .frame(height: chartHeight)
    }

    private func drawLabels(in context: inout GraphicsContext, layout: Layout, size: CGSize) {
        let backing = Color(nsColor: .windowBackgroundColor).opacity(0.9)

        for (column, group) in Dictionary(grouping: nodes, by: \.column) {
            let ordered = group.compactMap { node in layout.rects[node.id].map { (node, $0) } }
                .sorted { $0.1.midY < $1.1.midY }
            guard !ordered.isEmpty else { continue }

            // Push labels down so none overlap, then back up if that ran off the bottom.
            var ys: [CGFloat] = []
            for (_, rect) in ordered {
                let floor = (ys.last ?? -.infinity) + labelHeight
                ys.append(max(rect.midY, floor, labelHeight / 2))
            }
            let maxY = size.height - labelHeight / 2
            if let last = ys.last, last > maxY {
                ys[ys.count - 1] = maxY
                for i in stride(from: ys.count - 2, through: 0, by: -1) {
                    ys[i] = min(ys[i], ys[i + 1] - labelHeight)
                }
            }

            let leading = column == 0
            for (index, (node, rect)) in ordered.enumerated() {
                let y = ys[index]
                let text = Text("\(node.label)  \(node.value)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)
                let resolved = context.resolve(text)
                let textSize = resolved.measure(in: CGSize(width: 400, height: 40))

                let pillWidth = textSize.width + 10
                let pillX = leading ? rect.minX - 10 - pillWidth : rect.maxX + 8
                let pill = CGRect(x: pillX, y: y - (textSize.height + 4) / 2, width: pillWidth, height: textSize.height + 4)

                // A leader line when the label had to move off its node.
                if abs(y - rect.midY) > 3 {
                    var leader = Path()
                    leader.move(to: CGPoint(x: leading ? rect.minX : rect.maxX, y: rect.midY))
                    leader.addLine(to: CGPoint(x: leading ? pill.maxX : pill.minX, y: y))
                    context.stroke(leader, with: .color(color(for: node.area).opacity(0.7)), lineWidth: 0.75)
                }
                context.fill(Path(roundedRect: pill, cornerRadius: 4), with: .color(backing))
                context.draw(resolved, at: CGPoint(x: pill.minX + 5, y: y), anchor: .leading)
            }
        }
    }

    private struct Ribbon {
        let path: Path
        let area: String
    }

    private struct Layout {
        var rects: [String: CGRect] = [:]
        var ribbons: [Ribbon] = []
    }

    private func makeLayout(size: CGSize) -> Layout {
        var layout = Layout()
        let columns = Dictionary(grouping: nodes, by: \.column)
        guard let total = columns[0]?.reduce(0, { $0 + $1.value }), total > 0 else { return layout }
        let columnCount = (columns.keys.max() ?? 0) + 1

        // One shared scale so a ribbon is the same thickness at both ends:
        // whichever column has the most nodes (and so the most gap) sets it.
        let scale = columns.values.map { column in
            (size.height - nodeGap * CGFloat(column.count - 1)) / CGFloat(total)
        }.min() ?? 1

        let usable = size.width - leftMargin - rightMargin - nodeWidth
        func x(for column: Int) -> CGFloat {
            columnCount > 1 ? leftMargin + usable * CGFloat(column) / CGFloat(columnCount - 1) : leftMargin
        }

        for (index, column) in columns {
            let used = column.reduce(CGFloat(0)) { $0 + CGFloat($1.value) * scale } + nodeGap * CGFloat(column.count - 1)
            var y = (size.height - used) / 2
            for node in column {
                let height = CGFloat(node.value) * scale
                layout.rects[node.id] = CGRect(x: x(for: index), y: y, width: nodeWidth, height: height)
                y += height + nodeGap
            }
        }

        // Stack each node's ribbon ends in the order of the node on the other
        // side, which is what keeps the bands from tangling.
        let byTarget = links.sorted { (layout.rects[$0.target]?.minY ?? 0) < (layout.rects[$1.target]?.minY ?? 0) }
        var outCursor: [String: CGFloat] = [:]
        var srcY: [String: CGFloat] = [:]
        for link in byTarget {
            let start = outCursor[link.source, default: 0]
            srcY[link.id] = start
            outCursor[link.source] = start + CGFloat(link.value) * scale
        }
        let bySource = links.sorted { (layout.rects[$0.source]?.minY ?? 0) < (layout.rects[$1.source]?.minY ?? 0) }
        var inCursor: [String: CGFloat] = [:]
        var dstY: [String: CGFloat] = [:]
        for link in bySource {
            let start = inCursor[link.target, default: 0]
            dstY[link.id] = start
            inCursor[link.target] = start + CGFloat(link.value) * scale
        }

        for link in links {
            guard let from = layout.rects[link.source], let to = layout.rects[link.target] else { continue }
            let thickness = CGFloat(link.value) * scale
            let x0 = from.maxX, x1 = to.minX, mid = (x0 + x1) / 2
            let y0 = from.minY + (srcY[link.id] ?? 0)
            let y1 = to.minY + (dstY[link.id] ?? 0)

            var path = Path()
            path.move(to: CGPoint(x: x0, y: y0))
            path.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: mid, y: y0), control2: CGPoint(x: mid, y: y1))
            path.addLine(to: CGPoint(x: x1, y: y1 + thickness))
            path.addCurve(to: CGPoint(x: x0, y: y0 + thickness), control1: CGPoint(x: mid, y: y1 + thickness), control2: CGPoint(x: mid, y: y0 + thickness))
            path.closeSubpath()
            layout.ribbons.append(Ribbon(path: path, area: link.area))
        }
        return layout
    }

    private func color(for area: String) -> Color {
        switch area {
        case "Language & Agents": .accentColor
        case "Data & Retrieval": .orange
        case "Training & Optimization": .teal
        case "Systems & Ops": .pink
        case "Perception": .green
        case "Evaluation": .purple
        case "Status": .gray
        default: .gray.opacity(0.7)
        }
    }
}
