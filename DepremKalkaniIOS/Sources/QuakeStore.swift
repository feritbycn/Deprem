import Foundation
import SwiftUI
import UserNotifications
import BackgroundTasks

enum Prefs {
    static let d = UserDefaults.standard
    static var minMag: Double { d.object(forKey: "minMag") as? Double ?? 2.5 }
    static var notifyMin: Double { d.object(forKey: "notifyMin") as? Double ?? 4.0 }
    static var notifyOn: Bool { d.object(forKey: "notifyOn") as? Bool ?? true }
    static var worldwide: Bool { d.bool(forKey: "worldwide") }
}

@MainActor
final class QuakeStore: ObservableObject {
    static let shared = QuakeStore()

    @Published var quakes: [Quake] = []
    @Published var loading = false
    @Published var lastUpdate: Date?
    @Published var errorText: String?

    private var refreshing = false

    func refresh() async {
        if refreshing { return }
        refreshing = true
        loading = true
        defer { refreshing = false; loading = false }

        async let a = try? Sources.afad()
        async let k = try? Sources.kandilli()
        async let e = try? Sources.emsc()
        async let u = try? Sources.usgs()
        let results: [[Quake]?] = [await a, await k, await e, await u]
        if results.allSatisfy({ $0 == nil }) {
            errorText = "Bağlantı kurulamadı. İnternetini kontrol et."
            return
        }
        errorText = nil
        quakes = Sources.merge(results.map { $0 ?? [] })
        lastUpdate = Date()
        notifyNew()
    }

    func visible() -> [Quake] {
        let minMag = Prefs.minMag
        let world = Prefs.worldwide
        return quakes.filter { $0.mag >= minMag && (world || inTurkeyRegion($0)) }
    }

    private func notifyNew() {
        let d = UserDefaults.standard
        var seen = Set(d.stringArray(forKey: "notifiedIds") ?? [])
        let initialized = d.bool(forKey: "notifiedInit")
        let min = Prefs.notifyMin
        let world = Prefs.worldwide
        let fresh = quakes.filter {
            $0.mag >= min && Date().timeIntervalSince($0.time) < 3600 &&
                (world || inTurkeyRegion($0)) && !seen.contains($0.id)
        }
        if initialized && Prefs.notifyOn {
            for q in fresh.prefix(3) { Notifier.send(q) }
        }
        for q in fresh { seen.insert(q.id) }
        d.set(Array(seen.suffix(300)), forKey: "notifiedIds")
        d.set(true, forKey: "notifiedInit")
    }
}

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func send(_ q: Quake) {
        let c = UNMutableNotificationContent()
        c.title = String(format: "M%.1f · %@", q.mag, q.place)
        c.body = "Derinlik \(Int(q.depth)) km · Kaynak: \(q.source.rawValue)"
        c.sound = .default
        let r = UNNotificationRequest(identifier: q.id, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(r)
    }

    static func test() {
        let c = UNMutableNotificationContent()
        c.title = "Deprem Kalkanı"
        c.body = "Bildirimler çalışıyor."
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotifDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

enum BG {
    static let id = "app.depremkalkani.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            schedule()
            let work = Task { @MainActor in
                await QuakeStore.shared.refresh()
                t.setTaskCompleted(success: true)
            }
            t.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}
