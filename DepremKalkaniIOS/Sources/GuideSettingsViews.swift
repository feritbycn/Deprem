import SwiftUI

private struct Section2: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

private let guideSections: [Section2] = [
    Section2(title: "Deprem öncesi", items: [
        "Afet çantanı hazırla: su, yiyecek, ilaç, düdük, el feneri, powerbank, kimlik fotokopisi.",
        "Evde ağır eşyaları sabitle; yatağın üstüne ağır tablo koyma.",
        "Ailenle buluşma noktası ve toplanma alanını önceden belirle.",
        "Gaz, su ve elektrik ana vanalarının yerini öğren."
    ]),
    Section2(title: "Deprem sırasında", items: [
        "ÇÖK – KAPAN – TUTUN. Sağlam bir masanın altına gir ya da başını ve boynunu koru.",
        "Cam, ayna ve devrilebilecek eşyalardan uzak dur.",
        "Dışarıdaysan binalardan, elektrik direklerinden ve ağaçlardan uzaklaş.",
        "Asansör kullanma; balkona ya da merdivene koşma."
    ]),
    Section2(title: "Deprem sonrası", items: [
        "Sarsıntı bitince ayakkabını giy, çantanı al, açık alana çık.",
        "Gaz kokusu varsa vanayı kapat, kıvılcım çıkaracak şey kullanma.",
        "Artçılara hazırlıklı ol; hasarlı binaya girme.",
        "Telefonu gereksiz yere meşgul etme; mesajı aramaya tercih et."
    ]),
    Section2(title: "Enkaz altındaysan", items: [
        "Sakin ol, enerjini koru. Ağzını ve burnunu bir bezle kapat.",
        "Kibrit ya da çakmak yakma; gaz olabilir.",
        "Ses çıkarmak için düdük çal ya da borulara vur; bağırmak enerjini tüketir.",
        "Acil mod sekmesindeki düdüğü ve flaşı kullan."
    ]),
    Section2(title: "Afet çantası listesi", items: [
        "3 gün yetecek su ve hazır yiyecek",
        "İlaçların, ilk yardım malzemesi",
        "El feneri, yedek pil, powerbank, radyo",
        "Düdük, battaniye, yedek kıyafet",
        "Kimlik, önemli belgelerin fotokopisi, nakit",
        "Bebek / evcil hayvan ihtiyaçları"
    ])
]

private let emergencyNumbers: [(String, String)] = [
    ("112", "Acil çağrı"), ("122", "AFAD"), ("110", "İtfaiye"), ("155", "Polis"), ("156", "Jandarma")
]

struct GuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Acil numaralar") {
                    ForEach(emergencyNumbers, id: \.0) { item in
                        Link(destination: URL(string: "tel://\(item.0)")!) {
                            HStack {
                                Image(systemName: "phone.fill").foregroundColor(.red)
                                Text("\(item.0)  \(item.1)")
                                Spacer()
                            }
                        }
                    }
                }
                ForEach(guideSections) { s in
                    Section(s.title) {
                        ForEach(s.items, id: \.self) { Text("• \($0)") }
                    }
                }
                Section("Toplanma alanı") {
                    Link("AFAD – Acil Toplanma Alanı Sorgulama",
                         destination: URL(string: "https://www.turkiye.gov.tr/afet-ve-acil-durum-yonetimi-acil-toplanma-alani-sorgulama")!)
                }
            }
            .navigationTitle("Hazırlık ve rehber")
        }
    }
}

struct SettingsView: View {
    @AppStorage("minMag") private var minMag: Double = 2.5
    @AppStorage("notifyMin") private var notifyMin: Double = 4.0
    @AppStorage("notifyOn") private var notifyOn: Bool = true
    @AppStorage("worldwide") private var worldwide: Bool = false
    @EnvironmentObject var store: QuakeStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Bildirimler") {
                    Toggle("Deprem bildirimi", isOn: $notifyOn)
                        .onChange(of: notifyOn) { v in if v { Notifier.requestPermission() } }
                    Picker("Bildirim eşiği", selection: $notifyMin) {
                        ForEach([3.0, 3.5, 4.0, 4.5, 5.0, 6.0], id: \.self) { Text("M \(String(format: "%.1f", $0))+").tag($0) }
                    }
                    Button("Test bildirimi gönder") { Notifier.test() }
                }
                Section("Liste") {
                    Picker("Listede en az", selection: $minMag) {
                        ForEach([0.0, 2.0, 2.5, 3.0, 4.0, 5.0], id: \.self) { Text("M \(String(format: "%.1f", $0))+").tag($0) }
                    }
                    Toggle("Dünya geneli", isOn: $worldwide)
                    if let t = store.lastUpdate {
                        Text("Son güncelleme: \(t.formatted(date: .omitted, time: .standard))").font(.footnote).foregroundColor(.secondary)
                    }
                }
                Section("Hakkında") {
                    Text("Veri kaynakları: AFAD, Kandilli, EMSC, USGS. Aynı deprem tek satırda birleştirilir.")
                    Text("iPhone sürümü şimdilik “Lite”: internetsiz Yakındakiler ağı, Wi-Fi paylaşma ve Yakınlarım Android sürümündedir. iOS'ta uygulama kapalıyken bildirimleri sistem seyrek çalıştırır; resmi uyarının yerine geçmez.")
                        .font(.footnote).foregroundColor(.secondary)
                    Link("Gizlilik politikası", destination: URL(string: "https://feritbycn.github.io/DepremKalkani-kod/")!)
                    Text("Sürüm 1.0.0")
                }
            }
            .navigationTitle("Ayarlar")
        }
    }
}
