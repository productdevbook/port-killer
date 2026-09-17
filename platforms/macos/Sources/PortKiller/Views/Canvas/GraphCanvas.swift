import AppKit
import PortKillerKit
import SwiftUI

enum GraphMetrics {
    static let width: CGFloat = 270
    static let header: CGFloat = 60
    static let pin: CGFloat = 34
    static let footer: CGFloat = 6
    static let gap: CGFloat = 20
    static let columnSpacing: CGFloat = 400

    static func height(pins: Int) -> CGFloat {
        pins == 0 ? header : header + CGFloat(pins) * pin + footer
    }

    static func pinCenter(_ index: Int) -> CGFloat {
        header + CGFloat(index) * pin + pin / 2
    }
}

struct GraphCanvas: View {
    static let space = "graph"
    private static let margin: CGFloat = 160

    @Environment(AppModel.self) private var model
    let graph: PortGraph
    let layoutKey: String
    @State private var moving: (id: String, translation: CGSize)?
    @State private var link: GraphLink?

    var body: some View {
        let blocks = graph.blocks
        let pins = Dictionary(uniqueKeysWithValues: blocks.filter { $0.column == .providers }.map { ($0.id, graph.pins(of: $0.id)) })
        let positions = graph.layout(saved: model.graphLayout(layoutKey), columnSpacing: GraphMetrics.columnSpacing, gap: GraphMetrics.gap) { node in
            GraphMetrics.height(pins: pins[node.id]?.count ?? 0)
        }
        let placed = Dictionary(blocks.map { node in
            let point = positions[node.id] ?? GraphPoint(x: 0, y: 0)
            return (node.id, CGRect(x: point.x, y: point.y, width: GraphMetrics.width, height: GraphMetrics.height(pins: pins[node.id]?.count ?? 0)))
        }) { first, _ in first }
        let union = placed.values.reduce(CGRect.null) { $0.union($1) }
        let bounds = union.isNull ? .zero : union.insetBy(dx: -Self.margin, dy: -Self.margin)
        let frames = Dictionary(uniqueKeysWithValues: placed.map { id, frame in
            let translation = moving?.id == id ? moving?.translation ?? .zero : .zero
            return (id, frame.offsetBy(dx: translation.width - bounds.minX, dy: translation.height - bounds.minY))
        })
        let selected = Set(graph.nodes.filter(model.isSelected).map(\.id))
        let focusID = selected.sorted().first
        let outputs = outputs(blocks: blocks, pins: pins, frames: frames)

        GraphViewport(layoutKey: layoutKey, bounds: bounds, extent: union.isNull ? .zero : union, focus: focusID.flatMap { placed[graph.owner(of: $0) ?? $0] }, focusID: focusID) {
            ZStack(alignment: .topLeading) {
                GraphWires(wires: wires(outputs: outputs, frames: frames, selected: selected), link: link.flatMap { link in
                    outputs[PortGraph.portID(link.port)].map { GraphWire(from: $0, to: link.location, tint: .accentColor, isHighlighted: true) }
                })
                .allowsHitTesting(false)
                ForEach(blocks) { node in
                    let frame = frames[node.id] ?? .zero
                    GraphBlockView(
                        node: node,
                        pins: pins[node.id] ?? [],
                        graph: graph,
                        selected: selected,
                        linkState: linkState(for: node),
                        onLinkChanged: { port, location in
                            let target = blocks.first { candidate in
                                candidate.acceptsLinks && (frames[candidate.id]?.insetBy(dx: -12, dy: -12).contains(location) ?? false)
                            }
                            link = GraphLink(port: port, location: location, target: target?.id)
                        },
                        onLinkEnded: {
                            if let link, let target = link.target.flatMap(graph.node(id:)),
                               let change = graph.change(linking: link.port, to: target) {
                                model.apply(change)
                            }
                            link = nil
                        }
                    )
                    .offset(x: frame.minX, y: frame.minY)
                    .gesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
                            .onChanged { moving = (node.id, $0.translation) }
                            .onEnded { value in
                                let point = positions[node.id] ?? GraphPoint(x: 0, y: 0)
                                model.saveGraphPosition(GraphPoint(x: point.x + value.translation.width, y: point.y + value.translation.height), for: node.id, in: layoutKey)
                                moving = nil
                            }
                    )
                }
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
        }
    }

