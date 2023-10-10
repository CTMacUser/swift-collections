//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2021 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A [Min-Max Heap](https://en.wikipedia.org/wiki/Min-max_heap) data structure.
///
/// In a min-max heap, each node at an even level in the tree is less than or
/// equal to all its descendants, while each node at an odd level in the tree is
/// greater than or equal to all of its descendants.
///
/// The implementation is based on [Atkinson et al. 1986]:
///
/// [Atkinson et al. 1986]: https://doi.org/10.1145/6617.6621
///
/// M.D. Atkinson, J.-R. Sack, N. Santoro, T. Strothotte.
/// "Min-Max Heaps and Generalized Priority Queues."
/// *Communications of the ACM*, vol. 29, no. 10, Oct. 1986., pp. 996-1000,
/// doi:[10.1145/6617.6621](https://doi.org/10.1145/6617.6621)
@frozen
public struct Heap<Element: Comparable> {
  @usableFromInline
  internal var _storage: ContiguousArray<Element>

  /// Creates an empty heap.
  @inlinable
  public init() {
    _storage = []
  }
}

extension Heap: Sendable where Element: Sendable {}

extension Heap {
  /// A Boolean value indicating whether or not the heap is empty.
  ///
  /// - Complexity: O(1)
  @inlinable @inline(__always)
  public var isEmpty: Bool {
    _storage.isEmpty
  }

  /// The number of elements in the heap.
  ///
  /// - Complexity: O(1)
  @inlinable @inline(__always)
  public var count: Int {
    _storage.count
  }

  /// A view of a `Heap`'s underlying storage of elements.
  ///
  /// The correspondence between an element's storage position and its order
  /// ranking is private to `Heap`, and may change between revisions.
  ///
  /// - Warning: If `Element` is a reference type, do not mutate elements such
  ///   that their relative order rankings change.
  public typealias UnorderedView = [Element]

  /// A read-only view into the underlying array.
  ///
  /// Note: The elements aren't _arbitrarily_ ordered (it is, after all, a
  /// heap). However, no guarantees are given as to the ordering of the elements
  /// or that this won't change in future versions of the library.
  ///
  /// - Complexity: O(1)
  @inlinable
  public var unordered: UnorderedView {
    Array(_storage)
  }

  /// Inserts the given element into the heap.
  ///
  /// - Complexity: O(log(`count`)) element comparisons
  @inlinable
  public mutating func insert(_ element: Element) {
    _storage.append(element)

    _update { handle in
      handle.bubbleUp(_HeapNode(offset: handle.count - 1))
    }
    _checkInvariants()
  }

  /// Returns the element with the lowest priority, if available.
  ///
  /// - Complexity: O(1)
  @inlinable
  public func min() -> Element? {
    _storage.first
  }

  /// Returns the element with the highest priority, if available.
  ///
  /// - Complexity: O(1)
  @inlinable
  public func max() -> Element? {
    _storage.withUnsafeBufferPointer { buffer in
      guard buffer.count > 2 else {
        // If count is 0, `last` will return `nil`
        // If count is 1, the last (and only) item is the max
        // If count is 2, the last item is the max (as it's the only item in the
        // first max level)
        return buffer.last
      }
      // We have at least 3 items -- return the larger of the two in the first
      // max level
      return Swift.max(buffer[1], buffer[2])
    }
  }

  /// Removes and returns the element with the lowest priority, if available.
  ///
  /// - Complexity: O(log(`count`)) element comparisons
  @inlinable
  public mutating func popMin() -> Element? {
    guard _storage.count > 0 else { return nil }

    var removed = _storage.removeLast()

    if _storage.count > 0 {
      _update { handle in
        let minNode = _HeapNode.root
        handle.swapAt(minNode, with: &removed)
        handle.trickleDownMin(minNode)
      }
    }

    _checkInvariants()
    return removed
  }

  /// Removes and returns the element with the highest priority, if available.
  ///
  /// - Complexity: O(log(`count`)) element comparisons
  @inlinable
  public mutating func popMax() -> Element? {
    guard _storage.count > 2 else { return _storage.popLast() }

    var removed = _storage.removeLast()

    _update { handle in
      if handle.count == 2 {
        if handle[.leftMax] > removed {
          handle.swapAt(.leftMax, with: &removed)
        }
      } else {
        let maxNode = handle.maxValue(.rightMax, .leftMax)
        handle.swapAt(maxNode, with: &removed)
        handle.trickleDownMax(maxNode)
      }
    }

    _checkInvariants()
    return removed
  }

  /// Removes and returns the element with the lowest priority.
  ///
  /// The heap *must not* be empty.
  ///
  /// - Complexity: O(log(`count`)) element comparisons
  @inlinable
  public mutating func removeMin() -> Element {
    return popMin()!
  }

  /// Removes and returns the element with the highest priority.
  ///
  /// The heap *must not* be empty.
  ///
  /// - Complexity: O(log(`count`)) element comparisons
  @inlinable
  public mutating func removeMax() -> Element {
    return popMax()!
  }

  /// Replaces the minimum value in the heap with the given replacement,
  /// then updates heap contents to reflect the change.
  ///
  /// The heap must not be empty.
  ///
  /// - Parameter replacement: The value that is to replace the current
  ///   minimum value.
  /// - Returns: The original minimum value before the replacement.
  ///
  /// - Complexity: O(log(`count`)) element comparisons
  @inlinable
  @discardableResult
  public mutating func replaceMin(with replacement: Element) -> Element {
    precondition(!isEmpty, "No element to replace")

    var removed = replacement
    _update { handle in
      let minNode = _HeapNode.root
      handle.swapAt(minNode, with: &removed)
      handle.trickleDownMin(minNode)
    }
    _checkInvariants()
    return removed
  }

