
// Appended to the production inspector by tools/test-macos.sh, so this tests
// the actual private helpers. No QQ objects, accounts or sending are involved.
#if QQP_CONTEXT_TEST
private protocol QQPFixtureProtocol: AnyObject {}
private final class QQPFixtureContext: NSObject, QQPFixtureProtocol {}
private class QQPFixtureBase: NSObject {
    let chatContext: QQPFixtureContext?
    init(_ value: QQPFixtureContext?) { chatContext = value; super.init() }
}
private final class QQPFixtureChild: QQPFixtureBase { let unrelated = 7 }
private final class QQPFixtureWeak: NSObject {
    weak var context: QQPFixtureContext?
}
private final class QQPFixtureProtocolWeak: NSObject {
    weak var context: (any QQPFixtureProtocol)?
}
private final class QQPFixtureUnowned: NSObject {
    unowned var context: QQPFixtureContext?
    init(_ value: QQPFixtureContext) { context = value; super.init() }
}
private final class QQPFixtureUnsafe: NSObject {
    unowned(unsafe) var context: QQPFixtureContext?
    init(_ value: QQPFixtureContext) { context = value; super.init() }
}
private final class QQPFixtureAdjacent: NSObject {
    let chatContext: QQPFixtureContext
    unowned let unrelated: QQPFixtureContext
    init(_ value: QQPFixtureContext, _ other: QQPFixtureContext) {
        chatContext = value; unrelated = other; super.init()
    }
}
private final class QQPFixtureCustom: QQPFixtureBase, CustomReflectable {
    static var calls = 0
    var customMirror: Mirror { Self.calls += 1; return Mirror(self, children: [:]) }
}
private func qqpRunContextFixture() {
    precondition(Thread.isMainThread)
    let first = QQPFixtureContext(), second = QQPFixtureContext()
    let child = QQPFixtureChild(first)
    precondition(qqpField(child, declaringClass: QQPFixtureBase.self, name: "chatContext") === first)
    precondition(qqpField(child, declaringClass: QQPFixtureChild.self, name: "chatContext") == nil)
    precondition(qqpField(QQPFixtureBase(nil), declaringClass: QQPFixtureBase.self, name: "chatContext") == nil)
    let custom = QQPFixtureCustom(first)
    precondition(qqpField(custom, declaringClass: QQPFixtureBase.self, name: "chatContext") === first)
    precondition(QQPFixtureCustom.calls == 0)
    let weakOwner = QQPFixtureWeak()
    weakOwner.context = first
    precondition(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) === first)
    precondition(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context") == nil)
    weakOwner.context = second
    precondition(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) === second)
    weakOwner.context = nil
    precondition(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) == nil)
    autoreleasepool { weakOwner.context = QQPFixtureContext() }
    precondition(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) == nil)
    let protocolOwner = QQPFixtureProtocolWeak()
    protocolOwner.context = first
    precondition(qqpField(protocolOwner, declaringClass: QQPFixtureProtocolWeak.self, name: "context", ownership: .verifiedWeak) === first)
    let unowned = QQPFixtureUnowned(first), unsafe = QQPFixtureUnsafe(first)
    precondition(qqpField(unowned, declaringClass: QQPFixtureUnowned.self, name: "context", ownership: .verifiedWeak) == nil)
    precondition(qqpField(unsafe, declaringClass: QQPFixtureUnsafe.self, name: "context", ownership: .verifiedWeak) == nil)
    var adjacent: QQPFixtureAdjacent!
    autoreleasepool { adjacent = QQPFixtureAdjacent(first, QQPFixtureContext()) }
    precondition(qqpField(adjacent, declaringClass: QQPFixtureAdjacent.self, name: "chatContext") === first)
    print("{\"passed\":true,\"scope\":\"production Swift strong/weak reader on Apple fixture objects; no QQ runtime\"}")
}
qqpRunContextFixture()
#endif
