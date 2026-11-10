import Foundation
import CoreGraphics

@Observable
final class UndoRedoManager {
    private let maxHistoryDepth = 200
    /// Snapshot actions retain full-resolution CGImages (each crop produces a
    /// distinct one), so the stacks are bounded by bytes as well as depth.
    private let maxImageBudgetBytes = 512 * 1024 * 1024
    /// Consecutive modifications sharing a coalescing key (e.g. one slider
    /// drag or colour-well session) merge into a single undo entry as long as
    /// each arrives within this interval of the previous one.
    private let coalescingInterval: TimeInterval = 1.0
    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    @ObservationIgnored private var coalescingKey: String?
    @ObservationIgnored private var lastCoalescedRecordDate: Date = .distantPast
    /// Set once trimming drops undo entries; from then on an empty undo stack
    /// no longer means the document is back where it started.
    @ObservationIgnored private var hasTrimmedUndoHistory = false

    /// Increases on every change to the document history and never goes
    /// back, so comparing against a remembered value tells whether anything
    /// was edited, undone or redone since.
    private(set) var revision = 0

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoCount: Int { undoStack.count }
    /// True while undoing has returned the document to its initial contents.
    var isAtInitialState: Bool { undoStack.isEmpty && !hasTrimmedUndoHistory }

    func recordAdd(annotation: any Annotation, state: CanvasState) {
        record(.add(annotation))
    }

    /// Records several removals as one undo step. `removals` must be listed in
    /// the order they were performed, each with the index it had at that time.
    func recordRemovals(_ removals: [(annotation: any Annotation, index: Int)], state: CanvasState) {
        guard !removals.isEmpty else { return }
        if removals.count == 1, let only = removals.first {
            record(.remove(only.annotation, index: only.index))
        } else {
            record(.group(removals.map { .remove($0.annotation, index: $0.index) }))
        }
    }

    func recordModify(oldAnnotation: any Annotation, newAnnotation: any Annotation, state: CanvasState) {
        record(.modify(old: oldAnnotation, new: newAnnotation))
    }

    /// Records a set of modifications as one undo step. When `coalescingKey`
    /// matches the previous call's key (and that call was recent and is still
    /// the top undo entry for the same annotations), the change is folded
    /// into that entry, keeping its original "old" values.
    func recordModifications(
        _ changes: [(old: any Annotation, new: any Annotation)],
        coalescingKey key: String?,
        state: CanvasState
    ) {
        guard !changes.isEmpty else { return }
        let now = Date()

        if let key,
           key == coalescingKey,
           now.timeIntervalSince(lastCoalescedRecordDate) < coalescingInterval,
           redoStack.isEmpty,
           let last = undoStack.last,
           let merged = mergedModifications(last, with: changes) {
            // A gesture that ends where it started (e.g. a toggle flipped on
            // and back off) leaves nothing to undo.
            let effective = merged.filter { !Self.isNoOp($0) }
            if let action = Self.modificationAction(for: effective) {
                undoStack[undoStack.count - 1] = action
                lastCoalescedRecordDate = now
            } else {
                undoStack.removeLast()
                coalescingKey = nil
            }
            revision += 1
            return
        }

        let effective = changes.filter { !Self.isNoOp($0) }
        guard let action = Self.modificationAction(for: effective) else { return }
        record(action)
        coalescingKey = key
        lastCoalescedRecordDate = now
    }

    private static func modificationAction(
        for changes: [(old: any Annotation, new: any Annotation)]
    ) -> UndoAction? {
        guard !changes.isEmpty else { return nil }
        if changes.count == 1, let only = changes.first {
            return .modify(old: only.old, new: only.new)
        }
        return .group(changes.map { .modify(old: $0.old, new: $0.new) })
    }

    private static func isNoOp(_ change: (old: any Annotation, new: any Annotation)) -> Bool {
        contentSignature(change.old) == contentSignature(change.new)
    }

    /// Value-level fingerprint of an annotation's stored properties (render
    /// caches excluded), used to detect modifications that change nothing.
    static func contentSignature(_ annotation: any Annotation) -> String {
        var parts = [String(describing: type(of: annotation))]
        var mirror: Mirror? = Mirror(reflecting: annotation)
        while let current = mirror {
            for child in current.children {
                let label = child.label ?? "_"
                guard !label.lowercased().contains("cache") else { continue }
                parts.append("\(label)=\(String(describing: child.value))")
            }
            mirror = current.superclassMirror
        }
        return parts.joined(separator: "|")
    }

    /// Drops the most recent undo entry if it is the addition of `id`.
    /// Used when a just-created annotation is abandoned (e.g. an empty text
    /// box) so undo doesn't resurrect it.
    @discardableResult
    func discardLastAdd(of id: UUID) -> Bool {
        guard case .add(let annotation)? = undoStack.last, annotation.id == id else { return false }
        undoStack.removeLast()
        coalescingKey = nil
        revision += 1
        return true
    }

