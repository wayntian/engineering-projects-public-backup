import Foundation

/// Intent is distance based, never a count of gestures or a dwell timer.
struct RoamApproach {
    private(set) var progress: Double = 0
    private(set) var target: String?
    mutating func aim(_ id: String?) { if target != id { target = id; progress = 0 } }
    mutating func advance(_ amount: Double) { guard target != nil else { return }; progress = min(1, max(0, progress + amount)) }
    mutating func cancel() { progress = 0 }
    var ready: Bool { target != nil && progress >= 0.72 }
}

/// Save only committed positions, never an in-flight transition or zoom progress.
struct RoamCheckpoint: Codable {
    var schema = 1
    let route: [String]
    let target: String?
    let pictureVariant: Int

    init(walk: BuildingWalk, target: String?, pictureVariant: Int) {
        route = walk.history + [walk.position]
        self.target = target
        self.pictureVariant = pictureVariant
    }
    func restore(in graph: ConnectedBuilding) -> BuildingWalk? {
        guard schema == 1, let first = route.first,
              let node = graph.nodes[first],
              !["world", "building", "floor", "planning"].contains(node.kind) else { return nil }
        var walk = BuildingWalk(graph: graph, start: first)
        for next in route.dropFirst() { guard walk.step(to: next) else { return nil } }
        return walk
    }
    func validTarget(in walk: BuildingWalk) -> String? {
        guard let target, walk.graph.neighbors(of: walk.position).contains(where: { $0.id == target }) else { return nil }
        return target
    }
    func validPictureVariant(in walk: BuildingWalk) -> Int {
        guard let node = walk.graph.nodes[walk.position], RoamPicture.options(for: node).indices.contains(pictureVariant) else { return 0 }
        return pictureVariant
    }
}

