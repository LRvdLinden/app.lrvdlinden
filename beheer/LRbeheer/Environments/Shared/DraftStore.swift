import Foundation

/// Concept dat nog niet gepubliceerd is (zoals localStorage "lr-beheer-concept" in beheer.html): de versie van de
/// server waarop het gebaseerd is, het concept zelf en de nog niet geüploade afbeeldingen. In Application Support,
/// alleen op dit apparaat.
struct Draft {
    var base: JSON
    var data: JSON
    var files: [String: Data]
}

enum DraftStore {
    private static func dir(_ id: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("Drafts/\(id)", isDirectory: true)
    }

    static func load(_ id: String) -> Draft? {
        let d = dir(id)
        guard let b = try? Data(contentsOf: d.appendingPathComponent("base.json")),
              let c = try? Data(contentsOf: d.appendingPathComponent("draft.json")),
              let base = try? JSON.parse(b), let data = try? JSON.parse(c) else { return nil }
        var files: [String: Data] = [:]
        let fd = d.appendingPathComponent("files")
        if let index = try? Data(contentsOf: fd.appendingPathComponent("index.json")),
           let map = try? JSONDecoder().decode([String: String].self, from: index) {
            for (path, name) in map {
                if let bin = try? Data(contentsOf: fd.appendingPathComponent(name)) { files[path] = bin }
            }
        }
        return Draft(base: base, data: data, files: files)
    }

    static func save(_ id: String, _ draft: Draft) {
        let d = dir(id)
        let fm = FileManager.default
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        var noBackup = URLResourceValues()
        noBackup.isExcludedFromBackup = true
        var du = d
        try? du.setResourceValues(noBackup)
        try? Data(draft.base.serialized().utf8).write(to: d.appendingPathComponent("base.json"), options: .atomic)
        try? Data(draft.data.serialized().utf8).write(to: d.appendingPathComponent("draft.json"), options: .atomic)
        let fd = d.appendingPathComponent("files")
        try? fm.removeItem(at: fd)
        try? fm.createDirectory(at: fd, withIntermediateDirectories: true)
        var map: [String: String] = [:]
        for (i, (path, bin)) in draft.files.enumerated() {
            let name = "f\(i)"
            map[path] = name
            try? bin.write(to: fd.appendingPathComponent(name), options: .atomic)
        }
        if let index = try? JSONEncoder().encode(map) { try? index.write(to: fd.appendingPathComponent("index.json")) }
    }

    static func clear(_ id: String) {
        try? FileManager.default.removeItem(at: dir(id))
    }

    /// mergeDraft() uit beheer.html: alleen items die in het concept gewijzigd, toegevoegd of verwijderd zijn gaan mee,
    /// de rest komt van de server. `list` is de lijst met items met een `id` (apps, of packages/projects/reviews).
    /// Per veld samenvoegen: alleen de velden die je in dit item hebt aangepast gaan voor; de rest
    /// (bijv. versies, beoordelingen of de datum "added" van de store-check) blijft van de server.
    static func mergeFields(base: JSON, mine: JSON, server: JSON) -> JSON {
        guard case let .object(bk) = base, case let .object(mk) = mine, case .object = server else { return mine }
        var out = server
        var keys: [String] = []
        for k in bk.map(\.0) + mk.map(\.0) where !keys.contains(k) { keys.append(k) }
        for k in keys where base[k] != mine[k] {
            out[k] = mine[k]  // nil verwijdert het veld
        }
        return out
    }

    static func merge(base: JSON, draft: JSON, server: JSON, list: String) -> (data: JSON, kept: [String]) {
        let b = Dictionary(base[list]?.items.compactMap { a in a["id"]?.str.map { ($0, a) } } ?? [], uniquingKeysWith: { x, _ in x })
        let d = Dictionary(draft[list]?.items.compactMap { a in a["id"]?.str.map { ($0, a) } } ?? [], uniquingKeysWith: { x, _ in x })
        var out: [JSON] = []
        var kept: [String] = []
        for a in server[list]?.items ?? [] {
            guard let id = a["id"]?.str else { out.append(a); continue }
            if b[id] != nil && d[id] == nil { kept.append((a["name"]?.str ?? id) + " (verwijderd)"); continue }
            if let mine = d[id], let was = b[id], was != mine {
                out.append(mergeFields(base: was, mine: mine, server: a)); kept.append(mine["name"]?.str ?? id)
            } else {
                out.append(a)
            }
        }
        for (i, a) in (draft[list]?.items ?? []).enumerated() {
            guard let id = a["id"]?.str, b[id] == nil, !out.contains(where: { $0["id"]?.str == id }) else { continue }
            out.insert(a, at: min(i, out.count)); kept.append((a["name"]?.str ?? id) + " (nieuw)")
        }
        var data = server
        data[list] = .array(out)
        return (data, kept)
    }
}
