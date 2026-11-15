import Foundation
import ObjectiveC.runtime

private typealias QQPNameFree = @convention(c) (UnsafePointer<CChar>?) -> Void
@_silgen_name("swift_reflectionMirror_recursiveCount")
private func qqpCount(_ type: Any.Type) -> Int
@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
private func qqpMetadata(_ type: Any.Type, index: Int,
                         fieldMetadata: UnsafeMutablePointer<QQPFieldMetadata>) -> Any.Type
@_silgen_name("swift_reflectionMirror_subscript")
private func qqpChild<T>(of value: T, type: Any.Type, index: Int,
                         outName: UnsafeMutablePointer<UnsafePointer<CChar>?>,
                         outFreeFunc: UnsafeMutablePointer<QQPNameFree?>) -> Any

@_silgen_name("swift_getTypeContextDescriptor")
private func qqpTypeDescriptor(_ type: Any.Type) -> UnsafeRawPointer?

// Optional is opened by its own compiled implementation, never by Mirror.
private protocol QQPOptionalObject {
    static var objectClass: AnyClass? { get }
    var object: NSObject? { get }
}
extension Optional: QQPOptionalObject {
    static var objectClass: AnyClass? { Wrapped.self as? AnyClass }
    var object: NSObject? {
        switch self {
        case .some(let value): return value as? NSObject
        case .none: return nil
        }
    }
}
private func qqpObjectClass(_ type: Any.Type) -> AnyClass? {
    if let cls = type as? AnyClass { return cls }
    return (type as? QQPOptionalObject.Type)?.objectClass
}
private func qqpIsSubclass(_ cls: AnyClass, of expected: AnyClass) -> Bool {
    var current: AnyClass? = cls
    while let value = current {
        if value === expected { return true }
        current = class_getSuperclass(value)
    }
    return false
}

// Metadata inspection receives no instance. The ownership decoder checks the
// exact field type mangling before runtime is allowed to load weak storage.
// ObjC W alone is insufficient: Swift uses it for unowned properties as well.
private enum QQPFieldOwnership { case strong, verifiedWeak }
private func qqpField(_ object: NSObject, declaringClass: AnyClass,
                      name wanted: String,
                      ownership: QQPFieldOwnership = .strong) -> NSObject? {
    guard Thread.isMainThread, object.isKind(of: declaringClass),
          MemoryLayout<QQPFieldMetadata>.size == 24,
          MemoryLayout<QQPFieldMetadata>.alignment == 8 else { return nil }
    let total = qqpCount(declaringClass)
    let inherited = class_getSuperclass(declaringClass).map { qqpCount($0) } ?? 0
    guard inherited >= 0, total >= inherited, total <= 4096 else { return nil }
    var match: (Int, Any.Type)?
    for index in inherited..<total {
        var metadata = QQPFieldMetadata()
        let type = qqpMetadata(declaringClass, index: index, fieldMetadata: &metadata)
        let label = metadata.name.flatMap { String(validatingUTF8: $0) }
        metadata.freeFunc?(metadata.name)
        guard label == wanted else { continue }
        guard match == nil else { return nil }
        switch ownership {
        case .strong:
            guard metadata.isStrong else { return nil }
        case .verifiedWeak:
            guard !metadata.isStrong, metadata.isVar,
                  type is QQPOptionalObject.Type else { return nil }
            guard let descriptor = qqpTypeDescriptor(declaringClass) else { return nil }
            guard wanted.withCString({
                QQPSwiftFieldIsWeak(descriptor, $0, UInt32(index - inherited),
                                    UInt32(total - inherited))
            }) else { return nil }
        }
        if ownership == .strong {
            guard let cls = qqpObjectClass(type), qqpIsSubclass(cls, of: NSObject.self)
            else { return nil }
        }
        // The weak decoder also admits class-bound protocol existentials.
        // Their Optional.Wrapped is not an AnyClass, but the exact weak
        // mangling proves reference storage before any instance value is read.
        match = (index - inherited, type)
    }
    guard let selected = match else { return nil }
    // Swift's ObjC-heritage ClassImpl.childOffset indexes class_copyIvarList.
    // Refuse an absent/reordered slot before asking the runtime to load it.
    var ivarCount: UInt32 = 0
    guard let ivars = class_copyIvarList(declaringClass, &ivarCount) else { return nil }
    defer { free(UnsafeMutableRawPointer(ivars)) }
    guard selected.0 >= 0, selected.0 < Int(ivarCount),
          ivarCount == UInt32(total - inherited),
          let ivarName = ivar_getName(ivars[selected.0]),
          String(cString: ivarName) == wanted,
          ivar_getOffset(ivars[selected.0]) >= 0,
          UInt(ivar_getOffset(ivars[selected.0])) < UInt(class_getInstanceSize(declaringClass))
    else { return nil }
    var name: UnsafePointer<CChar>?
    var fieldNameFree: QQPNameFree?
    let value: Any = withExtendedLifetime(object) {
        qqpChild(of: object, type: declaringClass, index: selected.0,
                 outName: &name, outFreeFunc: &fieldNameFree)
    }
    defer { fieldNameFree?(name) }
    guard name.map({ String(cString: $0) }) == wanted else { return nil }
    let result: NSObject?
    if let optional = value as? QQPOptionalObject { result = optional.object }
    else { result = value as? NSObject }
    guard let actual = result else { return nil }
    if let expected = qqpObjectClass(selected.1) {
        guard actual.isKind(of: expected) else { return nil }
    } else if ownership != .verifiedWeak { return nil }
    return actual
}

@objc(QQPContextInspector)
final class QQPContextInspector: NSObject {
    @objc static func ownerForPicker(_ picker: NSObject) -> NSObject? {
        guard Thread.isMainThread,
              let cls = NSClassFromString("NTAIOPhotoMediaPickerController"),
              picker.isKind(of: cls) else { return nil }
        return qqpField(picker, declaringClass: cls, name: "context",
                        ownership: .verifiedWeak)
    }
    @objc static func contextForOwner(_ owner: NSObject) -> NSObject? {
        guard Thread.isMainThread,
              let contextClass = NSClassFromString("AIOChatParameter.AIOChatContext")
        else { return nil }
        if owner.isKind(of: contextClass) { return owner }
        guard let base = NSClassFromString("NTBaseAIO.NTAIOChatBaseViewController"),
              owner.isKind(of: base),
              let value = qqpField(owner, declaringClass: base, name: "chatContext"),
              value.isKind(of: contextClass) else { return nil }
        return value
    }
}
