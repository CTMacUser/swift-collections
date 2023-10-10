//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
#if COLLECTIONS_SINGLE_MODULE
import Collections
#else
import _RopeModule
import _CollectionsTestSupport
#endif

struct Chunk: RopeElement, Equatable, CustomStringConvertible {
  var length: Int
  var value: Int
  
  struct Summary: RopeSummary, Comparable {
    var length: Int
    
    init(_ length: Int) {
      self.length = length
    }
    
    static var zero: Self { Self(0) }
    
    var isZero: Bool { length == 0 }
    
    mutating func add(_ other: Self) {
      length += other.length
    }
    
    mutating func subtract(_ other: Self) {
      length -= other.length
    }
    
    static func ==(left: Self, right: Self) -> Bool { left.length == right.length }
    static func <(left: Self, right: Self) -> Bool { left.length < right.length }
    
    static var maxNodeSize: Int { 6 }
    static var nodeSizeBitWidth: Int { 3 }
  }
  
  struct Metric: RopeMetric {
    typealias Element = Chunk
    
    func size(of summary: Chunk.Summary) -> Int {
      summary.length
    }
    
    func index(at offset: Int, in element: Chunk) -> Int {
      precondition(offset >= 0 && offset <= element.length)
      return offset
    }
  }
  
  init(length: Int, value: Int) {
    self.length = length
    self.value = value
  }
  
  var description: String {
    "\(value)*\(length)"
  }
  
  var summary: Summary {
    Summary(length)
  }
  
  var isEmpty: Bool { length == 0 }
  var isUndersized: Bool { isEmpty }
  
  func invariantCheck() {}
  
  mutating func rebalance(prevNeighbor left: inout Chunk) -> Bool {
    // Fully merge neighbors that have the same value
    if left.value == self.value {
      self.length += left.length
      left.length = 0
      return true
    }
    if left.isEmpty { return true }
    guard self.isEmpty else { return false }
    swap(&self, &left)
    return true
  }
  
  mutating func rebalance(nextNeighbor right: inout Chunk) -> Bool {
    // Fully merge neighbors that have the same value
    if self.value == right.value {
      self.length += right.length
      right.length = 0
      return true
    }
    if right.isEmpty { return true }
    guard self.isEmpty else { return false }
    swap(&self, &right)
    return true
  }

  typealias Index = Int

  mutating func split(at index: Int) -> Chunk {
    precondition(index >= 0 && index <= length)
    let tail = Chunk(length: length - index, value: value)
    self.length = index
    return tail
  }
}

class TestRope: XCTestCase {
  override func setUp() {
    print("Global seed: \(RepeatableRandomNumberGenerator.globalSeed)")
  }
  
  func test_empty() {
    let empty = Rope<Chunk>()
    empty._invariantCheck()
    XCTAssertTrue(empty.isEmpty)
    XCTAssertEqual(empty.count, 0)
    XCTAssertTrue(empty.summary.isZero)
    XCTAssertEqual(empty.startIndex, empty.endIndex)
  }
  
  func test_build() {
    let c = 1000
    
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }
    var builder = Rope<Chunk>.Builder()
    for chunk in ref {
      builder.insertBeforeTip(chunk)
      builder._invariantCheck()
    }
    let rope = builder.finalize()
    
    let actualSum = rope.summary
    let expectedSum: Chunk.Summary = ref.reduce(into: .zero) { $0.add($1.summary) }
    XCTAssertEqual(actualSum, expectedSum)
    
