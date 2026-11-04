import SwiftUI
import MapKit

private let relFmt: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.unitsStyle = .short
    return f
}()

struct MagBadge: View {
    let q: Quake
    var size: CGFloat = 46
    var body: some View {
        Text(String(format: "%.1f", q.mag))
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundColor(.black)
            .frame(width: size, height: size)
            .background(q.color)
            .clipShape(Circle())
    }
}

struct QuakeListView: View {
    @EnvironmentObject var store: QuakeStore
    @AppStorage("minMag") private var minMag: Double = 2.5
    @AppStorage("worldwide") private var worldwide: Bool = false
    @State private var selected: Quake?

    var body: some View {
        NavigationStack {
            let list = store.quakes.filter { $0.mag >= minMag && (worldwide || inTurkeyRegion($0)) }
            List {
                if let e = store.errorText {
                    Text(e).foregroundColor(.red)
                }
                ForEach(list) { q in
                    Button { selected = q } label: {
                        HStack(spacing: 12) {
                            MagBadge(q: q)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.place.isEmpty ? "Konum bilinmiyor" : q.place)
                                    .font(.headline).foregroundColor(.primary).lineLimit(2)
                                Text("\(relFmt.localizedString(for: q.time, relativeTo: Date())) · \(Int(q.depth)) km · \(q.source.rawValue)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if list.isEmpty && !store.loading {
                    Text("Bu filtreyle deprem yok.").foregroundColor(.secondary)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Depremler")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("En az büyüklük", selection: $minMag) {
                            ForEach([0.0, 2.0, 2.5, 3.0, 4.0, 5.0], id: \.self) { v in
                                Text("M \(String(format: "%.1f", v))+").tag(v)
                            }
                        }
                        Toggle("Dünya geneli", isOn: $worldwide)
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if store.loading { ProgressView() }
                }
            }
            .sheet(item: $selected) { q in QuakeDetail(q: q) }
        }
    }
}

struct QuakeDetail: View {
    let q: Quake
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(
                        center: q.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2))),
                        annotationItems: [q]) { item in
                        MapAnnotation(coordinate: item.coordinate) { MagBadge(q: item, size: 38) }
                    }
                    .frame(height: 260)
                    .cornerRadius(14)

                    Text(q.place).font(.title2.bold())
                    row("Büyüklük", String(format: "%.1f", q.mag))
                    row("Derinlik", "\(Int(q.depth)) km")
                    row("Zaman", q.time.formatted(date: .abbreviated, time: .standard))
                    row("Kaynak", q.source.rawValue)
                    row("Koordinat", String(format: "%.3f, %.3f", q.lat, q.lon))

                    ShareLink(item: String(format: "M%.1f deprem · %@ · %@ · https://maps.apple.com/?ll=%.4f,%.4f",
                                           q.mag, q.place, q.time.formatted(date: .omitted, time: .shortened), q.lat, q.lon)) {
                        Label("Paylaş", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Deprem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundColor(.secondary); Spacer(); Text(v).bold() }
    }
}

struct MapTab: View {
    @EnvironmentObject var store: QuakeStore
    @AppStorage("minMag") private var minMag: Double = 2.5
    @AppStorage("worldwide") private var worldwide: Bool = false
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
        span: MKCoordinateSpan(latitudeDelta: 13, longitudeDelta: 22))
    @State private var selected: Quake?

    var body: some View {
        let list = Array(store.quakes.filter { $0.mag >= minMag && (worldwide || inTurkeyRegion($0)) }.prefix(200))
        ZStack(alignment: .top) {
            Map(coordinateRegion: $region, annotationItems: list) { q in
                MapAnnotation(coordinate: q.coordinate) {
                    Button { selected = q } label: {
                        Circle()
                            .fill(q.color.opacity(0.75))
                            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                            .frame(width: CGFloat(10 + q.mag * 5), height: CGFloat(10 + q.mag * 5))
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            Text("\(list.count) deprem · M\(String(format: "%.1f", minMag))+")
                .font(.caption.bold())
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
        }
        .sheet(item: $selected) { q in QuakeDetail(q: q) }
    }
}
