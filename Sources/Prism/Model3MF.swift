import Foundation
import SceneKit

/// Loads a `.3mf` (3D Manufacturing Format) file into a SceneKit node.
///
/// A 3MF file is an OPC/ZIP container whose model lives at `3D/3dmodel.model`
/// as XML. We extract that single entry with the system `unzip` tool (no third
/// party dependencies), parse the `<vertices>`/`<triangles>` mesh, and build an
/// `SCNGeometry`. The result is returned both as a solid flat-shaded body and a
/// glowing wireframe overlay so it matches Prism's retro-CAD look.
enum Model3MF {

    enum LoadError: Error, LocalizedError {
        case unzipFailed
        case modelEntryMissing
        case emptyMesh
        var errorDescription: String? {
            switch self {
            case .unzipFailed:       return "Could not read the .3mf archive."
            case .modelEntryMissing: return "No 3D/3dmodel.model found inside the .3mf file."
            case .emptyMesh:         return "The model contained no triangles."
            }
        }
    }

    /// Parse a 3MF file at `url` and return a centered, normalized SCNNode.
    static func loadNode(from url: URL) throws -> SCNNode {
        let xml = try extractModelXML(from: url)
        let mesh = try parseMesh(xml)
        guard !mesh.indices.isEmpty else { throw LoadError.emptyMesh }
        return makeNode(from: mesh)
    }

    // MARK: - Step 1: pull 3D/3dmodel.model out of the zip container

    private static func extractModelXML(from url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -p streams the entry to stdout; the model path is fixed by the 3MF spec.
        process.arguments = ["-p", url.path, "3D/3dmodel.model"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw LoadError.unzipFailed
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard !data.isEmpty else { throw LoadError.modelEntryMissing }
        return data
    }

    // MARK: - Step 2: parse the mesh XML

    struct Mesh {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
    }

    private static func parseMesh(_ data: Data) throws -> Mesh {
        let parser = XMLParser(data: data)
        let delegate = MeshXMLDelegate()
        parser.delegate = delegate
        guard parser.parse() else { throw LoadError.modelEntryMissing }
        return delegate.mesh
    }

    private final class MeshXMLDelegate: NSObject, XMLParserDelegate {
        var mesh = Mesh()
        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes attr: [String: String]) {
            switch name {
            case "vertex":
                let x = CGFloat(Double(attr["x"] ?? "0") ?? 0)
                let y = CGFloat(Double(attr["y"] ?? "0") ?? 0)
                let z = CGFloat(Double(attr["z"] ?? "0") ?? 0)
                mesh.vertices.append(SCNVector3(x, y, z))
            case "triangle":
                if let v1 = Int32(attr["v1"] ?? ""),
                   let v2 = Int32(attr["v2"] ?? ""),
                   let v3 = Int32(attr["v3"] ?? "") {
                    mesh.indices.append(contentsOf: [v1, v2, v3])
                }
            default:
                break
            }
        }
    }

    // MARK: - Step 3: build a centered + normalized SceneKit node

    private static func makeNode(from mesh: Mesh) -> SCNNode {
        // Center on origin and scale so the largest dimension is ~2 units.
        let big = CGFloat.greatestFiniteMagnitude
        var minV = SCNVector3(big, big, big)
        var maxV = SCNVector3(-big, -big, -big)
        for v in mesh.vertices {
            minV.x = min(minV.x, v.x); minV.y = min(minV.y, v.y); minV.z = min(minV.z, v.z)
            maxV.x = max(maxV.x, v.x); maxV.y = max(maxV.y, v.y); maxV.z = max(maxV.z, v.z)
        }
        let center = SCNVector3((minV.x+maxV.x)/2, (minV.y+maxV.y)/2, (minV.z+maxV.z)/2)
        let extent = max(maxV.x-minV.x, max(maxV.y-minV.y, maxV.z-minV.z))
        // SCNVector3 components are CGFloat on macOS, so keep the scalar CGFloat too.
        let scale: CGFloat = extent > 0 ? 2.0 / extent : 1.0

        let normalized = mesh.vertices.map {
            SCNVector3(($0.x-center.x)*scale, ($0.y-center.y)*scale, ($0.z-center.z)*scale)
        }

        let vertexSource = SCNGeometrySource(vertices: normalized)
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])

        // Solid flat-shaded body
        let solid = SCNMaterial()
        solid.diffuse.contents = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.22, alpha: 1)
        solid.lightingModel = .physicallyBased
        solid.metalness.contents = 0.8
        solid.roughness.contents = 0.35
        geometry.materials = [solid]

        let node = SCNNode(geometry: geometry)

        // Glowing wireframe overlay (clone with line fill mode)
        let wireGeometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let wire = SCNMaterial()
        wire.fillMode = .lines
        wire.diffuse.contents = NSColor(calibratedRed: 0.35, green: 0.95, blue: 1.0, alpha: 1)
        wire.emission.contents = NSColor(calibratedRed: 0.35, green: 0.95, blue: 1.0, alpha: 1)
        wire.lightingModel = .constant
        wireGeometry.materials = [wire]
        let wireNode = SCNNode(geometry: wireGeometry)
        wireNode.scale = SCNVector3(1.001, 1.001, 1.001)
        node.addChildNode(wireNode)

        return node
    }
}
