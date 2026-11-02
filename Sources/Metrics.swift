import Foundation
import Combine
import IOKit
import IOKit.ps

struct Sensor: Identifiable {
    let id: String
    let name: String
    let value: Double
}
struct Sample {
    var cpu: Double = 0
    var gpu: Double?
    var memory: Double = 0
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var compressed: Double = 0
    var swap: Double = 0
    var pressure = 1
    var sensors: [Sensor] = []
    var cpuTemp: Double? { average(sensors.filter { $0.id.hasPrefix("Tp") }) }
    var gpuTemp: Double? { average(sensors.filter { $0.id.hasPrefix("Tg") }) }
    var hotspot: Double? { sensors.filter { $0.id.hasPrefix("Tp") || $0.id.hasPrefix("Tg") }.map(\.value).max() }
    var down: Double = 0
    var up: Double = 0
    var diskFree: Double?
    var diskTotal: Double?
    var battery: Int?
    var charging = false
    var plugged = false
    var thermal = ProcessInfo.ThermalState.nominal
    private func average(_ values: [Sensor]) -> Double? { values.isEmpty ? nil : values.map(\.value).reduce(0,+) / Double(values.count) }
}
final class MetricsReader {
    private var previousCPU: [UInt64]?
    private var previousNetwork: (UInt64, UInt64, TimeInterval)?
    private let host = mach_host_self()
    private let cpuKeys = ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D"]
    private let gpuKeys = ["Tg0f", "Tg0j"]
    init() { _ = pulse_smc_open() }
    deinit { pulse_smc_close(); mach_port_deallocate(mach_task_self_, host) }
    func read() -> Sample {
        var s = Sample()
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if cpuResult == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3].map(UInt64.init)
            if let prev = previousCPU {
                let delta = zip(ticks, prev).map { ($0 &- $1) & 0xffffffff }
                let total = delta.reduce(0,+)
                if total > 0 { s.cpu = 100 * Double(total - delta[2]) / Double(total) }
            }
            previousCPU = ticks
        }
        var vm = vm_statistics64()
        count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        if vmResult == KERN_SUCCESS {
            var page: vm_size_t = 0
            host_page_size(host, &page)
            let used = Double(vm.active_count) + Double(vm.inactive_count) + Double(vm.speculative_count) + Double(vm.wire_count) + Double(vm.compressor_page_count) - Double(vm.purgeable_count) - Double(vm.external_page_count)
            s.memory = max(0, min(s.memoryTotal, used * Double(page)))
            s.compressed = Double(vm.compressor_page_count) * Double(page)
        }
        var pressure: Int32 = 1; var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0 { s.pressure = Int(pressure) }
        var swap = xsw_usage(); size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { s.swap = Double(swap.xsu_used) }
        for (index, key) in cpuKeys.enumerated() {
            let v = key.withCString { pulse_temperature($0) }
            if v.isFinite { s.sensors.append(Sensor(id: key, name: index < 4 ? "CPU · эффективность \(index+1)" : "CPU · производительность \(index-3)", value: v)) }
        }
        for (index, key) in gpuKeys.enumerated() {
            let v = key.withCString { pulse_temperature($0) }
            if v.isFinite { s.sensors.append(Sensor(id: key, name: "GPU · датчик \(index+1)", value: v)) }
        }
        for (key, name) in [("TB0T", "Батарея"), ("TH0x", "Накопитель")] {
            let v = key.withCString { pulse_temperature($0) }
            if v.isFinite { s.sensors.append(Sensor(id: key, name: name, value: v)) }
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        if service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any], let v = stats["Device Utilization %"] as? Double { s.gpu = max(0,min(100,v)) }
            IOObjectRelease(service)
        }
        var received: UInt64 = 0, sent: UInt64 = 0
        pulse_network(&received, &sent)
        let now = ProcessInfo.processInfo.systemUptime
        if let (r,t,time) = previousNetwork, now > time {
            s.down = received >= r ? Double(received-r)/(now-time) : 0
            s.up = sent >= t ? Double(sent-t)/(now-time) : 0
        }
        previousNetwork = (received,sent,now)
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            s.diskFree = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue
            s.diskTotal = (attrs[.systemSize] as? NSNumber)?.doubleValue
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let cap = d[kIOPSCurrentCapacityKey] as? Int, let maxCap = d[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { continue }
                s.battery = Int((Double(cap)/Double(maxCap)*100).rounded())
                s.charging = d[kIOPSIsChargingKey] as? Bool ?? false
                s.plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                break
            }
        }
        s.thermal = ProcessInfo.processInfo.thermalState
        return s
    }
}
final class Monitor: ObservableObject {
    @Published var sample = Sample()
    @Published var cpuHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var tempHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    var onUpdate: (() -> Void)?
    private let queue = DispatchQueue(label: "local.pulse.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var reader: MetricsReader?
    func start(interval: Double = 2) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if self.reader == nil { self.reader = MetricsReader() }
            guard let s = self.reader?.read() else { return }
            DispatchQueue.main.async {
                self.sample = s
                self.cpuHistory = Array((self.cpuHistory + [s.cpu]).suffix(60))
                self.gpuHistory = Array((self.gpuHistory + [s.gpu ?? 0]).suffix(60))
                self.memoryHistory = Array((self.memoryHistory + [s.memory / s.memoryTotal * 100]).suffix(60))
                if let temp = s.cpuTemp { self.tempHistory = Array((self.tempHistory + [temp]).suffix(60)) }
                self.onUpdate?()
            }
        }
        timer = t; t.resume()
    }
}
func degrees(_ value: Double?) -> String { value.map { String(format: "%.0f°", $0) } ?? "—" }
func gigabytes(_ value: Double) -> String { String(format: "%.1f", value / 1_073_741_824) }
func rate(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1f МБ/с", value/1_000_000) }
    return String(format: "%.0f КБ/с", value/1_000)
}
