import SwiftUI
import SceneKit

/// Holds the currently displayed 3D model so SwiftUI can trigger swaps
/// (e.g. when the user loads a .3mf file). Shared via @EnvironmentObject.
final class SceneModelStore: ObservableObject {
    @Published var customNode: SCNNode? = nil
    @Published var statusMessage: String = "Default: wireframe icosahedron"

    /// Prompt the user for a .3mf file and load it on a background queue.
    func importModel() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["3mf"]      // accept .3mf models
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .3mf model to display in Prism"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        statusMessage = "Loading \(url.lastPathComponent)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let node = try Model3MF.loadNode(from: url)
                DispatchQueue.main.async {
                    self?.customNode = node
                    self?.statusMessage = "Loaded \(url.lastPathComponent)"
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusMessage = "⚠︎ \(error.localizedDescription)"
                }
            }
        }
    }

    func resetToDefault() {
        customNode = nil
        statusMessage = "Default: wireframe icosahedron"
    }
}

/// A live, continuously spinning SceneKit view. Renders either a procedural
/// neon wireframe icosahedron (default) or a user-supplied .3mf model.
struct Scene3DView: NSViewRepresentable {
    @ObservedObject var store: SceneModelStore

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = makeScene(with: store.customNode)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true        // user can orbit with the mouse
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        context.coordinator.lastNode = store.customNode
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        // Rebuild only when the model actually changed.
        if context.coordinator.lastNode !== store.customNode {
            view.scene = makeScene(with: store.customNode)
            context.coordinator.lastNode = store.customNode
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastNode: SCNNode? }

    // MARK: - Scene assembly

    private func makeScene(with custom: SCNNode?) -> SCNScene {
        let scene = SCNScene()

        // Camera
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        camera.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(camera)

        // Two colored rim lights for that render-engine glow
        for (color, pos) in [(NSColor(calibratedRed: 0.35, green: 0.95, blue: 1.0, alpha: 1), SCNVector3(5, 4, 6)),
                             (NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.85, alpha: 1), SCNVector3(-5, -3, 4))] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = .omni
            light.light?.color = color
            light.light?.intensity = 1200
            light.position = pos
            scene.rootNode.addChildNode(light)
        }
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 250
        scene.rootNode.addChildNode(ambient)

        // The object: custom model if present, else procedural icosahedron.
        let object = custom ?? Self.makeWireframeIcosahedron()
        object.runAction(.repeatForever(
            .rotateBy(x: 0.3, y: CGFloat.pi * 2, z: 0.12, duration: 12)
        ))
        scene.rootNode.addChildNode(object)

        // A faint reference grid floor for depth
        scene.rootNode.addChildNode(Self.makeGrid())
        return scene
    }

    /// Procedural low-poly icosahedron with a glowing wireframe overlay.
    static func makeWireframeIcosahedron() -> SCNNode {
        let geo = SCNSphere(radius: 1.6)
        geo.segmentCount = 8                   // low segment count => faceted, retro look
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.22, alpha: 1)
        mat.metalness.contents = 0.85
        mat.roughness.contents = 0.3
        mat.lightingModel = .physicallyBased
        geo.materials = [mat]
        let node = SCNNode(geometry: geo)

        let wireGeo = SCNSphere(radius: 1.605)
        wireGeo.segmentCount = 8
        let wire = SCNMaterial()
        wire.fillMode = .lines
        wire.diffuse.contents = NSColor(calibratedRed: 0.35, green: 0.95, blue: 1.0, alpha: 1)
        wire.emission.contents = NSColor(calibratedRed: 0.35, green: 0.95, blue: 1.0, alpha: 1)
        wire.lightingModel = .constant
        wireGeo.materials = [wire]
        node.addChildNode(SCNNode(geometry: wireGeo))
        return node
    }

    /// Simple emissive wire grid to ground the object in space.
    static func makeGrid() -> SCNNode {
        let plane = SCNFloor()
        plane.reflectivity = 0.05
        let mat = SCNMaterial()
        mat.fillMode = .lines
        mat.diffuse.contents = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.6, alpha: 0.5)
        mat.emission.contents = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.6, alpha: 0.4)
        mat.lightingModel = .constant
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, -2.4, 0)
        return node
    }
}
