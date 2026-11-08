import Foundation

/// Structural access is separate from access to unfinished room content.
/// IDs and same-floor edges come from the existing building assets.
struct ConnectedBuilding {
    struct Node: Identifiable {
        let id: String
        let name: String
        let kind: String
        let floor: String?
        let parent: String?
        let destination: String?
        let contentLocked: Bool
    }
    struct Edge: Equatable {
        let source: String
        let target: String
        let kind: String
    }
    let nodes: [String: Node]
    let edges: [Edge]
    let rooms: [Node]

    init(building: Data, firstFloor: Data) throws {
        let b = try JSONSerialization.jsonObject(with: building) as? [String: Any] ?? [:]
        let l = try JSONSerialization.jsonObject(with: firstFloor) as? [String: Any] ?? [:]
        var index: [String: Node] = [:]
        var links: [Edge] = []
        func add(_ id: String, _ name: String, _ kind: String, _ floor: String?, _ parent: String?, _ destination: String? = nil, _ locked: Bool = false) {
            index[id] = Node(id: id, name: name, kind: kind, floor: floor, parent: parent, destination: destination, contentLocked: locked)
        }
        add("world.campus", "园区", "world", nil, nil)
        add("building.citadel", "实验楼", "building", nil, "space.L1.plaza")
        let floors = ["B2", "B1", "L1", "L2", "L3", "L4"]
        for floor in floors { add("floor." + floor, floor, "floor", floor, "building.citadel") }
        let sourceRooms = b["rooms"] as? [[String: Any]] ?? []
        let roomByID = Dictionary(uniqueKeysWithValues: sourceRooms.compactMap { r -> (String, [String: Any])? in
            guard let id = r["id"] as? String else { return nil }; return (id, r)
        })
        // L1 geometry and door routes are authoritative over the older whole-building L1 projection.
        for r in (l["rooms"] as? [[String: Any]] ?? []) where r["id"] as? String != "lift.E01" {
            guard let id = r["id"] as? String else { continue }
            let saved = roomByID[id]
            let kind = (saved != nil) ? "room" : (r["type"] as? String ?? "space")
            add(id, r["name"] as? String ?? id, kind, "L1", "floor.L1", saved?["destination"] as? String, r["locked"] as? Bool ?? false)
        }
        for r in (l["corridors"] as? [[String: Any]] ?? []) {
            guard let id = r["id"] as? String else { continue }; add(id, r["name"] as? String ?? id, "corridor", "L1", "floor.L1")
        }
        for r in (l["waypoints"] as? [[String: Any]] ?? []) {
            guard let id = r["id"] as? String else { continue }; add(id, "通道转折点", "waypoint", "L1", "floor.L1")
        }
        for r in (l["doors"] as? [[String: Any]] ?? []) where r["target"] as? String != "lift.E01" {
            guard let id = r["id"] as? String, let target = r["target"] as? String else { continue }
            add(id, "门 · " + (index[target]?.name ?? target), "door", "L1", target)
        }
        for n in (b["nodes"] as? [[String: Any]] ?? []) where n["floor"] as? String != "L1" && floors.contains(n["floor"] as? String ?? "") {
            guard let id = n["id"] as? String, let floor = n["floor"] as? String, id != "floor." + floor else { continue }
            let r = roomByID[id]
            let type = n["type"] as? String ?? "space"
            let parent = id == "space.L2.L201.assets" ? "space.L2.L201" : "floor." + floor
            let name = r?["name"] as? String ?? (id == "entry.ST01." + floor ? "ST01 · " + floor + "楼梯平台" : type == "corridor" ? floor + "主走廊" : type == "landing" ? floor + "接待区" : type == "door" ? "房间门" : floor + "通道")
            add(id, name, type, floor, parent, r?["destination"] as? String, r?["locked"] as? Bool ?? false)
        }
        for r in sourceRooms where r["floor"] as? String != "L1" {
            if let door = r["doorId"] as? String, let id = r["id"] as? String, let old = index[door] {
                add(door, "门 · " + (index[id]?.name ?? id), old.kind, old.floor, id)
            }
        }
        for e in (l["edges"] as? [[String: Any]] ?? []) {
            guard let a = e["source"] as? String, let z = e["target"] as? String, index[a] != nil, index[z] != nil else { continue }
            guard e["bidirectional"] as? Bool == true else { throw GraphError.invalidEdge }
            links.append(Edge(source: a, target: z, kind: "passage"))
        }
        for e in (b["edges"] as? [[String: Any]] ?? []) {
            guard let a = e["source"] as? String, let z = e["target"] as? String,
                  let from = index[a], let to = index[z], from.floor != "L1", from.floor == to.floor,
                  from.kind != "floor", to.kind != "floor" else { continue }
            guard e["bidirectional"] as? Bool == true else { throw GraphError.invalidEdge }
            links.append(Edge(source: a, target: z, kind: "passage"))
        }
        // Adjacent landings only: stairs cannot skip a floor or reuse the elevator shaft.
        let landings = floors.map { $0 == "L1" ? "stair.ST01" : "entry.ST01." + $0 }
        guard landings.allSatisfy({ index[$0] != nil }) else { throw GraphError.missingStair }
        for pair in zip(landings, landings.dropFirst()) {
            links.append(Edge(source: pair.0, target: pair.1, kind: "stair"))
        }
        // Reuse the existing exterior plaza identity as the global parent; no old path removed.
        add("space.L1.plaza", "广场", "external", nil, "world.campus")
        add("building.productlab", "产品设计／制造实验室", "building", nil, "space.L1.plaza")
        add("productlab.entrance", "产品工坊入口 · 象征性门禁", "entrance", nil, "building.productlab")
        add("productlab.hall", "产品实验室 · 主厂房概念场景", "factory", nil, "building.productlab")
        add("factory.shibu", "拾步者概念展项", "concept_zone", nil, "building.productlab")
        add("productlab.traditional", "传统清扫车概念展项", "concept_zone", nil, "building.productlab")
        add("productlab.design", "设计室 · 开发中", "planning", nil, "building.productlab", nil, true)
        add("productlab.office", "办公室 · 开发中", "planning", nil, "building.productlab", nil, true)
        add("city.background", "未来城市远景 · 暂不可远行", "planning", nil, "world.campus", nil, true)
        links.append(Edge(source: "space.L1.plaza", target: "productlab.entrance", kind: "campus"))
        links.append(Edge(source: "productlab.entrance", target: "productlab.hall", kind: "gate"))
        links.append(Edge(source: "productlab.hall", target: "factory.shibu", kind: "exhibit"))
        links.append(Edge(source: "productlab.hall", target: "productlab.traditional", kind: "exhibit"))
        for (id, name) in [("pickup", "拾取探索"), ("storage", "容积与收纳"), ("packaging", "打包探索"), ("validation", "训练与验证")] {
            let key = "factory.shibu." + id
            add(key, name + " · 概念未验证", "concept_zone", nil, "factory.shibu")
            links.append(Edge(source: "factory.shibu", target: key, kind: "concept_passage"))
        }
        for scene in ProductConceptScene.interior {
            add(scene.id, scene.title + " · 概念导览", "concept_view", nil, "productlab.hall")
            links.append(Edge(source: "productlab.hall", target: scene.id, kind: "concept_tour"))
        }
        for pair in zip(ProductConceptScene.interior, ProductConceptScene.interior.dropFirst()) {
            links.append(Edge(source: pair.0.id, target: pair.1.id, kind: "concept_tour"))
        }
        nodes = index
        edges = links
        rooms = index.values.filter { $0.kind == "room" }.sorted { $0.id < $1.id }
        guard issues().isEmpty else { throw GraphError.disconnected }
    }
    enum GraphError: Error { case invalidEdge, missingStair, disconnected }
    func neighbors(of id: String) -> [Node] {
        edges.compactMap { edge in nodes[edge.source == id ? edge.target : edge.target == id ? edge.source : ""] }.sorted { $0.id < $1.id }
    }
    func path(from start: String, to target: String) -> [String]? {
        guard nodes[start] != nil, nodes[target] != nil else { return nil }
        var queue = [[start]], visited: Set<String> = [start]
        while !queue.isEmpty {
            let path = queue.removeFirst(), last = path.last!
            if last == target { return path }
            for node in neighbors(of: last) where visited.insert(node.id).inserted { queue.append(path + [node.id]) }
        }
        return nil
    }
    func issues() -> [String] {
        var result: [String] = []
        for node in nodes.values {
            if let parent = node.parent, nodes[parent] == nil { result.append("悬空归属：" + node.id) }
            var parents: Set<String> = [node.id], next = node.parent
            while let id = next {
                if !parents.insert(id).inserted { result.append("归属循环：" + node.id); break }
                next = nodes[id]?.parent
            }
        }
        for node in nodes.values where !["world", "building", "floor", "planning"].contains(node.kind) && path(from: "space.L1.lobby", to: node.id) == nil { result.append("通行节点不可达：" + node.id) }
        for edge in edges where nodes[edge.source] == nil || nodes[edge.target] == nil { result.append("悬空通道") }
        return result
    }
}

