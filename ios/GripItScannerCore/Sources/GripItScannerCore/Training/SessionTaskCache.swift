import Foundation

/// Owned by a single hand session. The studio uses only its four pitch keys.
public actor SessionTaskCache<Key: Hashable & Sendable, Value: Sendable> {
  private struct Entry { let token: UUID; let task: Task<Value, Error> }
  private var entries: [Key: Entry] = [:]
  public init() {}

  public func value(for key: Key, load: @escaping @Sendable () async throws -> Value) async throws -> Value {
    let entry: Entry
    if let existing = entries[key] {
      entry = existing
    } else {
      entry = Entry(token: UUID(), task: Task.detached(priority: .userInitiated, operation: load))
      entries[key] = entry
    }
    do {
      return try await entry.task.value
    } catch {
      if entries[key]?.token == entry.token { entries[key] = nil }
      throw error
    }
  }
}
