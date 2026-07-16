import Foundation

/// Runs `tasks` concurrently on the global pool and returns their results in the original order.
/// Used to fan out independent, blocking `gh`/`git` subprocess calls (which have no async API)
/// so a batch finishes in roughly the time of its slowest member instead of their sum.
func runConcurrently<T>(_ tasks: [() -> T]) -> [T] {
    guard !tasks.isEmpty else { return [] }
    guard tasks.count > 1 else { return [tasks[0]()] }

    let results = UnsafeMutablePointer<T?>.allocate(capacity: tasks.count)
    results.initialize(repeating: nil, count: tasks.count)
    defer {
        results.deinitialize(count: tasks.count)
        results.deallocate()
    }

    DispatchQueue.concurrentPerform(iterations: tasks.count) { i in
        results[i] = tasks[i]()
    }

    return (0..<tasks.count).map { results[$0]! }
}
