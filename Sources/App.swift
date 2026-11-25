import SwiftUI
import StoreKit

@main
struct SKUProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ProbeRow: Identifiable {
    let id: String
    let exists: Bool
    let name: String
    let price: String
    let kind: String
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var input: String = """
g1.ios.2tb.a.12month_ip_15p
g1.ios.100gb.m.3month_ip_75p
g1.ios.20tb.m.v2
g1.ios.30tb.ai.pro.m
g1.ios.2tb.m.3month_ip_75p
g1.ios.100gb.a.12month_ip_15p
"""
    @Published var rows: [ProbeRow] = []
    @Published var status: String = "待查询"
    @Published var errors: String = ""
    @Published var busy: Bool = false

    func run() async {
        let ids = input
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == "\t" || $0 == " " })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !ids.isEmpty else {
            status = "没有候选"
            return
        }

        busy = true
        errors = ""
        rows = []
        status = "查询中… 共 \(ids.count) 条"

        var collected: [String: Product] = [:]
        var errorLines: [String] = []

        let batchSize = 40
        var start = 0
        while start < ids.count {
            let end = min(start + batchSize, ids.count)
            let slice = Array(ids[start..<end])
            do {
                let got = try await Product.products(for: slice)
                for p in got {
                    collected[p.id] = p
                }
            } catch {
                errorLines.append("批次 \(start)-\(end): \(error.localizedDescription)")
            }
            start = end
        }

        rows = ids.map { id in
            if let p = collected[id] {
                return ProbeRow(id: id, exists: true,
                                name: p.displayName,
                                price: p.displayPrice,
                                kind: "\(p.type)")
            }
            return ProbeRow(id: id, exists: false, name: "", price: "", kind: "")
        }

        let hits = collected.count
        status = "\(ids.count) 条候选，\(hits) 条存在"
        if hits == 0 {
            status += "  ← 全是 0，注意是不是接口被限制了"
        }
        errors = errorLines.joined(separator: "\n")
        busy = false
    }
}

struct ContentView: View {
    @StateObject private var model = ProbeModel()

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.status)
                    .font(.subheadline)
                    .bold()

                Text("每行一个商品编号")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                TextEditor(text: $model.input)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    Button(model.busy ? "查询中…" : "开始查询") {
                        Task { await model.run() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)

                    Button("清空结果") {
                        model.rows = []
                        model.errors = ""
                        model.status = "待查询"
                    }
                    .buttonStyle(.bordered)
                }

                List(model.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top, spacing: 6) {
                            Text(row.exists ? "✅" : "❌")
                            Text(row.id)
                                .font(.system(.caption, design: .monospaced))
                        }
                        if row.exists {
                            Text("\(row.name)    \(row.price)    \(row.kind)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)

                if !model.errors.isEmpty {
                    ScrollView {
                        Text(model.errors)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 90)
                }
            }
            .padding()
            .navigationTitle("SKU 探针")
        }
        .navigationViewStyle(.stack)
    }
}
