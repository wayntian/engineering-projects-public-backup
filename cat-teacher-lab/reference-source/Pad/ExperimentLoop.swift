import SwiftUI

enum ExperimentStorage124 {
 static var root:URL {
  var root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CitadelLabPad")
  #if DEBUG
  let args=ProcessInfo.processInfo.arguments
  if let index=args.firstIndex(of:"--experiment-test-session"),index+1<args.count,let id=UUID(uuidString:args[index+1]){root=root.appendingPathComponent("UITestSessions").appendingPathComponent(id.uuidString)}
  #endif
  return root
 }
}

extension PadModel {
 func openExperiment124(records:Bool=false){panel=nil;experimentTab124=records ? 1:0;showExperimentLoop124=true}
 func saveConfiguration124(_ plan:ExperimentPlan){message=store.savePlan(plan).message}
 func selectRecord124(_ id:String){message=store.selectReview124(id).message}
}

struct ExperimentLoop124:View {
 @ObservedObject var model:PadModel
 var onClose:(()->Void)? = nil
 var onCampus:(()->Void)? = nil
 @State private var draft=ExperimentPlan.presets[0]
 var state:ExperimentState {model.store.experiment}
 var editable:Bool {state.active==nil}
 var body:some View {NavigationStack{GeometryReader{geo in
  VStack(spacing:0){
  warning.padding(.horizontal,24).padding(.top,12)
  ScrollView{VStack(alignment:.leading,spacing:18){
   Picker("阶段",selection:$model.experimentTab124){Text("配置与运行").tag(0);Text("保存记录").tag(1)}.pickerStyle(.segmented).accessibilityIdentifier("experiment.tabs")
   if model.experimentTab124==0 {
    if geo.size.width>=900 {HStack(alignment:.top,spacing:20){configuration.frame(maxWidth:.infinity);liveResult.frame(maxWidth:.infinity)}}else{configuration;liveResult}
   }else{records}
   Text(model.message).font(.callout).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("experiment.feedback")
  }.padding(24).frame(maxWidth:1300).frame(maxWidth:.infinity)}
  }.background(Color(red:0.94,green:0.97,blue:0.97))
 }.navigationTitle("L201 · 阶段实验台架").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItemGroup(placement:.confirmationAction){Button("广场"){model.showExperimentLoop124=false;if let onCampus{onCampus()}else{model.goCampus()}}.accessibilityIdentifier("experiment.plaza");Button("返回实验室"){model.showExperimentLoop124=false;onClose?()}.accessibilityIdentifier("experiment.close")}}
 .onAppear{draft=state.selectedPlan}
 .onChange(of:state.selectedPlanID){_,_ in draft=state.selectedPlan}
 .onChange(of:state.selectedPlan.revision){_,_ in draft=state.selectedPlan}
 }}
 var warning:some View {VStack(alignment:.leading,spacing:6){Label("虚拟 / 模拟结果 · 非实测",systemImage:"exclamationmark.triangle.fill").font(.title2.bold()).accessibilityIdentifier("experiment.virtualBanner");Text("此处是教学响应模型，不是照片中 LLC / PFC 电路的求解，也未连接真实仪器。不能作为真实上电依据。").font(.callout)}.foregroundStyle(Color(red:0.38,green:0.22,blue:0.04)).padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color(red:1,green:0.91,blue:0.70),in:RoundedRectangle(cornerRadius:14))}
 var configuration:some View {VStack(alignment:.leading,spacing:16){
  Text("1 · 选择并保存配置").font(.title3.bold())
  Picker("观察方案",selection:Binding(get:{state.selectedPlanID},set:{model.selectPreset($0)})){ForEach(state.plans,id:\.id){Text($0.name).tag($0.id)}}.pickerStyle(.segmented).disabled(!editable).accessibilityIdentifier("experiment.plan")
  Text("电路演示方案").font(.headline)
  Picker("电路演示方案",selection:Binding(get:{draft.moduleID},set:{id in guard let c=TeachingCircuit124.find(id) else{return};draft.moduleID=id;draft.moduleRevision=1;draft.sourceVersion=c.sourceVersion;draft.loadID=c.loadID})){ForEach(TeachingCircuit124.all){Text($0.name).tag($0.id)}}.pickerStyle(.segmented).disabled(!editable).accessibilityIdentifier("experiment.circuit")
  HStack{Text("虚拟电源");Image(systemName:"arrow.right");Text(draft.circuitName124);Image(systemName:"arrow.right");Text("\(Int(draft.teachingResistance124))Ω 负载")}.font(.footnote).padding(12).background(.cyan.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
  Text("测量仪器（虚拟）").font(.headline)
  Picker("测量仪器",selection:$draft.instrumentID){ForEach(TeachingInstrument124.all){Text($0.name).tag($0.id)}}.pickerStyle(.segmented).disabled(!editable).accessibilityIdentifier("experiment.instrument")
  Text("M 为原台架的共享仪器槽；软件万用表为独立虚拟读数，不占用 M。").font(.caption).foregroundStyle(.secondary)
  Text("M 仪器槽："+model.store.value.instrument.status).font(.caption).accessibilityIdentifier("experiment.scope.state")
  Stepper("目标 \(Int(draft.targetVoltage)) V",value:$draft.targetVoltage,in:5...30).disabled(!editable).accessibilityIdentifier("experiment.target")
  Stepper("虚拟阈值 \(Int(draft.voltageLimit)) V",value:$draft.voltageLimit,in:6...40).disabled(!editable).accessibilityIdentifier("experiment.limit")
  Stepper("采样时长 \(Int(draft.duration)) 秒",value:$draft.duration,in:4...30,step:2).disabled(!editable).accessibilityIdentifier("experiment.duration")
  Text("保存配置产生方案新版本。运行开始后冻结本轮电路、仪器和参数；更改方案不会改写旧记录。").font(.footnote)
  Button("保存配置"){model.saveConfiguration124(draft)}.buttonStyle(LabButton()).disabled(!editable).accessibilityIdentifier("experiment.config.save")
  if !editable{Text("本轮尚未保存或放弃，配置暂时锁定。").font(.footnote).foregroundStyle(.secondary)}
 }.padding(20).background(.white,in:RoundedRectangle(cornerRadius:16))}
 var liveResult:some View {VStack(alignment:.leading,spacing:16){
  Text("2 · 运行、观察与保存").font(.title3.bold())
  if let run=state.active {
   Text(run.interrupted ? "重开恢复：上次虚拟运行已中断，未自动继续":"状态："+(run.status=="running" ? "虚拟采样中":"已停止，等待保存")).font(.headline).accessibilityIdentifier("experiment.status")
   if run.interrupted {Label("保留已提交样本；仪器已释放，需重新确认才可开始下一轮。",systemImage:"pause.circle.fill").font(.callout).foregroundStyle(.orange)}
   runSummary(run)
   result(run)
   HStack{if run.status=="running"{Button("停止虚拟实验"){model.command(.stop)}.accessibilityIdentifier("experiment.stop")}else{Button("保存本轮记录"){if onClose != nil {let result=model.store.runCommand(.saveRun);model.message=result.message;if result.accepted{model.experimentTab124=1}}else{model.command(.saveRun)}}.accessibilityIdentifier("experiment.run.save");Button("放弃本轮草稿"){model.command(.discardStopped)}.accessibilityIdentifier("experiment.discard")}}.buttonStyle(LabButton())
   if run.status=="running"{Text("关闭面板仍会采样；关闭 App 后，下次启动将按中断处理。").font(.footnote)}
  }else{
   Text("就绪 · 保存配置后开始本轮虚拟实验").accessibilityIdentifier("experiment.status")
   Text("已保存方案 v\(state.selectedPlan.revision) · \(state.selectedPlan.circuitName124)\n\(state.selectedPlan.instrumentName124)").font(.headline).accessibilityIdentifier("experiment.savedConfig")
   Text("目标 \(Int(state.selectedPlan.targetVoltage))V · 阈值 \(Int(state.selectedPlan.voltageLimit))V · \(Int(state.selectedPlan.duration))秒")
   Button("开始虚拟实验"){model.command(.start)}.buttonStyle(LabButton()).disabled(draft != state.selectedPlan).accessibilityIdentifier("experiment.start")
   if draft != state.selectedPlan{Text("当前有未保存改动，请先保存配置。").foregroundStyle(.orange)}
  }
 }.padding(20).background(.white,in:RoundedRectangle(cornerRadius:16))}
 @ViewBuilder func result(_ run:ExperimentRun)->some View {
  if let last=run.samples.last {
   HStack{metric("虚拟电压",String(format:"%.3f V",last.voltage));metric("虚拟电流",String(format:"%.3f A",last.current))}.accessibilityIdentifier("experiment.readings")
   if TeachingInstrument124.find(run.configuration.instrumentID)?.waveform ?? true{WavePlot(run:run).frame(height:180).accessibilityIdentifier("experiment.waveform")}else{Text("软件万用表 · 本模型最后一次采样的电压/电流读数").font(.footnote)}
  }else{Text("尚无采样，不显示占位读数。").accessibilityIdentifier("experiment.noSamples")}
  Text("样本：\(run.samples.count) · 虚拟阈值\(run.faultObserved ? "曾超限":"未超限")").font(.footnote).accessibilityIdentifier("experiment.samples")
 }
 func metric(_ title:String,_ value:String)->some View {VStack(alignment:.leading){Text(title).font(.caption);Text(value).font(.title2.monospacedDigit().bold())}.frame(maxWidth:.infinity,alignment:.leading)}
 func runSummary(_ run:ExperimentRun)->some View {VStack(alignment:.leading,spacing:5){Text(run.configuration.circuitName124+" · "+run.configuration.instrumentName124).font(.headline).accessibilityIdentifier("experiment.snapshot");Text("方案 v\(run.configuration.revision) · \(run.configuration.sourceVersion)").font(.caption);Text(run.id).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("experiment.run.id")}}
 var records:some View {VStack(alignment:.leading,spacing:16){
  Text("已保存 \(state.history.count) 条虚拟记录").font(.headline).accessibilityIdentifier("experiment.records.count")
  if state.history.isEmpty{Text("尚无保存记录。停止并保存本轮后，记录会出现在这里。")}else{
   ScrollView(.horizontal){HStack{ForEach(state.history,id:\.id){run in Button{model.selectRecord124(run.id)}label:{VStack(alignment:.leading,spacing:5){Text(run.configuration.name+" · v\(run.configuration.revision)").bold();Text(run.configuration.circuitName124);Text(run.startedAt.formatted(date:.abbreviated,time:.shortened));Text(String(run.id.prefix(8))).font(.caption.monospaced())}.padding(14).background(model.store.selectedReview124?.id==run.id ? Color.cyan.opacity(0.18):Color.gray.opacity(0.08),in:RoundedRectangle(cornerRadius:12))}.buttonStyle(.plain).accessibilityIdentifier("experiment.record."+run.id)}}}
   if let saved=model.store.selectedReview124{VStack(alignment:.leading,spacing:12){Text("保存的虚拟结果 · 非实测").font(.title3.bold());runSummary(saved);result(saved);Text(saved.outcome ?? "虚拟记录").accessibilityIdentifier("experiment.record.outcome");Text("初始目标 \(Int(saved.configuration.targetVoltage))V · 阈值 \(Int(saved.configuration.voltageLimit))V · 已采样 \(String(format:"%.2f",saved.elapsed))秒").font(.footnote);Text("操作事件：\(saved.adjustments.count) · 电路/仪器快照随记录保存").font(.footnote)}.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:16))}
  }
 }.frame(maxWidth:.infinity,alignment:.leading)}
}
