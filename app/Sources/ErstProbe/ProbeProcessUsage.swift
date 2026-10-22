import Darwin
import Foundation

/// One reading of the probe process's own CPU time and resident memory.
struct ProbeProcessUsage: Sendable {
    /// User plus system CPU time in seconds, as `getrusage` reports it.
    let cpuSeconds: Double
    /// Physical memory footprint, the number Activity Monitor shows as Memory.
    let residentBytes: UInt64

    static func read() -> ProbeProcessUsage? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        guard let residentBytes = footprintBytes() else { return nil }
        return ProbeProcessUsage(
            cpuSeconds: seconds(usage.ru_utime) + seconds(usage.ru_stime),
            residentBytes: residentBytes
        )
    }

    private static func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }

    /// Reads `phys_footprint`, which counts dirty and compressed pages rather than reservations.
    private static func footprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}
