import Foundation
struct NormalizedRect:Codable {let x:Double;let y:Double;let width:Double;let height:Double;func contains(x px:Double,y py:Double)->Bool {px>=x && py>=y && px<=x+width && py<=y+height};var area:Double{width*height}}
struct BenchObject:Codable {let id:String;let assetID:String;let name:String;let bounds:NormalizedRect;let actions:[String]}
struct ActionDescriptor {let id:String;let label:String;let enabled:Bool;let disabledReason:String?;let route:String}
struct RunObservation {let runID:String?;let phase:String;let voltage:Double;let current:Double;let samples:Int;let configurationRevision:Int;let moduleID:String;let instrumentState:String}
final class BenchSceneEngine {
 private(set) var objects:[BenchObject]=[];private(set) var selectedObjectID:String?;private(set) var observation=RunObservation(runID:nil,phase:"idle",voltage:0,current:0,samples:0,configurationRevision:1,moduleID:"module.virtual.demo",instrumentState:"可用")
 let registry=["openSupply":"参数与输出","openScope":"波形观测","openModule":"模块详情","openSchematic":"虚拟原理示意","prepare":"实验方案","openLoad":"虚拟负载"]
 var onObservation:(()->Void)?
 init(configuration:URL?=nil){let url=configuration ?? Bundle.main.url(forResource:"bench-objects",withExtension:"json");if let url{try? load(url)}}
 func load(_ url:URL)throws {let input=try JSONDecoder().decode([BenchObject].self,from:Data(contentsOf:url));guard !input.isEmpty,Set(input.map{$0.id}).count==input.count,input.allSatisfy({$0.bounds.width>0 && $0.bounds.height>0 && $0.bounds.x>=0 && $0.bounds.y>=0 && $0.bounds.x+$0.bounds.width<=1 && $0.bounds.y+$0.bounds.height<=1 && $0.actions.allSatisfy{registry[$0] != nil}}) else{throw NSError(domain:"SceneConfiguration",code:1,userInfo:[NSLocalizedDescriptionKey:"对象ID、命中范围或动作未通过校验。"])};objects=input}
 func hitTest(x:Double,y:Double)->BenchObject? {objects.sorted{$0.bounds.area<$1.bounds.area}.first{$0.bounds.contains(x:x,y:y)}}
 func select(_ id:String)->Bool {guard objects.contains(where:{$0.id==id}) else{return false};selectedObjectID=id;return true}
 func actions(for id:String)->[ActionDescriptor] {guard let object=objects.first(where:{$0.id==id}) else{return []};return object.actions.map{ActionDescriptor(id:$0,label:registry[$0] ?? $0,enabled:true,disabledReason:nil,route:$0)}}
 func route(for id:String,actionID:String?=nil)->ActionDescriptor? {let actions=actions(for:id);return actionID.flatMap{id in actions.first{$0.id==id}} ?? actions.first}
 func bind(_ store:AssetStore,onChange:@escaping()->Void){onObservation=onChange;refresh(store);store.onChange={[weak self,weak store] in guard let store else{return};self?.refresh(store)}}
 func refresh(_ store:AssetStore){let e=store.experiment;let run=e.active ?? e.history.first;let sample=run?.samples.last;observation=RunObservation(runID:run?.id,phase:e.active?.status ?? (e.history.isEmpty ? "idle":"saved"),voltage:sample?.voltage ?? 0,current:sample?.current ?? 0,samples:run?.samples.count ?? 0,configurationRevision:run?.configuration.revision ?? e.selectedPlan.revision,moduleID:run?.configuration.moduleID ?? e.selectedPlan.moduleID,instrumentState:run?.configuration.instrumentID=="instrument.virtual.meter" ? (e.active?.status=="running" ? "软件仪器占用":"软件仪器可用"):store.value.instrument.status);onObservation?()}
}
