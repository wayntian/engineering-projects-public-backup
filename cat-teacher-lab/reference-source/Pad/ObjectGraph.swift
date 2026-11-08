import Foundation
struct GraphNode:Decodable {let id:String;let type:String;let floor:String?;let parentId:String?;let displayCode:String?;let locked:Bool?}
struct GraphEdge:Decodable {let source:String;let target:String;let kind:String;let bidirectional:Bool}
struct PhotoLink:Decodable {let destination:String;let name:String;let x:CGFloat;let y:CGFloat}
struct SpatialGraph:Decodable {
 let version:String;let floors:[String];let rooms:[SpatialRoom];let nodes:[GraphNode];let edges:[GraphEdge];let stageNodes:[String:String];let photoLinks:[String:[PhotoLink]]
 static let shared:SpatialGraph = {let url=Bundle.main.url(forResource:"building-graph-v0.7",withExtension:"json")!;return try! JSONDecoder().decode(SpatialGraph.self,from:Data(contentsOf:url))}()
 var nodeByID:[String:GraphNode] {Dictionary(uniqueKeysWithValues:nodes.map{($0.id,$0)})}
 func owner(_ id:String)->String {let n=nodeByID[id];if let p=n?.parentId{return owner(p)};return id}
 func path(_ source:String,_ target:String,allowVertical:Bool=false)->[String]? {
  let lookup=nodeByID;guard lookup[source] != nil,lookup[target] != nil else{return nil}
  var queue=[[source]],seen=Set([source]);while !queue.isEmpty{let p=queue.removeFirst(),id=p.last!;if id==target{return p};for e in edges where e.kind=="transit" || (allowVertical && e.kind=="vertical") {let next=e.source==id ? e.target : e.bidirectional && e.target==id ? e.source : "";guard !next.isEmpty,!seen.contains(next),lookup[next]?.locked != true else{continue};seen.insert(next);queue.append(p+[next])}};return nil
 }
 func stageRoute(_ source:String,_ target:String)->[String]? {
  guard let a=stageNodes[source],let b=stageNodes[target] else{return nil};if source=="elevator" || target=="elevator"{return path(owner(a),owner(b),allowVertical:true)}
  return path(owner(a),owner(b))
 }
 func roomPath(from stage:String,to room:SpatialRoom)->[String]? {guard let id=stageNodes[stage] else{return nil};return path(owner(id),room.id)}
}
