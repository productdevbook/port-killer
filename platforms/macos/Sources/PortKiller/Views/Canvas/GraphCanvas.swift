import AppKit
import PortKillerKit
import SwiftUI

struct GraphCanvas: View {
    static let nodeSize = CGSize(width: 250, height: 68)
    static let space = "graph"
    private static let margin: CGFloat = 160

    @Environment(AppModel.self) private var model
    let graph: PortGraph
    let layoutKey: String
    @State private var moving: (id: String, translation: CGSize)?
    @State private var link: GraphLink?

    var body: some View {
        let positions = graph.layout(saved: model.graphLayout(layoutKey), columnSpacing: 360, rowSpacing: 88)
        let placed = Dictionary(graph.nodes.map { node in
            let point = positions[node.id] ?? GraphPoint(x: 0, y: 0)
            return (node.id, CGRect(origin: CGPoint(x: point.x, y: point.y), size: Self.nodeSize))
        }) { first, _ in first }
        let union = placed.values.reduce(CGRect.null) { $0.union($1) }
        let bounds = union.isNull ? .zero : union.insetBy(dx: -Self.margin, dy: -Self.margin)
        let frames = Dictionary(uniqueKeysWithValues: placed.map { id, frame in
            let translation = moving?.id == id ? moving?.translation ?? .zero : .zero
            return (id, frame.offsetBy(dx: translation.width - bounds.minX, dy: translation.height - bounds.minY))
        })
        let selected = Set(graph.nodes.filter(model.isSelected).map(\.id))

        GraphViewport(layoutKey: layoutKey, bounds: bounds, extent: union.isNull ? .zero : union, focus: selected.sorted().first.flatMap { placed[$0] }, focusID: selected.sorted().first) {
            ZStack(alignment: .topLeading) {
                GraphEdges(edges: graph.edges, frames: frames, highlighted: selected, link: link)
                    .allowsHitTesting(false)
                ForEach(graph.nodes) { node in
                    let frame = frames[node.id] ?? .zero
                    GraphNodeView(node: node, isSelected: selected.contains(node.id), isLinkTarget: link?.target == node.id)
                        .overlay(alignment: .trailing) {
                            if let port = node.port {
                                LinkHandle()
                                    .offset(x: 11)
                                    .gesture(
                                        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
                                            .onChanged { value in
                                                let target = graph.nodes.first { candidate in
                                                    candidate.acceptsLinks && (frames[candidate.id]?.insetBy(dx: -12, dy: -12).contains(value.location) ?? false)
                                                }
                                                link = GraphLink(port: port, location: value.location, target: target?.id)
                                            }
                                            .onEnded { _ in
                                                if let link, let target = link.target.flatMap(graph.node(id:)),
                                                   let change = graph.change(linking: link.port, to: target) {
                                                    model.apply(change)
                                                }
                                                link = nil
                                            }
                                    )
                            }
                        }
                        .offset(x: frame.minX, y: frame.minY)
                        .onTapGesture { model.select(node) }
                        .gesture(
                            DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
                                .onChanged { moving = (node.id, $0.translation) }
                                .onEnded { value in
                                    let point = positions[node.id] ?? GraphPoint(x: 0, y: 0)
                                    model.saveGraphPosition(GraphPoint(x: point.x + value.translation.width, y: point.y + value.translation.height), for: node.id, in: layoutKey)
                                    moving = nil
                                }
                        )
                        .contextMenu { GraphNodeMenu(node: node, graph: graph) }
                }
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
        }
    }
}

struct GraphLink: Equatable {
    var port: Int
    var location: CGPoint
    var target: String?
}

private struct LinkHandle: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
            .padding(6)
            .contentShape(.circle)
            .help("Drag to Favorites, Watch, Quick Tunnel or a plugin action")
    }
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

private struct GraphEdges: View {
    let edges: [GraphEdge]
    let frames: [String: CGRect]
    let highlighted: Set<String>
    let link: GraphLink?

    var body: some View {
        Canvas { context, _ in
            for edge in edges {
                guard let from = frames[edge.from], let to = frames[edge.to] else { continue }
                let isHighlighted = highlighted.contains(edge.from) || highlighted.contains(edge.to)
                let color = edge.origin == .link ? Color.accentColor : Color(nsColor: .tertiaryLabelColor)
                context.stroke(
                    Self.curve(from: CGPoint(x: from.maxX, y: from.midY), to: CGPoint(x: to.minX, y: to.midY)),
                    with: .color(isHighlighted ? .accentColor : color),
                    style: StrokeStyle(lineWidth: isHighlighted ? 2.5 : 1.5, lineCap: .round)
                )
            }
            if let link, let from = frames[PortGraph.portID(link.port)] {
                context.stroke(
                    Self.curve(from: CGPoint(x: from.maxX, y: from.midY), to: link.location),
                    with: .color(.accentColor),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5])
                )
            }
        }
    }

    private static func curve(from start: CGPoint, to end: CGPoint) -> Path {
        let handle = max(48, abs(end.x - start.x) / 2)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: CGPoint(x: start.x + handle, y: start.y), control2: CGPoint(x: end.x - handle, y: end.y))
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