    private func outputs(blocks: [GraphNode], pins: [String: [GraphNode]], frames: [String: CGRect]) -> [String: CGPoint] {
        var outputs: [String: CGPoint] = [:]
        for block in blocks {
            guard let frame = frames[block.id] else { continue }
            if block.column == .ports {
                outputs[block.id] = CGPoint(x: frame.maxX, y: frame.minY + GraphMetrics.header / 2)
            }
            for (index, pin) in (pins[block.id] ?? []).enumerated() where outputs[pin.id] == nil {
                outputs[pin.id] = CGPoint(x: frame.maxX, y: frame.minY + GraphMetrics.pinCenter(index))
            }
        }
        return outputs
    }

    private func wires(outputs: [String: CGPoint], frames: [String: CGRect], selected: Set<String>) -> [GraphWire] {
        graph.edges.compactMap { edge in
            guard let from = outputs[edge.from], let to = frames[edge.to], let target = graph.node(id: edge.to) else { return nil }
            let owner = graph.owner(of: edge.from)
            return GraphWire(
                from: from,
                to: CGPoint(x: to.minX, y: to.minY + GraphMetrics.header / 2),
                tint: target.kind.tint,
                isHighlighted: selected.contains(edge.from) || selected.contains(edge.to) || owner.map(selected.contains) == true
            )
        }
    }

    private func linkState(for node: GraphNode) -> GraphBlockView.LinkState {
        guard let link else { return .idle }
        if link.target == node.id { return .target }
        if node.acceptsLinks { return .candidate }
        return node.column == .consumers ? .dimmed : .idle
    }
}

struct GraphLink: Equatable {
    var port: Int
    var location: CGPoint
    var target: String?
}

struct GraphWire: Hashable {
    var from: CGPoint
    var to: CGPoint
    var tint: Color
    var isHighlighted: Bool
}

private struct GraphViewport<Content: View>: View {
    @Environment(AppModel.self) private var model
    let layoutKey: String
    let bounds: CGRect
    let extent: CGRect
    let focus: CGRect?
    let focusID: String?
    @ViewBuilder var content: Content
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var size: CGSize = .zero
    @State private var isPositioned = false
    @State private var fittedPositions: [String: GraphPoint] = [:]

    var body: some View {
        GraphGrid(scale: scale, offset: offset)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let start = panStart ?? offset
                        panStart = start
                        isPositioned = true
                        offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                    }
                    .onEnded { _ in panStart = nil }
            )
            .onTapGesture { model.focusedPort = nil }
            .contextMenu {
                Button(GraphZoomRequest.Kind.fit.title, systemImage: GraphZoomRequest.Kind.fit.symbol) { model.graphZoomRequest = GraphZoomRequest(kind: .fit) }
                Button("Reset Layout", systemImage: "rectangle.3.group") { model.resetGraphLayout(layoutKey) }
            }
            .overlay(alignment: .topLeading) {
                content
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: offset.width + bounds.minX * scale, y: offset.height + bounds.minY * scale)
            }
            .clipped()
            .background {
                CanvasInput { delta in
                    isPositioned = true
                    offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
                } onZoom: { factor, point in
                    isPositioned = true
                    zoom(by: factor, at: point)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { newSize in
                size = newSize
                if !isPositioned { fit() }
            }
            .onChange(of: bounds) {
                guard !isPositioned else { return }
                if model.graphLayout(layoutKey) == fittedPositions {
                    fit()
                } else {
                    isPositioned = true
                }
            }
            .onChange(of: model.graphZoomRequest) { _, request in
                guard let request else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                isPositioned = request.kind != .fit
                withAnimation(.snappy) {
                    switch request.kind {
                    case .zoomIn: zoom(by: 1.25, at: center)
                    case .zoomOut: zoom(by: 0.8, at: center)
                    case .actualSize: zoom(by: 1 / scale, at: center)
                    case .fit: fit()
                    }
                }
            }
            .onChange(of: focusID) {
                guard let focus else { return }
                let visible = CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24)
                let frame = CGRect(x: offset.width + focus.minX * scale, y: offset.height + focus.minY * scale, width: focus.width * scale, height: focus.height * scale)
                guard !visible.contains(frame) else { return }
                withAnimation(.snappy) {
                    offset = CGSize(width: size.width / 2 - focus.midX * scale, height: size.height / 2 - focus.midY * scale)
                }
            }
    }

    private func zoom(by factor: CGFloat, at point: CGPoint) {
        let next = min(max(scale * factor, 0.2), 3)
        let ratio = next / scale
        offset = CGSize(width: point.x - (point.x - offset.width) * ratio, height: point.y - (point.y - offset.height) * ratio)
        scale = next
    }

    private func fit() {
        let padding: CGFloat = 48
        let area = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)
        guard extent.width > 0, extent.height > 0, area.width > 0, area.height > 0 else { return }
        fittedPositions = model.graphLayout(layoutKey)
        scale = min(max(min(area.width / extent.width, area.height / extent.height), 0.6), 1)
        let top = extent.height * scale <= area.height ? (size.height - extent.height * scale) / 2 : padding
        offset = CGSize(
            width: (size.width - extent.width * scale) / 2 - extent.minX * scale,
            height: top - extent.minY * scale
        )
    }
}