    XCTAssertTrue(rope.elementsEqual(ref))
  }
  
  func test_iteration() {
    for c in [0, 1, 2, 10, 100, 500, 1000, 10000] {
      let ref = (0 ..< c).map {
        Chunk(length: ($0 % 4) + 1, value: $0)
      }
      let rope = Rope(ref)

      var it = rope.makeIterator()
      var i = 0
      while let next = it.next() {
        let expected = ref[i]
        XCTAssertEqual(next, expected)
        guard next == expected else { break }
        i += 1
      }
      XCTAssertEqual(i, ref.count)

      let expectedLength = ref.reduce(into: 0) { $0 += $1.length }
      let actualLength = rope.reduce(into: 0) { $0 += $1.length }
      XCTAssertEqual(actualLength, expectedLength)
    }
  }
  
  func test_subscript() {
    for c in [0, 1, 2, 10, 100, 500, 1000, 10000] {
      let ref = (0 ..< c).map {
        Chunk(length: ($0 % 4) + 1, value: $0)
      }
      let rope = Rope(ref)
      XCTAssertTrue(rope.elementsEqual(ref))
      
      var i = rope.startIndex
      var j = 0
      while i != rope.endIndex, j != ref.count {
        XCTAssertEqual(rope[i], ref[j])
        i = rope.index(after: i)
        j += 1
      }
      XCTAssertEqual(i, rope.endIndex)
      XCTAssertEqual(j, ref.count)
    }
  }
  
  func test_index_before() {
    for c in [0, 1, 2, 10, 100, 500, 1000, 10000] {
      let ref = (0 ..< c).map {
        Chunk(length: ($0 % 4) + 1, value: $0)
      }
      let rope = Rope(ref)
      XCTAssertTrue(rope.elementsEqual(ref))
      
      var indices: [Rope<Chunk>.Index] = []
      var i = rope.startIndex
      while i != rope.endIndex {
        indices.append(i)
        i = rope.index(after: i)
      }
      
      while let j = indices.popLast() {
        i = rope.index(before: i)
        XCTAssertEqual(i, j)
      }
    }
  }
  
  func test_distance() {
    let c = 500
    
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }
    let rope = Rope<Chunk>(ref)
    
    let indices = Array(rope.indices) + [rope.endIndex]
    XCTAssertEqual(indices.count, c + 1)
    for i in indices.indices {
      for j in indices.indices {
        let d = rope.distance(from: indices[i], to: indices[j], in: Chunk.Metric())
        let r = (
          i <= j
          ? ref[i..<j].reduce(into: 0) { $0 += $1.length }
          : ref[j..<i].reduce(into: 0) { $0 -= $1.length })
        XCTAssertEqual(d, r, "i: \(i), j: \(j)")
      }
    }
  }
  
  func test_index_offsetBy() {
    let c = 500
    
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }
    let rope = Rope<Chunk>(ref)
    
    let indices = Array(rope.indices) + [rope.endIndex]
    XCTAssertEqual(indices.count, c + 1)
    for i in indices.indices {
      for j in indices.indices {
        let d = (
          i <= j
          ? ref[i..<j].reduce(into: 0) { $0 += $1.length }
          : ref[j..<i].reduce(into: 0) { $0 -= $1.length })
        let r = rope.index(indices[i], offsetBy: d, in: Chunk.Metric(), preferEnd: false)
        XCTAssertEqual(r.index, indices[j])
        XCTAssertEqual(r.remaining, 0)
      }
    }
  }
  
  func test_append_item() {
    let c = 1000
    var rope = Rope<Chunk>()
    var ref: [Chunk] = []
    
    for i in 0 ..< c {
      let chunk = Chunk(length: (i % 4) + 1, value: i)
      ref.append(chunk)
      rope.append(chunk)
      rope._invariantCheck()
    }
    
    let actualSum = rope.summary
    let expectedSum: Chunk.Summary = ref.reduce(into: .zero) { $0.add($1.summary) }
    XCTAssertEqual(actualSum, expectedSum)
    
    XCTAssertTrue(rope.elementsEqual(ref))
  }
  
  func test_prepend_item() {
    let c = 1000
    
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }
    
    var rope = Rope<Chunk>()
    for chunk in ref.reversed() {
      rope.insert(chunk, at: 0, in: Chunk.Metric())
      rope._invariantCheck()
    }
    
    let actualSum = rope.summary
    let expectedSum: Chunk.Summary = ref.reduce(into: .zero) { $0.add($1.summary) }
    XCTAssertEqual(actualSum, expectedSum)
    
    XCTAssertTrue(rope.elementsEqual(ref))
  }
  
  func test_insert_item() {
    let c = 1000
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }
    
    var rng = RepeatableRandomNumberGenerator(seed: 0)
    let input = ref.shuffled(using: &rng)
    
    var rope = Rope<Chunk>()
    for i in input.indices {
      let chunk = input[i]
      let position = input[..<i].reduce(into: 0) {
        $0 += $1.value < chunk.value ? $1.length : 0
      }
      rope.insert(input[i], at: position, in: Chunk.Metric())
      rope._invariantCheck()
    }
    
    let actualSum = rope.summary
    let expectedSum: Chunk.Summary = ref.reduce(into: .zero) { $0.add($1.summary) }
    XCTAssertEqual(actualSum, expectedSum)
    
    XCTAssertTrue(rope.elementsEqual(ref))
  }
  
  func test_remove_at_index() {
    let c = 1000
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }
    
    var rope = Rope<Chunk>(ref)
    
    var rng = RepeatableRandomNumberGenerator(seed: 0)
    let input = ref.shuffled(using: &rng)
    
    for i in input.indices {
      let chunk = input[i]
      let offset = input[i...].reduce(into: 0) {
        $0 += $1.value < chunk.value ? 1 : 0
      }
      let index = rope.index(rope.startIndex, offsetBy: offset)
      let removed = rope.remove(at: index)
      XCTAssertEqual(removed, chunk)
      rope._invariantCheck()
    }
    XCTAssertTrue(rope.isEmpty)
    XCTAssertEqual(rope.summary, .zero)
  }

  func test_remove_at_inout_index() {
    let c = 1000
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }

    var rope = Rope<Chunk>(ref)

    var rng = RepeatableRandomNumberGenerator(seed: 0)
    let input = ref.shuffled(using: &rng)

    for i in input.indices {
      let chunk = input[i]
      let (offset, position) = input[i...].reduce(into: (0, 0)) {
        guard $1.value < chunk.value else { return }
        $0.0 += 1
        $0.1 += $1.length
      }
      var index = rope.index(rope.startIndex, offsetBy: offset)
      let removed = rope.remove(at: &index)
      XCTAssertEqual(removed, chunk)
      XCTAssertEqual(rope.offset(of: index, in: Chunk.Metric()), position, "\(i)")
      rope._invariantCheck()
    }
    XCTAssertTrue(rope.isEmpty)
    XCTAssertEqual(rope.summary, .zero)
  }

  func test_remove_at_position() {
    let c = 1000
    let ref = (0 ..< c).map {
      Chunk(length: ($0 % 4) + 1, value: $0)
    }
    
    var rope = Rope<Chunk>(ref)
    
    var rng = RepeatableRandomNumberGenerator(seed: 0)
    let input = ref.shuffled(using: &rng)
    
    for i in input.indices {
      let chunk = input[i]
      let position = input[i...].reduce(into: 0) {
        $0 += $1.value < chunk.value ? $1.length : 0
      }
      let r = rope.remove(at: position, in: Chunk.Metric())
      XCTAssertEqual(r.removed, chunk)
      XCTAssertEqual(rope.offset(of: r.next, in: Chunk.Metric()), position, "\(i)")
      rope._invariantCheck()
    }
    XCTAssertTrue(rope.isEmpty)
    XCTAssertEqual(rope.summary, .zero)
  }
  
  func test_join() {
    let c = 100_000
    var trees = (0 ..< c).map {
      let chunk = Chunk(length: ($0 % 4) + 1, value: $0)
      return Rope(CollectionOfOne(chunk))
    }
    var ranges = (0 ..< c).map { $0 ..< $0 + 1 }
    
    var rng = RepeatableRandomNumberGenerator(seed: 0)
    while trees.count >= 2 {
      let i = (0 ..< trees.count - 1).randomElement(using: &rng)!
      let expectedRange = ranges[i].lowerBound ..< ranges[i + 1].upperBound
      
      let a = trees[i]
      let b = trees.remove(at: i + 1)
      trees[i] = Rope()
      
      let joined = Rope.join(a, b)
      joined._invariantCheck()
      let actualValues = joined.map { $0.value }
      XCTAssertEqual(actualValues, Array(expectedRange))
      trees[i] = joined
      ranges.replaceSubrange(i ... i + 1, with: CollectionOfOne(expectedRange))
    }
    XCTAssertEqual(ranges, [0 ..< c])
  }

  func chunkify(_ values: [Int]) -> [Chunk] {
    var result: [Chunk] = []
    var last = Int.min
    var length = 0
    for i in values {
      if length == 0 || i == last {
        length += 1
      } else {
        result.append(Chunk(length: length, value: last))
        length = 1
      }
      last = i
    }
    if length > 0 {
      result.append(Chunk(length: length, value: last))
    }
    return result
  }

  func checkEqual(
    _ x: Rope<Chunk>,
    _ y: [Int],
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let u = Array(x)
    let v = chunkify(y)
    XCTAssertEqual(u, v, file: file, line: line)
  }

  func checkRemoveSubrange(
    _ a: Rope<Chunk>,
    _ b: [Int],
    range: Range<Int>,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    var x = a
    x.removeSubrange(range, in: Chunk.Metric())
    var y = b
    y.removeSubrange(range)

    checkEqual(x, y, file: file, line: line)
  }

  func test_removeSubrange_simple() {
    var rope = Rope<Chunk>()
    for i in 0 ..< 10 {
      rope.append(Chunk(length: 10, value: i))
    }
    let ref = (0 ..< 10).flatMap { Array(repeating: $0, count: 10) }

    // Basics
    checkRemoveSubrange(rope, ref, range: 0 ..< 0)
    checkRemoveSubrange(rope, ref, range: 30 ..< 30)
    checkRemoveSubrange(rope, ref, range: 0 ..< 100)

    // Whole individual chunks
    checkRemoveSubrange(rope, ref, range: 90 ..< 100)
    checkRemoveSubrange(rope, ref, range: 0 ..< 10)
    checkRemoveSubrange(rope, ref, range: 30 ..< 40)
    checkRemoveSubrange(rope, ref, range: 70 ..< 80)

    // Prefixes of single chunks
    checkRemoveSubrange(rope, ref, range: 0 ..< 1)
    checkRemoveSubrange(rope, ref, range: 30 ..< 35)
    checkRemoveSubrange(rope, ref, range: 60 ..< 66)
    checkRemoveSubrange(rope, ref, range: 90 ..< 98)

    // Suffixes of single chunks
    checkRemoveSubrange(rope, ref, range: 9 ..< 10)
    checkRemoveSubrange(rope, ref, range: 35 ..< 40)
    checkRemoveSubrange(rope, ref, range: 64 ..< 70)
    checkRemoveSubrange(rope, ref, range: 98 ..< 100)

    // Neighboring couple of whole chunks
    checkRemoveSubrange(rope, ref, range: 0 ..< 20)
    checkRemoveSubrange(rope, ref, range: 80 ..< 100)
    checkRemoveSubrange(rope, ref, range: 10 ..< 30)
    checkRemoveSubrange(rope, ref, range: 50 ..< 70) // Crosses nodes!

    // Longer whole chunk sequences
    checkRemoveSubrange(rope, ref, range: 0 ..< 30)
    checkRemoveSubrange(rope, ref, range: 70 ..< 90)
    checkRemoveSubrange(rope, ref, range: 0 ..< 60) // entire first node
    checkRemoveSubrange(rope, ref, range: 60 ..< 100) // entire second node
    checkRemoveSubrange(rope, ref, range: 40 ..< 70) // crosses into second node
    checkRemoveSubrange(rope, ref, range: 10 ..< 90) // crosses into second node

    // Arbitrary cuts
    checkRemoveSubrange(rope, ref, range: 0 ..< 69)
    checkRemoveSubrange(rope, ref, range: 42 ..< 73)
    checkRemoveSubrange(rope, ref, range: 21 ..< 89)
    checkRemoveSubrange(rope, ref, range: 1 ..< 99)
    checkRemoveSubrange(rope, ref, range: 1 ..< 59)
    checkRemoveSubrange(rope, ref, range: 61 ..< 99)

  }

  func test_removeSubrange_larger() {
    var rope = Rope<Chunk>()
    for i in 0 ..< 100 {
      rope.append(Chunk(length: 10, value: i))
    }
    let ref = (0 ..< 100).flatMap { Array(repeating: $0, count: 10) }

    checkRemoveSubrange(rope, ref, range: 0 ..< 0)
    checkRemoveSubrange(rope, ref, range: 0 ..< 1000)
    checkRemoveSubrange(rope, ref, range: 0 ..< 100)
    checkRemoveSubrange(rope, ref, range: 900 ..< 1000)
    checkRemoveSubrange(rope, ref, range: 120 ..< 330)
    checkRemoveSubrange(rope, ref, range: 734 ..< 894)
    checkRemoveSubrange(rope, ref, range: 183 ..< 892)

    checkRemoveSubrange(rope, ref, range: 181 ..< 479)
    checkRemoveSubrange(rope, ref, range: 191 ..< 469)
    checkRemoveSubrange(rope, ref, range: 2 ..< 722)
    checkRemoveSubrange(rope, ref, range: 358 ..< 718)
    checkRemoveSubrange(rope, ref, range: 12 ..< 732)
    checkRemoveSubrange(rope, ref, range: 348 ..< 728)
    checkRemoveSubrange(rope, ref, range: 63 ..< 783)
    checkRemoveSubrange(rope, ref, range: 297 ..< 655)
  }

  func test_removeSubrange_random() {
    for iteration in 0 ..< 20 {
      var rng = RepeatableRandomNumberGenerator(seed: iteration)
      let c = 1000
      var rope = Rope<Chunk>()
      for i in 0 ..< c {
        rope.append(Chunk(length: 2, value: i))
      }
      var ref = (0 ..< c).flatMap { Array(repeating: $0, count: 2) }

      while !ref.isEmpty {
        print(ref.count)
        let i = (0 ..< ref.count).randomElement(using: &rng)!
        let j = (i + 1 ... ref.count).randomElement(using: &rng)!
        rope.removeSubrange(i ..< j, in: Chunk.Metric())
        ref.removeSubrange(i ..< j)
        checkEqual(rope, ref)
      }
    }
  }

}
