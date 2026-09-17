import AppKit
import PortKillerKit
import SwiftUI

enum GraphMetrics {
    static let width: CGFloat = 330
    static let header: CGFloat = 68
    static let detail: CGFloat = 44
    static let status: CGFloat = 36
    static let pin: CGFloat = 38
    static let footer: CGFloat = 8
    static let gap: CGFloat = 24
    static let columnSpacing: CGFloat = 480

    static func height(pins: Int) -> CGFloat {
        pins == 0 ? header + detail + status : header + CGFloat(pins) * pin + footer
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
    @State private var hoveredWire: String?
    @State private var selectedWire: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        let blocks = graph.blocks
        let pins = Dictionary(uniqueKeysWithValues: blocks.compactMap { node -> (String, [GraphNode])? in
            switch node.column {
            case .providers: (node.id, graph.pins(of: node.id))
            case .ports: (node.id, [node])
            case .consumers: nil
            }
        })
        let positions = graph.layout(offsets: model.graphLayout(layoutKey), columnSpacing: GraphMetrics.columnSpacing, gap: GraphMetrics.gap) { node in
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
        let wires = wires(outputs: outputs, frames: frames, selected: selected)
        let chosenWire = wires.first { $0.id == selectedWire && $0.change != nil }

        GraphViewport(
            layoutKey: layoutKey,
            bounds: bounds,
            extent: union.isNull ? .zero : union,
            focus: focusID.flatMap { placed[graph.owner(of: $0) ?? $0] },
            focusID: focusID,
            onBackgroundTap: {
                selectedWire = nil
                model.focusedPort = nil
            }
        ) {
            ZStack(alignment: .topLeading) {
                GraphWires(
                    wires: wires,
                    emphasized: Set([hoveredWire, selectedWire].compactMap(\.self)),
                    link: link.flatMap { link in
                        outputs[PortGraph.portID(link.port)].map { GraphWire(id: "link", from: $0, to: link.location, tint: .accentColor, isHighlighted: true) }
                    }
                )
                .allowsHitTesting(false)
                WireHitLayer(wires: wires.filter { $0.change != nil }, hovered: $hoveredWire) { id in
                    selectedWire = id
                    isFocused = true
                }
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
                                candidate.acceptsLinks && (frames[candidate.id]?.insetBy(dx: -24, dy: -12).contains(location) ?? false)
                            }
                            link = GraphLink(port: port, location: location, target: target?.id)
                        },
                        onLinkEnded: {
                            if let link, let target = link.target.flatMap(graph.node(id:)),
                               let change = graph.change(linking: link.port, to: target) {
                                model.apply(change)
                            }
                            link = nil
                        },
                        onMoveChanged: { moving = (node.id, $0) },
                        onMoveEnded: { translation in
                            model.moveGraphNode(node.id, by: translation, in: layoutKey)
                            moving = nil
                        }
                    )
                    .offset(x: frame.minX, y: frame.minY)
                }
                if let chosenWire, let connection = chosenWire.connection {
                    ConnectionControls(connection: connection) { selectedWire = nil }
                        .position(chosenWire.midpoint)
                } else if let chosenWire, let change = chosenWire.change {
                    Button {
                        model.apply(change)
                        selectedWire = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.red, in: .circle)
                            .overlay { Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2) }
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect \(chosenWire.title)")
                    .position(chosenWire.midpoint)
                }
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .coordinateSpace(.named(Self.space))
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard let change = chosenWire?.change else { return .ignored }
                model.apply(change)
                selectedWire = nil
                return .handled
            }
            .onKeyPress(.escape) {
                guard selectedWire != nil else { return .ignored }
                selectedWire = nil
                return .handled
            }
        }
    }

    private func outputs(blocks: [GraphNode], pins: [String: [GraphNode]], frames: [String: CGRect]) -> [String: CGPoint] {
        var outputs: [String: CGPoint] = [:]
        for block in blocks {
            guard let frame = frames[block.id] else { continue }
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
                id: edge.id,
                from: from,
                to: CGPoint(x: to.minX, y: to.minY + GraphMetrics.header / 2),
                tint: target.kind.tint,
                isHighlighted: selected.contains(edge.from) || selected.contains(edge.to) || owner.map(selected.contains) == true,
                title: "\(graph.node(id: edge.from)?.port.map { "Port \(String($0))" } ?? edge.from) from \(target.title)",
                change: graph.change(unlinking: edge),
                connection: connectionKey(edge: edge, target: target)
            )
        }
    }

    private func connectionKey(edge: GraphEdge, target: GraphNode) -> GraphWire.Connection? {
        guard case .pluginAction(let plugin, let action) = target.kind, let port = graph.node(id: edge.from)?.port else { return nil }
        return GraphWire.Connection(plugin: plugin, action: action, port: port)
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

nonisolated struct GraphWire: Hashable {
    struct Connection: Hashable {
        var plugin: String
        var action: String
        var port: Int
    }

    var id: String
    var from: CGPoint
    var to: CGPoint
    var tint: Color
    var isHighlighted: Bool
    var title = ""
    var change: GraphChange?
    var connection: Connection?

    var midpoint: CGPoint {
        CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
    }

    var path: Path {
        let handle = max(60, abs(to.x - from.x) / 2)
        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: CGPoint(x: from.x + handle, y: from.y), control2: CGPoint(x: to.x - handle, y: to.y))
        return path
    }

    func distance(to point: CGPoint) -> CGFloat {
        let handle = max(60, abs(to.x - from.x) / 2)
        let control1 = CGPoint(x: from.x + handle, y: from.y)
        let control2 = CGPoint(x: to.x - handle, y: to.y)
        return (0...32).map { step in
            let t = CGFloat(step) / 32
            let u = 1 - t
            let x = u * u * u * from.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * to.x
            let y = u * u * u * from.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * to.y
            return hypot(x - point.x, y - point.y)
        }.min() ?? .infinity
    }
}

