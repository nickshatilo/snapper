import Foundation
import CoreGraphics

@Observable
final class UndoRedoManager {
    private let maxHistoryDepth = 200
    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func recordAdd(annotation: any Annotation, state: CanvasState) {
        record(.add(annotation))
    }

    func recordRemove(annotation: any Annotation, state: CanvasState) {
        record(.remove(annotation))
    }

    func recordModify(oldAnnotation: any Annotation, newAnnotation: any Annotation, state: CanvasState) {
        record(.modify(old: oldAnnotation, new: newAnnotation))
    }

    func recordSnapshot(oldState: CanvasState.Snapshot, newState: CanvasState.Snapshot, state: CanvasState) {
        if isRedundantSnapshot(oldState: oldState, newState: newState) {
            return
        }
        record(.snapshot(old: oldState, new: newState))
    }

    func undo(state: CanvasState) {
        guard let action = undoStack.popLast() else { return }
        applyInverse(action, to: state)
        redoStack.append(action)
        trim(&redoStack)
    }

    func redo(state: CanvasState) {
        guard let action = redoStack.popLast() else { return }
        apply(action, to: state)
        undoStack.append(action)
        trim(&undoStack)
    }

    private func record(_ action: UndoAction) {
        undoStack.append(action)
        trim(&undoStack)
        redoStack.removeAll(keepingCapacity: true)
    }

    private func trim(_ stack: inout [UndoAction]) {
        let overflow = stack.count - maxHistoryDepth
        guard overflow > 0 else { return }
        stack.removeFirst(overflow)
    }

    private func isRedundantSnapshot(oldState: CanvasState.Snapshot, newState: CanvasState.Snapshot) -> Bool {
        if snapshotsEquivalent(oldState, newState) {
            return true
        }

        guard case .snapshot(_, let lastNew)? = undoStack.last else {
            return false
        }

        return snapshotsEquivalent(lastNew, newState)
    }

    private func snapshotsEquivalent(_ lhs: CanvasState.Snapshot, _ rhs: CanvasState.Snapshot) -> Bool {
        if lhs.selectedAnnotationID != rhs.selectedAnnotationID {
            return false
        }
        if lhs.selectedAnnotationIDs != rhs.selectedAnnotationIDs {
            return false
        }
        if lhs.annotations.count != rhs.annotations.count {
            return false
        }
        if !isSameImage(lhs.baseImage, rhs.baseImage) {
            return false
        }

        for (left, right) in zip(lhs.annotations, rhs.annotations) {
            if type(of: left) != type(of: right) {
                return false
            }
            if left.id != right.id {
                return false
            }
            if left.zOrder != right.zOrder || left.isVisible != right.isVisible {
                return false
            }
            if left.boundingRect != right.boundingRect {
                return false
            }
        }

        return true
    }

    private func isSameImage(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        let lhsPtr = Unmanaged.passUnretained(lhs).toOpaque()
        let rhsPtr = Unmanaged.passUnretained(rhs).toOpaque()
        return lhsPtr == rhsPtr
    }

    private func apply(_ action: UndoAction, to state: CanvasState) {
        switch action {
        case .add(let annotation):
            state.annotations.append(annotation)
        case .remove(let annotation):
            state.annotations.removeAll { $0.id == annotation.id }
        case .modify(_, let new):
            replaceAnnotation(with: new, in: state)
        case .snapshot(_, let new):
            state.restore(from: new)
        }
    }

    private func applyInverse(_ action: UndoAction, to state: CanvasState) {
        switch action {
        case .add(let annotation):
            state.annotations.removeAll { $0.id == annotation.id }
        case .remove(let annotation):
            state.annotations.append(annotation)
        case .modify(let old, _):
            replaceAnnotation(with: old, in: state)
        case .snapshot(let old, _):
            state.restore(from: old)
        }
    }

    private func replaceAnnotation(with annotation: any Annotation, in state: CanvasState) {
        if let index = state.annotations.firstIndex(where: { $0.id == annotation.id }) {
            state.annotations[index] = annotation
        } else {
            state.annotations.append(annotation)
        }
    }
}

private enum UndoAction {
    case add(any Annotation)
    case remove(any Annotation)
    case modify(old: any Annotation, new: any Annotation)
    case snapshot(old: CanvasState.Snapshot, new: CanvasState.Snapshot)
}
