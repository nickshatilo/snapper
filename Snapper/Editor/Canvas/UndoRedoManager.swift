import Foundation

@Observable
final class UndoRedoManager {
    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func recordAdd(annotation: any Annotation, state: CanvasState) {
        undoStack.append(.add(annotation))
        redoStack.removeAll()
    }

    func recordRemove(annotation: any Annotation, state: CanvasState) {
        undoStack.append(.remove(annotation))
        redoStack.removeAll()
    }

    func recordModify(oldAnnotation: any Annotation, newAnnotation: any Annotation, state: CanvasState) {
        undoStack.append(.modify(old: oldAnnotation, new: newAnnotation))
        redoStack.removeAll()
    }

    func undo(state: CanvasState) {
        guard let action = undoStack.popLast() else { return }
        applyInverse(action, to: state)
        redoStack.append(action)
    }

    func redo(state: CanvasState) {
        guard let action = redoStack.popLast() else { return }
        apply(action, to: state)
        undoStack.append(action)
    }

    private func apply(_ action: UndoAction, to state: CanvasState) {
        switch action {
        case .add(let annotation):
            state.annotations.append(annotation)
        case .remove(let annotation):
            state.annotations.removeAll { $0.id == annotation.id }
        case .modify(_, let new):
            replaceAnnotation(with: new, in: state)
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
}
