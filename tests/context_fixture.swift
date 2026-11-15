
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
private func qqpCheck(_ condition: @autoclosure () -> Bool, line: UInt = #line) {
    // Write before evaluation: even a runtime trap must leave the precise case.
    FileHandle.standardError.write(Data("QQP fixture checking line \(line)\n".utf8))
    guard condition() else {
        FileHandle.standardError.write(Data("QQP fixture FAILED line \(line)\n".utf8))
        exit(1)
    }
}
private func qqpRunContextFixture() {
    qqpCheck(Thread.isMainThread)
    let first = QQPFixtureContext(), second = QQPFixtureContext()
    let child = QQPFixtureChild(first)
    qqpCheck(qqpField(child, declaringClass: QQPFixtureBase.self, name: "chatContext") === first)
    qqpCheck(qqpField(child, declaringClass: QQPFixtureChild.self, name: "chatContext") == nil)
    qqpCheck(qqpField(QQPFixtureBase(nil), declaringClass: QQPFixtureBase.self, name: "chatContext") == nil)
    let custom = QQPFixtureCustom(first)
    qqpCheck(qqpField(custom, declaringClass: QQPFixtureBase.self, name: "chatContext") === first)
    qqpCheck(QQPFixtureCustom.calls == 0)
    let weakOwner = QQPFixtureWeak()
    weakOwner.context = first
    qqpCheck(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) === first)
    qqpCheck(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context") == nil)
    weakOwner.context = second
    qqpCheck(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) === second)
    weakOwner.context = nil
    qqpCheck(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) == nil)
    autoreleasepool {
        let temporary = QQPFixtureContext()
        weakOwner.context = temporary
        withExtendedLifetime(temporary) {
            qqpCheck(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) === temporary)
        }
    }
    qqpCheck(qqpField(weakOwner, declaringClass: QQPFixtureWeak.self, name: "context", ownership: .verifiedWeak) == nil)
    let protocolOwner = QQPFixtureProtocolWeak()
    protocolOwner.context = first
    qqpCheck(qqpField(protocolOwner, declaringClass: QQPFixtureProtocolWeak.self, name: "context", ownership: .verifiedWeak) === first)
    let unowned = QQPFixtureUnowned(first), unsafe = QQPFixtureUnsafe(first)
    qqpCheck(qqpField(unowned, declaringClass: QQPFixtureUnowned.self, name: "context", ownership: .verifiedWeak) == nil)
    qqpCheck(qqpField(unsafe, declaringClass: QQPFixtureUnsafe.self, name: "context", ownership: .verifiedWeak) == nil)
    var adjacent: QQPFixtureAdjacent!
    autoreleasepool { adjacent = QQPFixtureAdjacent(first, QQPFixtureContext()) }
    qqpCheck(qqpField(adjacent, declaringClass: QQPFixtureAdjacent.self, name: "chatContext") === first)
    print("{\"passed\":true,\"scope\":\"production Swift strong/weak reader on Apple fixture objects; no QQ runtime\"}")
}
qqpRunContextFixture()
#endif
