import Foundation

final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var dict: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: Key) -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard let node = dict[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    func set(_ key: Key, _ value: Value) {
        lock.lock(); defer { lock.unlock() }
        if let node = dict[key] {
            node.value = value
            moveToHead(node)
        } else {
            let node = Node(key: key, value: value)
            dict[key] = node
            addToHead(node)
            if dict.count > capacity, let t = tail {
                remove(t)
                dict.removeValue(forKey: t.key)
            }
        }
    }

    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        if node === tail { tail = node.prev }
        node.prev?.next = node.next
        node.next?.prev = node.prev
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
    }

    private func remove(_ node: Node) {
        if node === head { head = node.next }
        if node === tail { tail = node.prev }
        node.prev?.next = node.next
        node.next?.prev = node.prev
        node.prev = nil
        node.next = nil
    }

    private class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?
        init(key: Key, value: Value) { self.key = key; self.value = value }
    }
}

