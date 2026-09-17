import PortKillerKit
import SwiftUI

struct CanvasView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let overview = model.portGraph
        let centerID = model.selection.flatMap { selection in overview.nodes.first { $0.kind.itemID == selection }?.id }
        let graph = centerID.map { model.focusedGraph(overview, on: $0) } ?? (model.selection == .overview || model.selection == nil ? overview : PortGraph(providers: [], consumers: []))
        let layoutKey = centerID ?? "overview"
        let center = centerID.flatMap(graph.node(id:))
        let portCount = graph.nodes.count { $0.port != nil }
        Group {
            if graph.nodes.contains(where: { !$0.acceptsLinks }) {
                GraphCanvas(graph: graph, layoutKey: layoutKey)
                    .id(layoutKey)
            } else {
                ContentUnavailableView("No Ports", systemImage: "network.slash", description: Text("This item doesn't use a port on this Mac right now."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor), ignoresSafeAreaEdges: .all)
        .navigationTitle(center?.title ?? "Overview")
        .navigationSubtitle(portCount == 1 ? "1 port" : "\(portCount) ports")
        .safeAreaBar(edge: .bottom) {
            if let run = model.plugins.bannerRun.flatMap(model.plugins.activity.run) {
                PluginRunBanner(run: run)
            }
        }
        .toolbar { CanvasToolbar(model: model, layoutKey: layoutKey) }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

private struct CanvasToolbar: ToolbarContent {
    let model: AppModel
    let layoutKey: String

    var body: some ToolbarContent {
        ToolbarItem {
            ControlGroup {
                ForEach(GraphZoomRequest.Kind.allCases, id: \.self) { kind in
                    Button(kind.title, systemImage: kind.symbol) { model.graphZoomRequest = GraphZoomRequest(kind: kind) }
                        .help(kind.title)
                }
            }
            .controlGroupStyle(.navigation)
        }
        ToolbarItem {
            Menu {
                AddNodeItems(port: model.portForNewNode)
            } label: {
                Label("Add Node", systemImage: "plus.rectangle.on.rectangle")
            }
            .menuIndicator(.hidden)
            .help("Add Node")
        }
        ToolbarItem {
            Menu {
                if let selection = model.selection, selection != .overview {
                    ItemActions(id: selection)
                    Divider()
                }
                Button("Reset Layout", systemImage: "rectangle.3.group") { model.resetGraphLayout(layoutKey) }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
        }
    }
}