struct BuildingWalk {
    let graph: ConnectedBuilding
    private(set) var position: String
    private(set) var history: [String] = []
    init(graph: ConnectedBuilding, start: String = "space.L1.lobby") {
        self.graph = graph
        self.position = graph.nodes[start] == nil ? "space.L1.lobby" : start
    }
    @discardableResult mutating func step(to next: String) -> Bool {
        guard graph.neighbors(of: position).contains(where: { $0.id == next }) else { return false }
        history.append(position); position = next; return true
    }
    @discardableResult mutating func swipe(_ intent: BuildingSwipeIntent, toward target: String) -> Bool {
        if intent == .back { return back() }
        guard let route = graph.path(from: position, to: target), route.count > 1 else { return false }
        return step(to: route[1])
    }
    @discardableResult mutating func back() -> Bool {
        guard let previous = history.last, graph.neighbors(of: position).contains(where: { $0.id == previous }) else { return false }
        position = previous; history.removeLast(); return true
    }
}

enum BuildingSwipeIntent {
    case forward, back
    static func resolve(horizontal: Double, vertical: Double) -> Self? {
        guard abs(horizontal) >= 70, abs(horizontal) > abs(vertical) * 1.6 else { return nil }
        return horizontal < 0 ? .forward : .back
    }
}