  /// Replaces the maximum value in the heap with the given replacement,
  /// then updates heap contents to reflect the change.
  ///
  /// The heap must not be empty.
  ///
  /// - Parameter replacement: The value that is to replace the current maximum
  ///   value.
  /// - Returns: The original maximum value before the replacement.
  ///
  /// - Complexity: O(log(`count`)) element comparisons
  @inlinable
  @discardableResult
  public mutating func replaceMax(with replacement: Element) -> Element {
    precondition(!isEmpty, "No element to replace")

    var removed = replacement
    _update { handle in
      switch handle.count {
      case 1:
        handle.swapAt(.root, with: &removed)
      case 2:
        handle.swapAt(.leftMax, with: &removed)
        handle.bubbleUp(.leftMax)
      default:
        let maxNode = handle.maxValue(.leftMax, .rightMax)
        handle.swapAt(maxNode, with: &removed)
        handle.bubbleUp(maxNode)  // This must happen first
        handle.trickleDownMax(maxNode)  // Either new element or dethroned min
      }
    }
    _checkInvariants()
    return removed
  }
}

// MARK: -

extension Heap {
  /// Initializes a heap from a sequence.
  ///
  /// - Complexity: O(*n*), where *n* is the number of items in `elements`.
  @inlinable
  public init<S: Sequence>(_ elements: S) where S.Element == Element {
    _storage = ContiguousArray(elements)
    guard _storage.count > 1 else { return }

    _update { handle in
      handle.heapify()
    }
    _checkInvariants()
  }

  /// Inserts the elements in the given sequence into the heap.
  ///
  /// - Parameter newElements: The new elements to insert into the heap.
  ///
  /// - Complexity: O(*n* * log(`count`)), where *n* is the length of `newElements`.
  @inlinable
  public mutating func insert<S: Sequence>(
    contentsOf newElements: S
  ) where S.Element == Element {
    if count == 0 {
      self = Self(newElements)
      return
    }
    _storage.reserveCapacity(count + newElements.underestimatedCount)
    for element in newElements {
      insert(element)
    }
  }
}

// MARK: -

extension Heap {
  /// Returns a Boolean value indicating whether the heap contains the given
  /// element.
  ///
  /// This example checks to see whether a favorite actor is in a heap storing a
  /// movie's cast.
  ///
  ///     let cast: Heap = ["Vivien", "Marlon", "Kim", "Karl"]
  ///     print(cast.contains("Marlon"))
  ///     // Prints "true"
  ///     print(cast.contains("James"))
  ///     // Prints "false"
  ///
  /// - Parameter element: The element to find in the heap.
  /// - Returns: `true` if the element was found in the heap; otherwise,
  ///   `false`.
  ///
  /// - Complexity: O(log `count`).
  @inlinable
  public func contains(_ element: Element) -> Bool {
    #if true
    // Pre-allocate an array for all potential searched-for nodes.  (Only
    // appending will happen, no removals nor random inserts, to minimize cache
    // invalidation.)
    var nodes = [_Node]()
    nodes.reserveCapacity(count)
    if !isEmpty {
      nodes.append(.root)
    }

    // Do a breadth-first search.
    var i = nodes.startIndex, areMinLevels = true
    while i < nodes.endIndex {
      let limit = nodes.endIndex
      let outsideCheck: (Element, Element) -> Bool = areMinLevels ? (<) : (>)
      while i < limit {
        // Equality and out-of-bounds checks
        let node = nodes[i], nodeElement = _storage[node.offset]
        guard element != nodeElement else { return true }
        defer { nodes.formIndex(after: &i) }
        guard !outsideCheck(element, nodeElement) else { continue }

        // Target may be within node's subtree.  Queue up its direct child nodes
        // to check.  (We're appending as we go, but `Array` always uses
        // `0..<count` as indices, so index values are never invalidated)
        if case let leftNode = node.leftChild(), leftNode.offset < count {
          nodes.append(leftNode)
        }
        if case let rightNode = node.rightChild(), rightNode.offset < count {
          nodes.append(rightNode)
        }
      }
      areMinLevels.toggle()
    }
    return false
    #else
    // Do a depth-based search.
    guard !isEmpty else { return false }

    func _contains(
      _ target: Element, within node: _Node, isMinLevel: Bool
    ) -> Bool {
      // Direct check
      let nodeElement = _storage[node.offset]
      if target == nodeElement {
        return true
      }

      // Out-of-bounds check
      if (isMinLevel ? (<) : (>))(target, nodeElement) {
        return false
      }

      // Left sub-tree
      let leftNode = node.leftChild()
      guard leftNode.offset < count else { return false }  // Also no right tree

      if _contains(target, within: leftNode, isMinLevel: !isMinLevel) {
        return true  // short circuit
      }

      // Right sub-tree
      let rightNode = node.rightChild()
      guard rightNode.offset < count else { return false }

      return _contains(target, within: rightNode, isMinLevel: !isMinLevel)
    }

    return _contains(element, within: .root, isMinLevel: true)
    #endif
  }
}