enum RoamCheckpointStore {
    static var key: String {
        let base = "lightweightRoam.committedCheckpoint.v1"
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--experiment-test-session"), index + 1 < args.count,
           let session = UUID(uuidString: args[index + 1]) { return base + ".test." + session.uuidString }
        #endif
        return base
    }
    static func load() -> RoamCheckpoint? {
        guard let data = UserDefaults.standard.data(forKey: key), data.count <= 1_000_000 else { return nil }
        return try? JSONDecoder().decode(RoamCheckpoint.self, from: data)
    }
    static func save(_ checkpoint: RoamCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct RoamPicture {
    let asset: String?
    let exact: Bool
    static func options(for node: ConnectedBuilding.Node) -> [String] {
        let base = forNode(node).asset.map { [$0] } ?? []
        let external: [String]
        switch node.id {
        case "space.L1.plaza": external = ["concept-campus-01", "concept-campus-10"]
        case "productlab.entrance": external = ["concept-campus-02"]
        default: external = []
        }
        return base + external
    }
    static func forNode(_ node: ConnectedBuilding.Node) -> Self {
        if let scene = ProductConceptScene.all.first(where: { $0.id == node.id }) { return .init(asset: scene.image, exact: true) }
        switch node.id {
        case "space.L1.plaza": return .init(asset: "campus-plaza-concept", exact: true)
        case "productlab.entrance": return .init(asset: "product-entrance-concept", exact: true)
        case "productlab.hall", "factory.shibu", "productlab.traditional": return .init(asset: "product-hall-concept", exact: node.id == "productlab.hall")
        case "space.L1.lobby": return .init(asset: "home-l1-central-corridor-v5", exact: true)
        case "entry.core.L1": return .init(asset: "l1-south-foyer-cl01-v3", exact: true)
        case "circulation.L1.coreLanding": return .init(asset: "core-l1-inside-v1", exact: false)
        case "space.L2.L201": return .init(asset: "room", exact: true)
        case "space.L2.L201.assets": return .init(asset: "assetbay", exact: true)
        case "space.L1.L103": return .init(asset: "pfc-room-entry-v1", exact: true)
        case "space.L3.L303": return .init(asset: "lounge-l3-v1", exact: true)
        case "space.L4.L402": return .init(asset: "lounge-l4-v1", exact: true)
        default:
            if node.contentLocked { return .init(asset: nil, exact: false) }
            if let floor = node.floor {
                return .init(asset: ["L2":"corridor-l2-wide-v1", "L3":"corridor-l3-wide-v1", "L4":"corridor-l4-wide-v1"][floor], exact: false)
            }
            return .init(asset: nil, exact: false)
        }
    }
}

/// Only the accepted plaza panorama has full spherical coverage. Ordinary views stay bounded.
enum RoamViewportSource: Equatable {
    case plazaPanorama
    case photo(String)
    static func forNode(_ node: ConnectedBuilding.Node, variant: Int) -> Self? {
        if node.id == "space.L1.plaza", variant == 0 { return .plazaPanorama }
        let pictures = RoamPicture.options(for: node)
        guard pictures.indices.contains(variant) else { return nil }
        return .photo(pictures[variant])
    }
    var isSpherical: Bool { self == .plazaPanorama }
    var disclosure: String {
        isSpherical ? "AI 球面全景 · 可环顾整圈、天空与地面 · 接缝及极点待修" : "有限视角原图 · 可拖动与缩放 · 此处完整 360° 素材尚缺"
    }
}

/// Direction comes from the existing floor plan, never inferred from AI pixels.
struct RoamSpatialIndex {
    var points: [String: CGPoint] = [:]
    init(building: Data, firstFloor: Data) {
        for data in [building, firstFloor] {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for key in ["nodes", "rooms", "corridors", "doors", "waypoints"] {
                for item in object[key] as? [[String: Any]] ?? [] {
                    guard let id = item["id"] as? String else { continue }
                    if let pair = (item["point"] ?? item["anchor"] ?? item["center"]) as? [Double], pair.count >= 2 {
                        points[id] = CGPoint(x: pair[0], y: pair[1])
                    } else if let b = item["bounds"] as? [Double], b.count == 4 {
                        points[id] = CGPoint(x: b[0] + b[2] / 2, y: b[1] + b[3] / 2)
                    }
                }
            }
        }
    }
    func direction(from a: ConnectedBuilding.Node, to b: ConnectedBuilding.Node) -> String {
        if let af = a.floor, let bf = b.floor, af != bf { return "楼梯 · " + af + " → " + bf }
        guard let p = points[a.id], let q = points[b.id], a.floor == b.floor || a.id == "space.L1.plaza" || b.id == "space.L1.plaza" else { return "相邻通路 · 朝向待标定" }
        let dx = q.x - p.x, dy = q.y - p.y
        guard hypot(dx, dy) > 0.01 else { return "同一门区" }
        let sector = Int((atan2(dx, -dy) * 4 / .pi + 8).rounded()) % 8
        return "图上" + ["北", "东北", "东", "东南", "南", "西南", "西", "西北"][sector]
    }
}

#if os(iOS)
import SwiftUI
import UIKit

enum AnyRoamLabelStyle: LabelStyle {
    case icon, title
    func makeBody(configuration: Configuration) -> some View {
        Group { if self == .icon { configuration.icon.frame(minWidth: 28, minHeight: 28) } else { configuration.title } }
    }
}

extension PadModel {
    func resumeRoam() {
        guard !l1Busy, !liftBusy, !buildingBusy else { return }
        if let saved = roamWalk, saved.graph.nodes[buildingPosition] != nil, saved.position != buildingPosition, roamOriginalPosition != buildingPosition { roamWalk = BuildingWalk(graph: saved.graph, start: buildingPosition); roamAim = nil; roamPictureVariant = 0 }
        showRoam = true
    }
}

struct LightweightRoamLoader: View {
    @ObservedObject var model: PadModel
    var body: some View {
        if let b = Bundle.main.url(forResource: "building-v0.12", withExtension: "json"),
           let l = Bundle.main.url(forResource: "L1-space-data-v0.4", withExtension: "json"),
           let bd = try? Data(contentsOf: b), let ld = try? Data(contentsOf: l),
           let graph = try? ConnectedBuilding(building: bd, firstFloor: ld) {
            LightweightRoam(model: model, graph: graph)
        } else {
            VStack { Text("漫游通路未载入，原有场景仍保留。"); Button("返回原场景") { model.showRoam = false } }.padding()
        }
    }
}

struct LightweightRoam: View {
    @ObservedObject var model: PadModel
    let graph: ConnectedBuilding
    @State private var walk: BuildingWalk
    @State private var approach = RoamApproach()
    @State private var busy = false
    @State private var transitionToken = UUID()
    @State private var feedback = "拖动画面环顾 · 双指缩放 · 下方选择去向后前进"
    @State private var picture: UIImage?
    @State private var pictureVariant = 0
    @State private var viewportStatus = "正在载入可拖动场景…"
    @State private var viewportReset = 0
    @State private var showLessons = false
    @State private var showExperiment = false
    @State private var showPanorama = false
    @State private var spatial: RoamSpatialIndex?
    @Environment(\.scenePhase) private var scenePhase
    init(model: PadModel, graph: ConnectedBuilding) {
        self.model = model; self.graph = graph
        var start = "space.L1.plaza"
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--roam-start"), arguments.count > i + 1, graph.nodes[arguments[i+1]] != nil { start = arguments[i+1] }
        #endif
        var checkpoint = model.roamWalk == nil ? RoamCheckpointStore.load() : nil
        #if DEBUG
        if arguments.contains("--roam-start") || arguments.contains("--roam-reset") { checkpoint = nil }
        #endif
        let savedWalk = checkpoint?.restore(in: graph)
        let restoredWalk = model.roamWalk ?? savedWalk ?? BuildingWalk(graph: graph, start: start)
        _walk = State(initialValue: restoredWalk)
        var restoredApproach = RoamApproach()
        let aim = model.roamWalk != nil ? model.roamAim : savedWalk.flatMap { checkpoint?.validTarget(in: $0) }
        if let aim, graph.neighbors(of: restoredWalk.position).contains(where: { $0.id == aim }) { restoredApproach.aim(aim) }
        _approach = State(initialValue: restoredApproach)
        let options = RoamPicture.options(for: graph.nodes[restoredWalk.position]!)
        let variant = model.roamWalk != nil ? model.roamPictureVariant : savedWalk.map { checkpoint?.validPictureVariant(in: $0) ?? 0 } ?? 0
        _pictureVariant = State(initialValue: options.indices.contains(variant) ? variant : 0)
        if model.roamWalk == nil, savedWalk != nil {
            _feedback = State(initialValue: "已回到上次停留位置 · 可继续前进，也可沿原路退后")
        }
    }
    private var current: ConnectedBuilding.Node { graph.nodes[walk.position]! }
    private var neighbors: [ConnectedBuilding.Node] { graph.neighbors(of: walk.position) }
    private var target: ConnectedBuilding.Node? { approach.target.flatMap { graph.nodes[$0] } }
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                ZStack {
                    background(size: geometry.size)
                        .scaleEffect(1 + approach.progress * 0.18)
                        .opacity(busy ? 0.38 : 1)
                        .animation(.easeInOut(duration: 0.65), value: busy)
                        .animation(.easeOut(duration: 0.35), value: approach.progress)
                    VStack {
                        Text(displayName(current)).font(isPhone ? .title3.bold() : .largeTitle.bold()).multilineTextAlignment(.center)
                            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("roam.position")
                        Spacer()
                        if busy { Label("跨过空间边界…", systemImage: "figure.walk").padding().background(.regularMaterial, in: Capsule()) }
                        if let target, !busy {
                            VStack(spacing: 10) {
                                Label(displayName(target), systemImage: target.floor != current.floor ? "stairs" : "arrow.up").font(.headline).multilineTextAlignment(.center).accessibilityIdentifier("roam.target")
                                Text(spatial?.direction(from: current, to: target) ?? "相邻通路").font(.caption)
                                if approach.ready {
                                    Button("进入 · " + displayName(target)) { crossBoundary() }.buttonStyle(.borderedProminent)
                                        .frame(minHeight: 48).accessibilityIdentifier("roam.enter")
                                } else {
                                    Text("向前接近").font(.subheadline)
                                    ProgressView(value: approach.progress / 0.72).frame(maxWidth: 150)
                                }
                            }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                                .frame(maxWidth: isPhone ? 280 : 420)
                        }
                        Text(feedback).font(.footnote).multilineTextAlignment(.center).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityIdentifier("roam.feedback")
                    }.padding(isPhone ? 12 : 24)
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped().contentShape(Rectangle())

            }
            footer
        }.background(Color(red: 0.94, green: 0.96, blue: 0.95))
            .interactiveDismissDisabled()
            .onAppear {
                if let b = Bundle.main.url(forResource: "building-v0.12", withExtension: "json"), let l = Bundle.main.url(forResource: "L1-space-data-v0.4", withExtension: "json"), let bd = try? Data(contentsOf: b), let ld = try? Data(contentsOf: l) { spatial = RoamSpatialIndex(building: bd, firstFloor: ld) }
                if let selected = approach.target, neighbors.contains(where: { $0.id == selected }) { approach.cancel(); loadPicture() } else { refresh() }
            }
            .onDisappear { cancelPending(); saveCheckpoint(); model.roamOriginalPosition = model.buildingPosition }
            .onChange(of: approach.target) { _, _ in saveCheckpoint() }
            .onChange(of: pictureVariant) { _, _ in saveCheckpoint() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelPending(); saveCheckpoint() }
            }
            .fullScreenCover(isPresented: $showLessons) { LearningShelf(onCampus: { showLessons = false; returnToPlaza() }) }
            .fullScreenCover(isPresented: $showExperiment) { ExperimentLoop124(model: model, onClose: { showExperiment = false }, onCampus: { showExperiment = false; returnToPlaza() }) }
            .fullScreenCover(isPresented: $showPanorama) {
                PlazaPanoramaScene(onLab: { aimToward("circulation.L1.coreLanding") }, onFactory: { aimToward("productlab.hall") })
            }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { retreat() } label: { Label("退后", systemImage: "chevron.left").labelStyle(isPhone ? AnyRoamLabelStyle.icon : AnyRoamLabelStyle.title) }.disabled(busy || (walk.history.isEmpty && approach.progress == 0)).accessibilityIdentifier("roam.back")
            Spacer()
            Text(isPhone ? "步进漫游" : (current.floor ?? "园区") + " · 步进漫游").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            Text(current.id).font(.system(size:1)).foregroundStyle(.clear).frame(width:1,height:1).accessibilityIdentifier("roam.node")
            Text(approach.target ?? "").font(.system(size:1)).foregroundStyle(.clear).frame(width:1,height:1).accessibilityIdentifier("roam.targetID")
            Spacer()
            Button("广场") { returnToPlaza() }.disabled(busy).accessibilityIdentifier("roam.plaza")
            Button { model.showRoam = false } label: { Label("退出漫游", systemImage: "xmark").labelStyle(isPhone ? AnyRoamLabelStyle.icon : AnyRoamLabelStyle.title) }.disabled(busy).accessibilityIdentifier("roam.original")
        }.buttonStyle(.bordered).frame(minHeight: 48).padding(.horizontal, 12)
    }
    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Button { turn(-1) } label: { Label("去向", systemImage: "chevron.left") }.accessibilityIdentifier("roam.turnPrevious")
                Spacer()
                Button(approach.ready ? "门前 · 可进入" : "前进一步") { advance(0.4) }.accessibilityIdentifier("roam.forward")
                Spacer()
                Button { turn(1) } label: { Label("去向", systemImage: "chevron.right") }.accessibilityIdentifier("roam.turnNext")
            }.buttonStyle(.bordered).disabled(busy)
            localActions
            if let source = RoamViewportSource.forNode(current, variant: pictureVariant) {
                Text(source.disclosure + (pictureVariant > 0 ? " · 概念观察变体，跨图结构未统一" : !source.isSpherical && !RoamPicture.forNode(current).exact ? " · 借用本层示意图，非该节点专属画面" : "")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text(viewportStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("roam.viewportStatus")
            } else {
                Text("通路位置已建立 · 该处专属画面／室内内容开发中").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }
    @ViewBuilder private var localActions: some View {
        if !busy {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if RoamViewportSource.forNode(current, variant: pictureVariant) != nil {
                        Button("复位视角") { viewportReset += 1 }.accessibilityIdentifier("roam.resetViewport")
                    }
                    if current.id == "circulation.L1.coreLanding" || current.id.hasPrefix("entry.E01.") {
                        Button("电梯 · 本层入口") { openElevator() }.accessibilityIdentifier("roam.elevator")
                    }
                    if RoamPicture.options(for: current).count > 1 {
                        Button("另一观察视角") {
                            approach.cancel(); pictureVariant = (pictureVariant + 1) % RoamPicture.options(for: current).count; loadPicture()
                        }.accessibilityIdentifier("roam.observation")
                    }
                    if current.id == "space.L1.plaza" { Button("环顾广场全景") { approach.cancel(); showPanorama = true }.accessibilityIdentifier("roam.panorama") }
                    if let destination = current.destination, !current.contentLocked {
                        Button("查看 · " + displayName(current)) { openOriginal(destination) }.accessibilityIdentifier("roam.openContent")
                    }
                    if current.id.hasPrefix("productlab.") || current.id.hasPrefix("factory.shibu") {
                        Button("展项与工程底账") { openOriginal("factory.shibu") }.accessibilityIdentifier("roam.factoryDetails")
                    }
                    if ["space.L2.L201", "space.L2.L202", "factory.shibu"].contains(current.id) {
                        Button("LLC / 拾步阅读") { approach.cancel(); showLessons = true }.accessibilityIdentifier("roam.reading")
                    }
                    if current.id == "space.L2.L201" {
                        Button("虚拟实验台") { approach.cancel(); showExperiment = true }.accessibilityIdentifier("roam.experiment")
                    }
                }.buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
    }
    @ViewBuilder private func background(size: CGSize) -> some View {
        let key = current.id + "/" + String(pictureVariant)
        if let source = RoamViewportSource.forNode(current, variant: pictureVariant) {
            EmbeddedSceneViewport(source: source, sceneName: displayName(current), initialPose: model.roamViewportPoses[key],
                active: scenePhase == .active && !busy && !showLessons && !showExperiment && !showPanorama,
                reset: viewportReset) { pose, status in
                    guard key == current.id + "/" + String(pictureVariant) else { return }
                    if let pose { model.roamViewportPoses[key] = pose }
                    viewportStatus = status
                }.id(key).frame(width: size.width, height: size.height).clipped()
        } else {
            ZStack {
                LinearGradient(colors: [.teal.opacity(0.12), .white, .gray.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 20) { Image(systemName: current.kind == "room" ? "door.left.hand.closed" : current.kind == "door" ? "door.left.hand.open" : "figure.walk").font(.system(size: 72)); Text("位置示意 · 内容开发中").font(.headline) }.foregroundStyle(.secondary)
            }
        }
    }
    private func displayName(_ node: ConnectedBuilding.Node) -> String {
        switch node.id {
        case "approach.plaza.exit.L1": return "实验楼外廊 · 安全出口方向"
        case "bridge.exit.ST01.L1": return "跨桥 · 实验楼首层入口"
        case "bridge.entrance.L1": return "大厅与前室之间的跨桥"
        default: return node.name
        }
    }
    private func refresh() {
        pictureVariant = 0; loadPicture()
        let previous = walk.history.last
        let options = neighbors.filter { $0.id != previous }
        let next = options.first(where: { $0.kind == "concept_view" }) ?? options.first ?? neighbors.first
        approach = RoamApproach(); approach.aim(next?.id)
        saveCheckpoint()
    }
    private func saveCheckpoint() {
        model.roamWalk = walk; model.roamAim = approach.target; model.roamPictureVariant = pictureVariant
        RoamCheckpointStore.save(RoamCheckpoint(walk: walk, target: approach.target, pictureVariant: pictureVariant))
    }
    private func loadPicture() {
        let options = RoamPicture.options(for: current)
        guard options.indices.contains(pictureVariant), let path = Bundle.main.path(forResource: options[pictureVariant], ofType: "png") else { picture = nil; return }
        picture = UIImage(contentsOfFile: path)
    }
    private func turn(_ delta: Int) {
        guard !busy, !neighbors.isEmpty else { return }
        let index = neighbors.firstIndex(where: { $0.id == approach.target }) ?? 0
        approach.aim(neighbors[(index + delta + neighbors.count) % neighbors.count].id)
        feedback = "去向：" + (target.map { displayName($0) } ?? "") + " · 向前接近后进入"
    }
    private func advance(_ amount: Double) {
        guard !busy else { return }
        approach.advance(amount)
        feedback = approach.ready ? "已到入口 · 轻点进入；左上角可退后" : "向入口接近中 · 可以停下来观察"
    }
    private func crossBoundary() {
        guard !busy, approach.ready, let id = approach.target, neighbors.contains(where: { $0.id == id }) else { return }
        busy = true; let token = UUID(); transitionToken = token
        feedback = "正在沿相邻通路跨入：" + (target.map { displayName($0) } ?? "")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            guard transitionToken == token, busy else { return }
            guard walk.step(to: id) else { cancelPending(); return }
            busy = false; refresh(); feedback = "已到达：" + displayName(current) + " · 可停留观察或继续前进"
        }
    }
    private func retreat() {
        guard !busy else { return }
        if approach.progress > 0 { approach.cancel(); feedback = "已退回观察位置"; return }
        guard !walk.history.isEmpty else { feedback = "已在本次漫游起点"; return }
        busy = true; let token = UUID(); transitionToken = token; feedback = "正在沿原路退回…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            guard transitionToken == token, busy else { return }
            _ = walk.back(); busy = false; refresh(); feedback = "沿原路退回：" + displayName(current)
        }
    }
    private func cancelPending() { transitionToken = UUID(); busy = false; approach.cancel() }
    private func returnToPlaza() {
        guard !busy else { return }
        // Explicit global safety return, not an invented walking edge.
        walk = BuildingWalk(graph: graph, start: "space.L1.plaza"); refresh(); feedback = "已使用全局返回回到广场"
    }
    private func aimToward(_ id: String) {
        guard let path = graph.path(from: walk.position, to: id), path.count > 1 else { return }
        approach.aim(path[1]); feedback = "面向" + (graph.nodes[id]?.name ?? "入口") + " · 沿现有通路逐段进入"
    }
    private func openOriginal(_ destination: String) {
        guard !busy else { return }; approach.cancel(); model.roamWalk = walk
        if let floor = current.floor { model.currentFloor = floor }
        model.sceneHistory = []
        model.buildingPosition = current.id
        model.buildingRoomOrigin = nil
        if destination == "pfc" { model.pfcReturnOrigin = ("floor.L1", "circulation.L1.main") }
        if current.floor == "L1" { model.l1Position = current.id; model.l1Marker = model.l1Data.point(current.id) }
        if let floor = current.floor, floor != "L1", destination != "lab" {
            model.buildingRoomOrigin = ("floor." + floor, "circulation." + floor + ".main", floor)
            model.buildingOriginHistory = []
        }
        model.navigate(destination, remember: false)
        if destination == "factory.shibu" { model.buildingPosition = current.id }
        model.showRoam = false
    }
    private func openElevator() {
        guard !busy, let floor = current.floor else { return }
        approach.cancel(); model.roamWalk = walk; model.buildingRoomOrigin = nil
        model.currentFloor = floor; model.buildingPosition = current.id
        if floor == "L1" {
            model.l1Position = current.id; model.l1Marker = model.l1Data.point(current.id)
            model.navigate("core.L1", remember: false)
        } else { model.navigate("corridor." + floor, remember: false) }
        model.showRoam = false
        let expectedStage = model.stage
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard UIApplication.shared.applicationState == .active, !model.showRoam, model.stage == expectedStage, model.currentFloor == floor else { return }
            model.enterElevator()
        }
    }
}
#endif
