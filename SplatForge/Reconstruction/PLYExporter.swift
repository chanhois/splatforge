import Foundation

nonisolated enum PLYExporter {
    static func write(points: [SparsePoint3D], to url: URL) throws {
        var lines = [
            "ply",
            "format ascii 1.0",
            "element vertex \(points.count)",
            "property float x",
            "property float y",
            "property float z",
            "property uchar red",
            "property uchar green",
            "property uchar blue",
            "end_header"
        ]

        lines.append(contentsOf: points.map { point in
            "\(point.position.x) \(point.position.y) \(point.position.z) "
                + "\(point.color.x) \(point.color.y) \(point.color.z)"
        })

        try (lines.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }
}
