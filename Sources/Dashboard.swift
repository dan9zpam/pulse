import SwiftUI
import ServiceManagement

private let mint = Color(red: 0.43, green: 0.91, blue: 0.76)
private let lavender = Color(red: 0.68, green: 0.64, blue: 1)
private let amber = Color(red: 1, green: 0.73, blue: 0.43)
private let panel = Color.white.opacity(0.045)

struct Sparkline: View {
    let values: [Double]
    var color: Color = mint
    var ceiling: Double = 100
    var body: some View {
        GeometryReader { geo in
            let points = values.enumerated().map { index, v in
                CGPoint(x: geo.size.width * CGFloat(index + max(0,60-values.count)) / 59,
                        y: geo.size.height * (1-CGFloat(min(ceiling,max(0,v))/ceiling)))
            }
            Canvas { ctx, size in
                for fraction in [0.25,0.75] {
                    var grid = Path(); grid.move(to: CGPoint(x: 0,y: size.height*fraction)); grid.addLine(to: CGPoint(x: size.width,y: size.height*fraction))
                    ctx.stroke(grid, with: .color(.white.opacity(0.06)), style: StrokeStyle(lineWidth: 0.5, dash: [2,4]))
                }
                guard let first = points.first, let last = points.last else { return }
                var line = Path(); line.move(to: first)
                for p in points.dropFirst() { line.addLine(to:p) }
                var fill = line; fill.addLine(to: CGPoint(x:last.x,y:size.height)); fill.addLine(to:CGPoint(x:first.x,y:size.height)); fill.closeSubpath()
                ctx.fill(fill, with: .linearGradient(Gradient(colors:[color.opacity(0.22),color.opacity(0)]),startPoint:.zero,endPoint:CGPoint(x:0,y:size.height)))
                ctx.stroke(line, with:.color(color),style:StrokeStyle(lineWidth:1.8,lineCap:.round,lineJoin:.round))
                ctx.fill(Path(ellipseIn:CGRect(x:last.x-2.5,y:last.y-2.5,width:5,height:5)),with:.color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
struct MetricCard: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let history: [Double]
    let color: Color
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            HStack(spacing:6) { Image(systemName:symbol).foregroundStyle(color); Text(title).foregroundStyle(.secondary); Spacer() }.font(.system(size:11,weight:.medium))
            HStack(alignment:.firstTextBaseline,spacing:3) { Text(value).font(.system(size:29,weight:.medium,design:.rounded)).monospacedDigit(); Spacer() }
            Sparkline(values:history,color:color).frame(height:35)
            Text(detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(13).background(panel,in:RoundedRectangle(cornerRadius:16))
        .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.055)))
    }
}
struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @State private var showSensors = CommandLine.arguments.contains("--expanded-sensors")
    @State private var launchError: String?
    @State private var launchEnabled = SMAppService.mainApp.status == .enabled
    @AppStorage("showCPU") private var showCPU = false
    @AppStorage("refreshInterval") private var refreshInterval = 2.0
    var settingsChanged: () -> Void
    private var s: Sample { monitor.sample }
    private var thermalText: String {
        switch s.thermal {
        case .nominal: return "Тепловая нагрузка macOS: норма"
        case .fair: return "Тепловая нагрузка macOS: умеренная"
        case .serious: return "Тепловая нагрузка macOS: высокая"
        case .critical: return "Тепловая нагрузка macOS: критическая"
        @unknown default: return "Состояние системы неизвестно"
        }
    }
    var body: some View {
        VStack(spacing:16) {
            HStack(spacing:10) {
                Image(systemName:"waveform.path.ecg").font(.system(size:22,weight:.medium)).foregroundStyle(mint)
                    .frame(width:40,height:40).background(mint.opacity(0.1),in:RoundedRectangle(cornerRadius:12))
                VStack(alignment:.leading,spacing:3) {
                    Text("Pulse").font(.system(size:21,weight:.semibold,design:.rounded))
                    Text("MacBook Air  /  Apple M2").font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(mint).frame(width:5,height:5)
                Text("СЕЙЧАС").font(.system(size:9,weight:.semibold)).tracking(1.1).foregroundStyle(mint)
            }
            VStack(alignment:.leading,spacing:12) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:3) {
                        Label("ТЕМПЕРАТУРА CPU",systemImage:"thermometer.medium").font(.system(size:10,weight:.semibold)).tracking(0.8).foregroundStyle(amber)
                        HStack(alignment:.firstTextBaseline,spacing:1) {
                            Text(s.cpuTemp.map { String(format:"%.0f",$0) } ?? "—").font(.system(size:57,weight:.light,design:.rounded)).monospacedDigit()
                            Text("°C").font(.system(size:23,weight:.regular)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment:.trailing,spacing:9) {
                        Text("GPU  \(degrees(s.gpuTemp))").font(.system(size:12,weight:.medium)).monospacedDigit()
                        Text("Пик датчиков  \(degrees(s.hotspot))").font(.system(size:10)).foregroundStyle(.secondary).monospacedDigit()
                        Text("Пассивное охлаждение").font(.system(size:9)).foregroundStyle(.secondary)
                    }.padding(.top,3)
                }
                Sparkline(values:monitor.tempHistory,color:amber,ceiling:110).frame(height:44)
                HStack(spacing:6) {
                    Circle().fill(s.thermal == .nominal ? mint : amber).frame(width:5,height:5)
                    Text(s.cpuTemp == nil ? "Датчики температуры недоступны" : thermalText).font(.system(size:10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(refreshInterval*60)) с").font(.system(size:9)).foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(LinearGradient(colors:[amber.opacity(0.08),panel],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(amber.opacity(0.12)))
            HStack(spacing:10) {
                MetricCard(title:"Процессор",symbol:"cpu",value:String(format:"%.0f%%",s.cpu),detail:"8 ядер · нагрузка CPU",history:monitor.cpuHistory,color:mint)
                MetricCard(title:"Графика",symbol:"square.3.layers.3d",value:s.gpu.map { String(format:"%.0f%%",$0) } ?? "—",detail:"Загрузка GPU",history:monitor.gpuHistory,color:lavender)
            }
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Label("Память",systemImage:"memorychip").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(gigabytes(s.memory)) / \(gigabytes(s.memoryTotal)) ГБ").font(.system(size:12,weight:.medium)).monospacedDigit()
                }
                GeometryReader { g in
                    ZStack(alignment:.leading) {
                        Capsule().fill(.white.opacity(0.06))
                        Capsule().fill(s.pressure >= 4 ? Color.red : s.pressure >= 2 ? amber : lavender).frame(width:g.size.width*min(1,s.memory/s.memoryTotal))
                    }
                }.frame(height:5)
                HStack {
                    Text(s.pressure >= 4 ? "Нагрузка высокая" : s.pressure >= 2 ? "Нагрузка повышена" : "Нагрузка в норме")
                    Spacer()
                    Text("Swap \(gigabytes(s.swap)) ГБ")
                }.font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(14).background(panel,in:RoundedRectangle(cornerRadius:14))
            HStack(spacing:0) {
                VStack(alignment:.leading,spacing:6) {
                    Label("Сеть",systemImage:"network").foregroundStyle(.secondary)
                    HStack(spacing:10) {
                        Text("↓ \(rate(s.down))").foregroundStyle(mint)
                        Text("↑ \(rate(s.up))").foregroundStyle(lavender)
                    }.monospacedDigit()
                }.frame(maxWidth:.infinity,alignment:.leading)
                Rectangle().fill(.white.opacity(0.08)).frame(width:1,height:28).padding(.horizontal,12)
                VStack(alignment:.leading,spacing:6) {
                    Label("Диск",systemImage:"internaldrive").foregroundStyle(.secondary)
                    Text(s.diskFree.map { "\(Int($0/1_000_000_000)) ГБ свободно" } ?? "—").monospacedDigit()
                }
            }.font(.system(size:10)).padding(.horizontal,3)
            HStack(spacing:7) {
                Image(systemName:s.plugged ? "battery.100percent.bolt" : "battery.75percent").foregroundStyle(mint)
                Text(s.battery.map { "\($0)%" } ?? "—").monospacedDigit()
                Text(s.charging ? "Заряжается" : s.plugged ? "От сети" : "От аккумулятора").foregroundStyle(.secondary)
                Spacer()
                Button { showSensors.toggle() } label: {
                    HStack(spacing:4) { Text("Датчики"); Image(systemName:showSensors ? "chevron.up" : "chevron.down") }
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.font(.system(size:11))
            if showSensors {
                ScrollView {
                    VStack(spacing:7) {
                        if s.sensors.isEmpty { Text("SMC не вернул данные датчиков").foregroundStyle(.secondary) }
                        ForEach(s.sensors) { sensor in
                            HStack { Text(sensor.name).foregroundStyle(.secondary); Spacer(); Text(degrees(sensor.value)).monospacedDigit() }
                        }
                    }.font(.system(size:11)).padding(12)
                }.frame(height:145).background(panel,in:RoundedRectangle(cornerRadius:12))
            }
            Divider().overlay(.white.opacity(0.04))
            HStack {
                Text("Обновление каждые \(Int(refreshInterval)) с").font(.system(size:9)).foregroundStyle(.tertiary)
                Spacer()
                Menu {
                    Toggle("Показывать CPU в строке меню",isOn:$showCPU).onChange(of:showCPU) { _ in settingsChanged() }
                    Menu("Частота обновления") {
                        ForEach([2.0,3.0,5.0],id:\.self) { interval in
                            Button("\(Int(interval)) секунды\(refreshInterval == interval ? " ✓" : "")") { refreshInterval = interval; monitor.start(interval:interval) }
                        }
                    }
                    Toggle("Запускать при входе",isOn:Binding(get:{ launchEnabled },set:{ enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchEnabled = SMAppService.mainApp.status == .enabled
                            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
                        } catch { launchError = error.localizedDescription }
                    }))
                    Divider()
                    Button("Открыть Мониторинг системы") { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Utilities/Activity Monitor.app")) }
                    Button("Исходный код") { NSWorkspace.shared.open(URL(fileURLWithPath:NSHomeDirectory()+"/Projects/Pulse")) }
                    Divider()
                    Button("Завершить Pulse") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName:"gearshape").font(.system(size:13)).foregroundStyle(.secondary) }
                .menuStyle(.borderlessButton).fixedSize().help("Настройки Pulse")
            }
        }
        .padding(20).frame(width:380)
        .background(Color(red:0.055,green:0.065,blue:0.085))
        .preferredColorScheme(.dark)
        .alert("Не удалось изменить автозапуск",isPresented:Binding(get:{ launchError != nil },set:{ if !$0 { launchError = nil } })) { Button("Понятно") { launchError = nil } } message: { Text(launchError ?? "") }
    }
}