#if os(iOS)
import SwiftUI

struct ConnectedBuildingScene: View {
    @ObservedObject var model: PadModel
    let graph: ConnectedBuilding
    @State private var walk: BuildingWalk
    @State private var showLessons = false
    @State private var swipeFeedback = "先选择目的地，再在导览图上左滑前进、右滑退回。"
    @State private var target: String = "space.L2.L201"
    @State private var destinationFloor: String = "L2"
    @Environment(\.dismiss) private var dismiss
    init(model: PadModel, graph: ConnectedBuilding) {
        self.model = model; self.graph = graph
        let start = model.connectedStart ?? (graph.nodes[model.buildingPosition] != nil ? model.buildingPosition : "circulation." + model.currentFloor + ".main")
        _walk = State(initialValue: BuildingWalk(graph: graph, start: start))
        let initialTarget = model.connectedTarget ?? "space.L2.L201"
        _target = State(initialValue: initialTarget)
        _destinationFloor = State(initialValue: graph.nodes[initialTarget]?.floor ?? "L2")
    }
    private var current: ConnectedBuilding.Node { graph.nodes[walk.position]! }
    private var route: [String] { graph.path(from: walk.position, to: target) ?? [] }
    var body: some View {
        NavigationStack {
            (UIDevice.current.userInterfaceIdiom == .phone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        swipeDeck
                        Text((current.floor ?? "") + " · " + current.name).font(.largeTitle.bold()).accessibilityIdentifier("connected.position")
                        Text(current.id).font(.caption).foregroundStyle(.secondary)
                        Label(current.kind == "room" ? "房间空间骨架" : (current.floor == nil ? "园区与工坊通路" : "通道与楼梯"), systemImage: current.kind == "room" ? "door.left.hand.open" : "figure.walk")
                        if current.kind == "room" {
                            Text(current.contentLocked || current.destination == nil ? "开发中 · 空间已接通，室内内容尚未开放。" : "已有内容可进入；实验记录继续由原实验室保存。")
                                .accessibilityIdentifier("connected.contentStatus")
                            if !current.contentLocked, let destination = current.destination {
                                Button("进入已有实验场景") { openContent(destination) }.buttonStyle(.borderedProminent).accessibilityIdentifier("connected.openContent")
                            }
                        } else if let floor = current.floor, !["L1", "L2"].contains(floor) {
                            Text("本层场景引导开发中；当前可沿空间骨架逐段通行。").foregroundStyle(.secondary)
                        }
                        if current.id == "space.L2.L202" || current.id == "space.L2.L201" {
                            Button("打开概念阅读角 · LLC / 拾步") { showLessons = true }.buttonStyle(.bordered).accessibilityIdentifier("lesson.fromRoom")
                        }
                        Text("相邻空间").font(.headline)
                        ForEach(graph.neighbors(of: walk.position)) { node in
                            Button { _ = walk.step(to: node.id) } label: {
                                Label((node.floor ?? "") + " · " + node.name, systemImage: node.floor != current.floor ? "stairs" : "arrow.forward")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            }.buttonStyle(.bordered).accessibilityIdentifier("connected.step." + node.id)
                        }
                        Button("沿原路退回一步") { _ = walk.back() }.disabled(walk.history.isEmpty).accessibilityIdentifier("connected.back")
                        Text("归属：" + hierarchy(current)).font(.footnote).foregroundStyle(.secondary)
                    }.padding(24)
                }.frame(maxWidth: .infinity)
                List {
                    Section("路线引导") {
                        Picker("目标楼层", selection: $destinationFloor) {
                            ForEach(["B2", "B1", "L1", "L2", "L3", "L4"], id: \.self) { floor in Text(floor).tag(floor) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("connected.destinationFloor")
                            .onChange(of: destinationFloor) { _, floor in if let room = graph.rooms.first(where: { $0.floor == floor }) { target = room.id } }
                        Picker("本层目的地", selection: $target) {
                            ForEach(graph.rooms.filter { $0.floor == destinationFloor }) { node in Text(node.name).tag(node.id) }
                            if graph.nodes[target]?.floor == nil { Text(graph.nodes[target]?.name ?? "外部目的地").tag(target) }
                        }.accessibilityIdentifier("connected.destination")
                        HStack {
                            Button("前往广场") { target = "space.L1.plaza" }.accessibilityIdentifier("connected.routeCampus")
                            Button("前往工坊") { target = "productlab.hall" }.accessibilityIdentifier("connected.routeFactory")
                        }.buttonStyle(.bordered)
                        if route.count > 1 {
                            Button("下一步 · " + (graph.nodes[route[1]]?.name ?? route[1])) { _ = walk.step(to: route[1]) }
                                .accessibilityIdentifier("connected.next").buttonStyle(.borderedProminent)
                        } else { Text("已到达目的地").accessibilityIdentifier("connected.arrived") }
                        ForEach(Array(route.enumerated()), id: \.offset) { _, id in Text((graph.nodes[id]?.floor ?? "") + " · " + (graph.nodes[id]?.name ?? id)).font(.footnote) }
                    }
                    ForEach(["B2", "B1", "L1", "L2", "L3", "L4"], id: \.self) { floor in
                        Section(floor + " · 房间") {
                            ForEach(graph.rooms.filter { $0.floor == floor }) { room in
                                Button { target = room.id } label: {
                                    VStack(alignment: .leading) {
                                        Text(room.name)
                                        Text(room.contentLocked || room.destination == nil ? "空间骨架 · 内容开发中" : "已有内容").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.accessibilityIdentifier("connected.target." + room.id)
                            }
                        }
                    }
                }.frame(width: UIDevice.current.userInterfaceIdiom == .phone ? nil : 370, height: UIDevice.current.userInterfaceIdiom == .phone ? 310 : nil)
            }
            .background(Color(uiColor: .systemBackground))
            .fullScreenCover(isPresented: $showLessons) { LearningShelf(onCampus: { model.goCampus() }) }
            .navigationTitle("滑动步行 · 楼宇通路")
            .toolbar { ToolbarItemGroup(placement: .confirmationAction) { Button("广场") { model.goCampus(); dismiss() }; Button("返回原实验场景") { dismiss() }.accessibilityIdentifier("connected.close") } }
        }
    }
    private var swipeDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("左滑前进一步 · 右滑沿原路退回").font(.headline)
            let name = current.floor.map { "floor-plan-" + $0 + "-v1" } ?? (current.id == "space.L1.plaza" ? "campus-plaza-concept" : "product-hall-concept")
            ZStack {
                if let path = Bundle.main.path(forResource: name, ofType: "png"), let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image).resizable().scaledToFill().frame(height: 190).clipped().opacity(current.floor == nil ? 0.65 : 0.16)
                }
                VStack(spacing: 12) {
                    Label(current.name, systemImage: "figure.walk").font(.title2.bold())
                    Text(current.floor.map { $0 + " · 楼层导览" } ?? "园区导览").font(.headline)
                    Text(route.count > 1 ? "下一步：" + (graph.nodes[route[1]]?.name ?? "") : "已到达选择的目的地")
                }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }.frame(maxWidth: .infinity).frame(height: 190).contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
                    guard let intent = BuildingSwipeIntent.resolve(horizontal: value.translation.width, vertical: value.translation.height) else { return }
                    let moved = walk.swipe(intent, toward: target)
                    swipeFeedback = moved ? "已沿相邻通道到达：" + current.name : (intent == .back ? "已退到本次步行起点。" : "已到达目的地；可选择另一房间。")
                }).accessibilityIdentifier("connected.swipeSurface")
            Text(swipeFeedback).font(.footnote).accessibilityIdentifier("connected.swipeFeedback")
            Text("每次手势只走一个相邻节点；导览图不是连续三维场景。历史楼层底图仅示方位，以实时门牌与通路为准；未开放室内标开发中。").font(.caption).foregroundStyle(.secondary)
            if current.id == "space.L1.plaza" { Button("进入广场场景") { model.goCampus(); dismiss() }.buttonStyle(.bordered).accessibilityIdentifier("connected.enterCampus") }
            if current.id == "productlab.hall" { Button("打开产品工坊入口") { model.enterShibuFactory(); dismiss() }.buttonStyle(.bordered).accessibilityIdentifier("connected.enterFactory") }
        }
    }
    private func hierarchy(_ node: ConnectedBuilding.Node) -> String {
        var result = [node.name], next = node.parent
        while let id = next, let parent = graph.nodes[id] { result.insert(parent.name, at: 0); next = parent.parent }
        return result.joined(separator: " / ")
    }
    private func openContent(_ destination: String) {
        guard current.kind == "room", !current.contentLocked, let floor = current.floor else { return }
        let roomID = current.id
        let origin = "circulation." + floor + ".main"
        model.currentFloor = floor
        model.sceneHistory = []
        model.buildingRoomOrigin = destination == "lab" ? nil : ("floor." + floor, origin, floor)
        model.buildingOriginHistory = []
        if floor == "L1" {
            model.l1Position = roomID; model.l1Marker = model.l1Data.point(roomID)
            if destination == "pfc" { model.pfcReturnOrigin = ("floor.L1", origin) }
        }
        model.buildingPosition = roomID
        model.navigate(destination, remember: false)
        dismiss()
    }
}