private struct ConnectionControls: View {
    @Environment(AppModel.self) private var model
    let connection: GraphWire.Connection
    let onDisconnect: () -> Void

    var body: some View {
        let plugins = model.plugins
        let list = plugins.connections.connections(plugin: connection.plugin, action: connection.action, port: connection.port)
        let definitions = list.first.flatMap(plugins.portAction(for:))?.action.inputs ?? []
        HStack(spacing: 2) {
            if list.count == 1, let only = list.first {
                control("Run", symbol: "play.fill") { plugins.run(only) }
                control("Edit", symbol: "slider.horizontal.3") { plugins.edit(only) }
            } else {
                Menu {
                    ForEach(list) { item in
                        Button(item.summary(using: definitions) ?? "Connection") { plugins.run(item) }
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 30, height: 30)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("Run")
                Menu {
                    ForEach(list) { item in
                        Button(item.summary(using: definitions) ?? "Connection") { plugins.edit(item) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 30, height: 30)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("Edit")
            }
            control(list.count > 1 ? "Disconnect All" : "Disconnect", symbol: "xmark", tint: .red) {
                plugins.disconnect(plugin: connection.plugin, action: connection.action, port: connection.port)
                onDisconnect()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize()
    }

    private func control(_ title: String, symbol: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct WireHitLayer: View {
    let wires: [GraphWire]
    @Binding var hovered: String?
    let onSelect: (String) -> Void

    var body: some View {
        Color.clear
            .contentShape(WiresShape(wires: wires))
            .onContinuousHover(coordinateSpace: .named(GraphCanvas.space)) { phase in
                switch phase {
                case .active(let location): hovered = nearest(to: location)
                case .ended: hovered = nil
                }
            }
            .pointerStyle(hovered == nil ? nil : .link)
            .onTapGesture(coordinateSpace: .named(GraphCanvas.space)) { location in
                if let id = nearest(to: location) { onSelect(id) }
            }
    }

    private func nearest(to location: CGPoint) -> String? {
        wires
            .map { (id: $0.id, distance: $0.distance(to: location)) }
            .filter { $0.distance <= 10 }
            .min { $0.distance < $1.distance }?
            .id
    }
}

private nonisolated struct WiresShape: Shape {
    let wires: [GraphWire]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for wire in wires {
            path.addPath(wire.path.strokedPath(StrokeStyle(lineWidth: 20, lineCap: .round)))
        }
        return path
    }
}

private struct GraphViewport<Content: View>: View {
    @Environment(AppModel.self) private var model
    let layoutKey: String
    let bounds: CGRect
    let extent: CGRect
    let focus: CGRect?
    let focusID: String?
    let onBackgroundTap: () -> Void
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
            .onTapGesture { onBackgroundTap() }
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
    let emphasized: Set<String>
    let link: GraphWire?

    var body: some View {
        Canvas { context, _ in
            for wire in wires where !wire.isHighlighted && !emphasized.contains(wire.id) {
                context.stroke(wire.path, with: .color(wire.tint.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            for wire in wires where wire.isHighlighted || emphasized.contains(wire.id) {
                context.stroke(wire.path, with: .color(wire.tint), style: StrokeStyle(lineWidth: emphasized.contains(wire.id) ? 5 : 3, lineCap: .round))
            }
            if let link {
                context.stroke(link.path, with: .color(link.tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 6]))
            }
        }
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
