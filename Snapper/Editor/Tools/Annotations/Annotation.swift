import AppKit

protocol Annotation: AnyObject, Identifiable {
    var id: UUID { get }
    var type: ToolType { get }
    var zOrder: Int { get set }
    var isVisible: Bool { get set }
    var boundingRect: CGRect { get }

    func render(in context: CGContext)
    func hitTest(point: CGPoint) -> Bool
}

extension Annotation {
    func hitTest(point: CGPoint) -> Bool {
        boundingRect.contains(point)
    }
}
