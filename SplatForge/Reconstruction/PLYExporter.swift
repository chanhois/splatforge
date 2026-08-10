import Foundation

nonisolated enum PLYExporter {
    static func write(points: [SparsePoint3D], to url: URL) throws {
        try Task.checkCancellation()
        let header = [
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
        var contents = header.joined(separator: "\n") + "\n"

        for (index, point) in points.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            contents.append(
                "\(point.position.x) \(point.position.y) \(point.position.z) "
                    + "\(point.color.x) \(point.color.y) \(point.color.z)\n"
            )
        }

        try Task.checkCancellation()
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
