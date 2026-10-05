import Foundation
import IOKit.ps

/// Live CPU / memory / battery readings via public Darwin + IOKit APIs.
@MainActor
@Observable
final class SystemStatsStore {
    private(set) var cpu: Double = 0        // 0…1 busy fraction
    private(set) var memory: Double = 0     // 0…1 used fraction
    private(set) var batteryLevel: Double?  // 0…1, nil on desktops
    private(set) var isCharging = false
    private(set) var hasBattery = false

    private var ticker: Task<Void, Never>?
    private var prevCPU: host_cpu_load_info?

    func start() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    private func sample() {
        if let value = readCPU() { cpu = value }
        if let value = readMemory() { memory = value }
        readBattery()
    }

    private func readCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        defer { prevCPU = info }
        guard let prev = prevCPU else { return nil }

        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (user + system + nice) / total
    }

    private func readMemory() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = Double(sysconf(Int32(_SC_PAGESIZE)))
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return min(1, max(0, used / total))
    }

    private func readBattery() {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            hasBattery = false
            batteryLevel = nil
            return
        }
        if let current = desc[kIOPSCurrentCapacityKey] as? Int,
           let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
            hasBattery = true
            batteryLevel = Double(current) / Double(max)
        }
        isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
    }
}