private struct GraphWires: View {
    let wires: [GraphWire]
    let link: GraphWire?

    var body: some View {
        Canvas { context, _ in
            for wire in wires where !wire.isHighlighted {
                context.stroke(Self.curve(wire), with: .color(wire.tint.opacity(0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            for wire in wires where wire.isHighlighted {
                context.stroke(Self.curve(wire), with: .color(wire.tint), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let link {
                context.stroke(Self.curve(link), with: .color(link.tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))
            }
        }
    }

    private static func curve(_ wire: GraphWire) -> Path {
        let handle = max(60, abs(wire.to.x - wire.from.x) / 2)
        var path = Path()
        path.move(to: wire.from)
        path.addCurve(to: wire.to, control1: CGPoint(x: wire.from.x + handle, y: wire.from.y), control2: CGPoint(x: wire.to.x - handle, y: wire.to.y))
        return path
    }
}

private struct GraphGrid: View {
    let scale: CGFloat
    let offset: CGSize

    var body: some View {
        Canvas { context, size in
            let spacing = 24 * scale
            guard spacing >= 8 else { return }
            let dot = max(1, 1.5 * scale)
            let startX = offset.width.truncatingRemainder(dividingBy: spacing) - spacing
            let startY = offset.height.truncatingRemainder(dividingBy: spacing) - spacing
            var dots = Path()
            for x in stride(from: startX, through: size.width, by: spacing) {
                for y in stride(from: startY, through: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                }
            }
            context.fill(dots, with: .color(Color(nsColor: .quaternaryLabelColor)))
        }
    }
}

private struct CanvasInput: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> InputView {
        InputView()
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.onPan = onPan
        view.onZoom = onZoom
    }

    static func dismantleNSView(_ view: InputView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class InputView: NSView {
        var onPan: (CGSize) -> Void = { _ in }
        var onZoom: (CGFloat, CGPoint) -> Void = { _, _ in }
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard unsafe window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self else { return event }
                return handle(event) ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard unsafe event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
            let point = convert(event.locationInWindow, from: nil)
            guard bounds.contains(point) else { return false }
            switch event.type {
            case .magnify:
                onZoom(1 + event.magnification, point)
            case .scrollWheel where !event.hasPreciseScrollingDeltas:
                onZoom(pow(1.1, event.scrollingDeltaY), point)
            case .scrollWheel where event.modifierFlags.contains(.command):
                onZoom(pow(1.01, event.scrollingDeltaY), point)
            case .scrollWheel:
                onPan(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
            default:
                return false
            }
            return true
        }
    }
}