struct ConnectedBuildingLoader: View {
    @ObservedObject var model: PadModel
    var body: some View {
        if let b = Bundle.main.url(forResource: "building-v0.12", withExtension: "json"),
           let l = Bundle.main.url(forResource: "L1-space-data-v0.4", withExtension: "json"),
           let bd = try? Data(contentsOf: b), let ld = try? Data(contentsOf: l),
           let graph = try? ConnectedBuilding(building: bd, firstFloor: ld) {
            ConnectedBuildingScene(model: model, graph: graph)
        } else {
            VStack(spacing: 20) {
                Text("楼宇通路数据不完整，已停止导航。")
                Button("返回原场景") { model.showConnectedBuilding = false }
            }
        }
    }
}
#endif

struct ProductConceptScene: Identifiable {
    let id: String
    let title: String
    let image: String
    static let externalIDs: Set<String> = ["productlab.view.campus-01", "productlab.view.campus-02", "productlab.view.campus-10"]
    static var interior: [ProductConceptScene] { all.filter { !externalIDs.contains($0.id) } }
    static let all: [ProductConceptScene] = [
        .init(id: "productlab.view.campus-01", title: "总广场", image: "concept-campus-01"),
        .init(id: "productlab.view.campus-02", title: "厂房入口外观", image: "concept-campus-02"),
        .init(id: "productlab.view.campus-03", title: "入口导览厅", image: "concept-campus-03"),
        .init(id: "productlab.view.campus-04", title: "工程化厂房大厅", image: "concept-campus-04"),
        .init(id: "productlab.view.campus-05", title: "起吊试验区", image: "concept-campus-05"),
        .init(id: "productlab.view.campus-06", title: "检修通达", image: "concept-campus-06"),
        .init(id: "productlab.view.campus-07", title: "设计层走廊", image: "concept-campus-07"),
        .init(id: "productlab.view.campus-08", title: "物料接收", image: "concept-campus-08"),
        .init(id: "productlab.view.campus-09", title: "休憩交流", image: "concept-campus-09"),
        .init(id: "productlab.view.campus-10", title: "返回广场", image: "concept-campus-10"),
        .init(id: "productlab.view.campus-11", title: "产品设计工作室", image: "concept-campus-11"),
        .init(id: "productlab.view.campus-12", title: "CAD协作会议室", image: "concept-campus-12"),
        .init(id: "productlab.view.campus-13", title: "材料与样品库", image: "concept-campus-13"),
        .init(id: "productlab.view.campus-21", title: "传统清扫车展区", image: "concept-campus-21"),
        .init(id: "productlab.view.workshop-assembly-cell", title: "装配生产单元", image: "concept-workshop-assembly-cell"),
        .init(id: "productlab.view.workshop-crane-maintenance", title: "桥式天车与检修通路", image: "concept-workshop-crane-maintenance"),
        .init(id: "productlab.view.workshop-parts-warehouse", title: "零部件仓储", image: "concept-workshop-parts-warehouse"),
        .init(id: "productlab.view.workshop-quality-inspection", title: "尺寸质检工位", image: "concept-workshop-quality-inspection"),
        .init(id: "productlab.view.workshop-wireless-charge-test", title: "无线充电测试区", image: "concept-workshop-wireless-charge-test"),
        .init(id: "productlab.view.workshop-mechanical-workshop", title: "机械原型车间", image: "concept-workshop-mechanical-workshop"),
        .init(id: "productlab.view.workshop-bin-service", title: "集尘箱维护清洁", image: "concept-workshop-bin-service"),
        .init(id: "productlab.view.workshop-shipping-preparation", title: "成品打包发运", image: "concept-workshop-shipping-preparation"),
        .init(id: "productlab.view.design-01-design-studio", title: "设计室", image: "concept-design-01-design-studio"),
        .init(id: "productlab.view.design-02-perception-training", title: "视觉感知训练室", image: "concept-design-02-perception-training"),
        .init(id: "productlab.view.design-03-pickup-test", title: "簸箕拾取试验区", image: "concept-design-03-pickup-test"),
        .init(id: "productlab.view.design-04-surface-test-lane", title: "多地面测试道", image: "concept-design-04-surface-test-lane"),
        .init(id: "productlab.view.design-05-wireless-charge-lab", title: "无线充电验证室", image: "concept-design-05-wireless-charge-lab"),
        .init(id: "productlab.view.design-06-prototype-gallery", title: "样机展示区", image: "concept-design-06-prototype-gallery"),
        .init(id: "productlab.view.design-07-engineering-office", title: "工程协调办公室", image: "concept-design-07-engineering-office"),
        .init(id: "productlab.view.design-08-quality-metrology", title: "质量与尺寸检验室", image: "concept-design-08-quality-metrology")
    ]
}
