import UIKit
import SceneKit
import ARKit

class ViewController: UIViewController {

    // MARK: - Outlets
    @IBOutlet var sceneView: ARSCNView!
    
    // MARK: - Types
    enum ObjectPlacementMode {
        case freeform, plane, image
    }
    
    // MARK: - Properties
    let configuration = ARWorldTrackingConfiguration()
    var selectedNode: SCNNode?
    var objectMode: ObjectPlacementMode = .freeform {
        didSet {
            reloadConfiguration()
        }
    }
    
    var lastObjectPlacedPosition: SCNVector3?
    let distanceThreshold: Float = 0.05
    
    var placedNodes = [SCNNode]()
    var planeNodes = [SCNNode]()
    
    var rootNode: SCNNode {
        return sceneView.scene.rootNode
    }
    
    var showPlaneOverlay = false {
        didSet {
            planeNodes.forEach { $0.isHidden = !showPlaneOverlay }
        }
    }
    
    // MARK:- Custom Methods
    func reloadConfiguration() {
        configuration.detectionImages = (objectMode == .image) ? ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) : nil
        
        configuration.planeDetection = [.horizontal]
        
        sceneView.session.run(configuration)
    }
    
    // MARK: - UIViewController Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadConfiguration()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    // MARK: - Object Placemode Methods
    func addNode(_ node:SCNNode, to parentNode: SCNNode) {
        let cloneNode = node.clone()
        parentNode.addChildNode(cloneNode)
        placedNodes.append(cloneNode)
    }
    
    func addNode(_ node: SCNNode, at point: CGPoint) {
        guard let result = sceneView.hitTest(point, types: [.existingPlaneUsingExtent]).first else { return }
        
        let transform = result.worldTransform
        let position = SCNVector3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        
        var distance = Float.greatestFiniteMagnitude
        
        if let lastPosition = lastObjectPlacedPosition {
            let deltaX = position.x - lastPosition.x
            let deltaY = position.y - lastPosition.y
            let deltaZ = position.z - lastPosition.z
            let sum = deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ
            distance = sqrt(sum)
            
        }
        
        if distanceThreshold < distance {
            node.position = position
            addNode(node, to: rootNode)
            lastObjectPlacedPosition = node.position
        }
    }
    
    func addNodeInFront(_ node: SCNNode) {
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        let transform = currentFrame.camera.transform
        var translation = matrix_identity_float4x4
        translation.columns.3.z = -0.2
        node.simdTransform = matrix_multiply(transform, translation)
        
        addNode(node, to: rootNode)
    }
    
    func createFloor(planeAnchor: ARPlaneAnchor) -> SCNNode {
        let node = SCNNode()
        
        let plane = SCNPlane(width: CGFloat(planeAnchor.extent.x), height: CGFloat(planeAnchor.extent.z))
        
        plane.firstMaterial?.diffuse.contents = UIColor.orange
        
        node.geometry = plane
        node.eulerAngles.x = -.pi/2
        node.opacity = 0.25
        
        return node
    }
    
    func nodeAdded(_ node: SCNNode, for anchor: ARPlaneAnchor) {
        let floor = createFloor(planeAnchor: anchor)
        floor.isHidden = !showPlaneOverlay
        
        node.addChildNode(floor)
        planeNodes.append(floor)
        
    }
    func nodeAdded(_ node: SCNNode, for anchor: ARImageAnchor) {
        guard let selectedNode = selectedNode else { return }
        addNode(selectedNode, to: node)
    }
    
    // MARK: - Touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        guard let node = selectedNode else { return }
        guard let touch = touches.first else { return }
        
        switch objectMode {
        case .freeform:
            addNodeInFront(node)
        case .plane:
            addNode(node, at: touch.location(in: sceneView))
        case .image:
            break
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        guard let node = selectedNode else { return }
        guard let touch = touches.first else { return }
        guard objectMode == .plane else { return }
        
        let newTouchPoint = touch.location(in: sceneView)
        addNode(node, at: newTouchPoint)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        lastObjectPlacedPosition = nil
    }

    // MARK: - Action
    @IBAction func changeObjectMode(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            objectMode = .freeform
            showPlaneOverlay = false
        case 1:
            objectMode = .plane
            showPlaneOverlay = true
        case 2:
            objectMode = .image
            showPlaneOverlay = false
        default:
            break
        }
    }
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOptions" {
            let optionsViewController = segue.destination as! OptionsContainerViewController
            optionsViewController.delegate = self
        }
    }
}

// MARK: - OptionsViewControllerDelegate
extension ViewController: OptionsViewControllerDelegate {
    
    func objectSelected(node: SCNNode) {
        dismiss(animated: true, completion: nil)
        selectedNode = node
    }
    
    func togglePlaneVisualization() {
        dismiss(animated: true, completion: nil)
        showPlaneOverlay.toggle()
    }
    
    func undoLastObject() {
        guard let lastNode = placedNodes.last else { return }
        lastNode.removeFromParentNode()
        placedNodes.removeLast()
    }
    
    func resetScene() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let imageAnchor = anchor as? ARImageAnchor {
            nodeAdded(node, for: imageAnchor)
        } else if let planeAnchor = anchor as? ARPlaneAnchor {
            nodeAdded(node, for: planeAnchor)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        guard let floor = node.childNodes.first else { return }
        guard let plane = floor.geometry as? SCNPlane else { return }
        floor.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
        plane.width = CGFloat(planeAnchor.extent.x)
        plane.height = CGFloat(planeAnchor.extent.z)
    }
}