    /// Replaces the most recent undo entry, if it is the addition of the same
    /// annotation, so creation and initial edit form a single step.
    @discardableResult
    func replaceLastAdd(with annotation: any Annotation) -> Bool {
        guard case .add(let existing)? = undoStack.last, existing.id == annotation.id else { return false }
        undoStack[undoStack.count - 1] = .add(annotation)
        coalescingKey = nil
        revision += 1
        return true
    }

    func recordSnapshot(oldState: CanvasState.Snapshot, newState: CanvasState.Snapshot, state: CanvasState) {
        if isRedundantSnapshot(oldState: oldState, newState: newState) {
            return
        }
        record(.snapshot(old: oldState, new: newState))
    }

    func undo(state: CanvasState) {
        coalescingKey = nil
        guard let action = undoStack.popLast() else { return }
        applyInverse(action, to: state)
        redoStack.append(action)
        trim(&redoStack)
        revision += 1
    }

    func redo(state: CanvasState) {
        coalescingKey = nil
        guard let action = redoStack.popLast() else { return }
        apply(action, to: state)
        undoStack.append(action)
        if trim(&undoStack) {
            hasTrimmedUndoHistory = true
        }
        revision += 1
    }

    private func record(_ action: UndoAction) {
        coalescingKey = nil
        undoStack.append(action)
        if trim(&undoStack) {
            hasTrimmedUndoHistory = true
        }
        redoStack.removeAll(keepingCapacity: true)
        revision += 1
    }

    /// Folds `changes` into an existing modification entry for the same
    /// annotations, keeping that entry's original "old" values.
    private func mergedModifications(
        _ action: UndoAction,
        with changes: [(old: any Annotation, new: any Annotation)]
    ) -> [(old: any Annotation, new: any Annotation)]? {
        let existing: [(old: any Annotation, new: any Annotation)]
        switch action {
        case .modify(let old, let new):
            existing = [(old, new)]
        case .group(let actions):
            var pairs: [(old: any Annotation, new: any Annotation)] = []
            for action in actions {
                guard case .modify(let old, let new) = action else { return nil }
                pairs.append((old, new))
            }
            existing = pairs
        default:
            return nil
        }

        guard Set(existing.map(\.old.id)) == Set(changes.map(\.old.id)),
              existing.count == changes.count else {
            return nil
        }

        let originals = Dictionary(uniqueKeysWithValues: existing.map { ($0.old.id, $0.old) })
        return changes.compactMap { change in
            guard let original = originals[change.old.id] else { return nil }
            return (old: original, new: change.new)
        }
    }

    /// Returns true if any entries were dropped.
    @discardableResult
    private func trim(_ stack: inout [UndoAction]) -> Bool {
        let originalCount = stack.count
        let overflow = stack.count - maxHistoryDepth
        if overflow > 0 {
            stack.removeFirst(overflow)
        }

        var totalBytes = 0
        for (index, action) in stack.enumerated().reversed() {
            totalBytes += approximateCost(of: action)
            if totalBytes > maxImageBudgetBytes, index < stack.count - 1 {
                // Keep the newer entries; drop everything at and before the
                // action that crossed the budget.
                stack.removeFirst(index + 1)
                break
            }
        }
        return stack.count < originalCount
    }

    private func approximateCost(of action: UndoAction) -> Int {
        switch action {
        case .add, .remove, .modify:
            return 1024
        case .group(let actions):
            return actions.reduce(0) { $0 + approximateCost(of: $1) }
        case .snapshot(let old, let new):
            let oldBytes = imageBytes(old.baseImage)
            return isSameImage(old.baseImage, new.baseImage)
                ? oldBytes
                : oldBytes + imageBytes(new.baseImage)
        }
    }

    private func imageBytes(_ image: CGImage) -> Int {
        image.bytesPerRow * image.height
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
        case .remove(let annotation, _):
            state.annotations.removeAll { $0.id == annotation.id }
        case .modify(_, let new):
            replaceAnnotation(with: new, in: state)
        case .group(let actions):
            for action in actions {
                apply(action, to: state)
            }
        case .snapshot(_, let new):
            state.restore(from: new)
        }
    }

    private func applyInverse(_ action: UndoAction, to state: CanvasState) {
        switch action {
        case .add(let annotation):
            state.annotations.removeAll { $0.id == annotation.id }
        case .remove(let annotation, let index):
            // Restore at the original stacking position, not on top.
            let insertionIndex = min(max(index, 0), state.annotations.count)
            state.annotations.insert(annotation, at: insertionIndex)
        case .modify(let old, _):
            replaceAnnotation(with: old, in: state)
        case .group(let actions):
            for action in actions.reversed() {
                applyInverse(action, to: state)
            }
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
    case remove(any Annotation, index: Int)
    case modify(old: any Annotation, new: any Annotation)
    case group([UndoAction])
    case snapshot(old: CanvasState.Snapshot, new: CanvasState.Snapshot)
}
