// Generated using the ObjectBox Swift Generator — https://objectbox.io
// DO NOT EDIT

// swiftlint:disable all
import ObjectBox
import Foundation

// MARK: - Entity metadata

extension AuditEntity: ObjectBox.Entity {}
extension FileEntity: ObjectBox.Entity {}
extension MemoryEntity: ObjectBox.Entity {}
extension SessionEntity: ObjectBox.Entity {}
extension TranscriptEntity: ObjectBox.Entity {}

extension AuditEntity: ObjectBox.__EntityRelatable {
    internal typealias EntityType = AuditEntity

    internal var _id: EntityId<AuditEntity> {
        return EntityId<AuditEntity>(self.id.value)
    }
}

extension AuditEntity: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = AuditEntityBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "AuditEntity", id: 1)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: AuditEntity.self, id: 1, uid: 3119378434988257536)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 9041789108828225024)
        try entityBuilder.addProperty(name: "sessionId", type: PropertyType.string, id: 2, uid: 1112545179719011840)
        try entityBuilder.addProperty(name: "action", type: PropertyType.string, id: 3, uid: 1465216564729540096)
        try entityBuilder.addProperty(name: "details", type: PropertyType.string, id: 4, uid: 249686791076345344)
        try entityBuilder.addProperty(name: "timestamp", type: PropertyType.date, id: 5, uid: 5742346292094710528)
        try entityBuilder.addProperty(name: "userId", type: PropertyType.string, id: 6, uid: 5760369612458244864)
        try entityBuilder.addProperty(name: "metadataJson", type: PropertyType.string, id: 7, uid: 1675046100229534208)

        try entityBuilder.lastProperty(id: 7, uid: 1675046100229534208)
    }
}

extension AuditEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { AuditEntity.id == myId }
    internal static var id: Property<AuditEntity, Id, Id> { return Property<AuditEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { AuditEntity.sessionId.startsWith("X") }
    internal static var sessionId: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { AuditEntity.action.startsWith("X") }
    internal static var action: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { AuditEntity.details.startsWith("X") }
    internal static var details: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { AuditEntity.timestamp > 1234 }
    internal static var timestamp: Property<AuditEntity, Date, Void> { return Property<AuditEntity, Date, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { AuditEntity.userId.startsWith("X") }
    internal static var userId: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { AuditEntity.metadataJson.startsWith("X") }
    internal static var metadataJson: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 7, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == AuditEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<AuditEntity, Id, Id> { return Property<AuditEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .sessionId.startsWith("X") }

    internal static var sessionId: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .action.startsWith("X") }

    internal static var action: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .details.startsWith("X") }

    internal static var details: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .timestamp > 1234 }

    internal static var timestamp: Property<AuditEntity, Date, Void> { return Property<AuditEntity, Date, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .userId.startsWith("X") }

    internal static var userId: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .metadataJson.startsWith("X") }

    internal static var metadataJson: Property<AuditEntity, String, Void> { return Property<AuditEntity, String, Void>(propertyId: 7, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `AuditEntity.EntityBindingType`.
internal final class AuditEntityBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = AuditEntity
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_sessionId = propertyCollector.prepare(string: entity.sessionId)
        let propertyOffset_action = propertyCollector.prepare(string: entity.action)
        let propertyOffset_details = propertyCollector.prepare(string: entity.details)
        let propertyOffset_userId = propertyCollector.prepare(string: entity.userId)
        let propertyOffset_metadataJson = propertyCollector.prepare(string: entity.metadataJson)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.timestamp, at: 2 + 2 * 5)
        propertyCollector.collect(dataOffset: propertyOffset_sessionId, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_action, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_details, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_userId, at: 2 + 2 * 6)
        propertyCollector.collect(dataOffset: propertyOffset_metadataJson, at: 2 + 2 * 7)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = AuditEntity()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.sessionId = entityReader.read(at: 2 + 2 * 2)
        entity.action = entityReader.read(at: 2 + 2 * 3)
        entity.details = entityReader.read(at: 2 + 2 * 4)
        entity.timestamp = entityReader.read(at: 2 + 2 * 5)
        entity.userId = entityReader.read(at: 2 + 2 * 6)
        entity.metadataJson = entityReader.read(at: 2 + 2 * 7)

        return entity
    }
}



extension FileEntity: ObjectBox.__EntityRelatable {
    internal typealias EntityType = FileEntity

    internal var _id: EntityId<FileEntity> {
        return EntityId<FileEntity>(self.id.value)
    }
}

extension FileEntity: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = FileEntityBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "FileEntity", id: 2)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: FileEntity.self, id: 2, uid: 639004552926595584)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 1037976401444389120)
        try entityBuilder.addProperty(name: "sessionId", type: PropertyType.string, id: 2, uid: 7925399470178910720)
        try entityBuilder.addProperty(name: "fileName", type: PropertyType.string, id: 3, uid: 81006185723989504)
        try entityBuilder.addProperty(name: "mimeType", type: PropertyType.string, id: 4, uid: 6095804569922039808)
        try entityBuilder.addProperty(name: "encryptedData", type: PropertyType.byteVector, id: 5, uid: 5272962629824747776)
        try entityBuilder.addProperty(name: "fileSize", type: PropertyType.long, id: 6, uid: 5782473101885932032)
        try entityBuilder.addProperty(name: "uploadTimestamp", type: PropertyType.date, id: 7, uid: 2515912062795982336)
        try entityBuilder.addProperty(name: "expiryTimestamp", type: PropertyType.date, id: 8, uid: 5576593747661471488)
        try entityBuilder.addProperty(name: "isExpired", type: PropertyType.bool, id: 9, uid: 503662559533127168)
        try entityBuilder.addProperty(name: "metadataJson", type: PropertyType.string, id: 10, uid: 796672730650135040)

        try entityBuilder.lastProperty(id: 10, uid: 796672730650135040)
    }
}

extension FileEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.id == myId }
    internal static var id: Property<FileEntity, Id, Id> { return Property<FileEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.sessionId.startsWith("X") }
    internal static var sessionId: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.fileName.startsWith("X") }
    internal static var fileName: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.mimeType.startsWith("X") }
    internal static var mimeType: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.encryptedData > 1234 }
    internal static var encryptedData: Property<FileEntity, Data, Void> { return Property<FileEntity, Data, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.fileSize > 1234 }
    internal static var fileSize: Property<FileEntity, Int64, Void> { return Property<FileEntity, Int64, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.uploadTimestamp > 1234 }
    internal static var uploadTimestamp: Property<FileEntity, Date, Void> { return Property<FileEntity, Date, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.expiryTimestamp > 1234 }
    internal static var expiryTimestamp: Property<FileEntity, Date, Void> { return Property<FileEntity, Date, Void>(propertyId: 8, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.isExpired == true }
    internal static var isExpired: Property<FileEntity, Bool, Void> { return Property<FileEntity, Bool, Void>(propertyId: 9, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { FileEntity.metadataJson.startsWith("X") }
    internal static var metadataJson: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 10, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == FileEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<FileEntity, Id, Id> { return Property<FileEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .sessionId.startsWith("X") }

    internal static var sessionId: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .fileName.startsWith("X") }

    internal static var fileName: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .mimeType.startsWith("X") }

    internal static var mimeType: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .encryptedData > 1234 }

    internal static var encryptedData: Property<FileEntity, Data, Void> { return Property<FileEntity, Data, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .fileSize > 1234 }

    internal static var fileSize: Property<FileEntity, Int64, Void> { return Property<FileEntity, Int64, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .uploadTimestamp > 1234 }

    internal static var uploadTimestamp: Property<FileEntity, Date, Void> { return Property<FileEntity, Date, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .expiryTimestamp > 1234 }

    internal static var expiryTimestamp: Property<FileEntity, Date, Void> { return Property<FileEntity, Date, Void>(propertyId: 8, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .isExpired == true }

    internal static var isExpired: Property<FileEntity, Bool, Void> { return Property<FileEntity, Bool, Void>(propertyId: 9, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .metadataJson.startsWith("X") }

    internal static var metadataJson: Property<FileEntity, String, Void> { return Property<FileEntity, String, Void>(propertyId: 10, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `FileEntity.EntityBindingType`.
internal final class FileEntityBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = FileEntity
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_sessionId = propertyCollector.prepare(string: entity.sessionId)
        let propertyOffset_fileName = propertyCollector.prepare(string: entity.fileName)
        let propertyOffset_mimeType = propertyCollector.prepare(string: entity.mimeType)
        let propertyOffset_encryptedData = propertyCollector.prepare(bytes: entity.encryptedData)
        let propertyOffset_metadataJson = propertyCollector.prepare(string: entity.metadataJson)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.fileSize, at: 2 + 2 * 6)
        propertyCollector.collect(entity.uploadTimestamp, at: 2 + 2 * 7)
        propertyCollector.collect(entity.expiryTimestamp, at: 2 + 2 * 8)
        propertyCollector.collect(entity.isExpired, at: 2 + 2 * 9)
        propertyCollector.collect(dataOffset: propertyOffset_sessionId, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_fileName, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_mimeType, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_encryptedData, at: 2 + 2 * 5)
        propertyCollector.collect(dataOffset: propertyOffset_metadataJson, at: 2 + 2 * 10)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = FileEntity()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.sessionId = entityReader.read(at: 2 + 2 * 2)
        entity.fileName = entityReader.read(at: 2 + 2 * 3)
        entity.mimeType = entityReader.read(at: 2 + 2 * 4)
        entity.encryptedData = entityReader.read(at: 2 + 2 * 5)
        entity.fileSize = entityReader.read(at: 2 + 2 * 6)
        entity.uploadTimestamp = entityReader.read(at: 2 + 2 * 7)
        entity.expiryTimestamp = entityReader.read(at: 2 + 2 * 8)
        entity.isExpired = entityReader.read(at: 2 + 2 * 9)
        entity.metadataJson = entityReader.read(at: 2 + 2 * 10)

        return entity
    }
}



extension MemoryEntity: ObjectBox.__EntityRelatable {
    internal typealias EntityType = MemoryEntity

    internal var _id: EntityId<MemoryEntity> {
        return EntityId<MemoryEntity>(self.id.value)
    }
}

extension MemoryEntity: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = MemoryEntityBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "MemoryEntity", id: 3)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: MemoryEntity.self, id: 3, uid: 5565179918131756544)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 4007722685109029120)
        try entityBuilder.addProperty(name: "sessionId", type: PropertyType.string, id: 2, uid: 4908410745287957760)
        try entityBuilder.addProperty(name: "encryptedText", type: PropertyType.string, id: 3, uid: 489889480656986368)
        try entityBuilder.addProperty(name: "embedding", type: PropertyType.floatVector, id: 4, uid: 5233342139816764416)
        try entityBuilder.addProperty(name: "timestamp", type: PropertyType.date, id: 5, uid: 2928854816243008256)
        try entityBuilder.addProperty(name: "metadataJson", type: PropertyType.string, id: 6, uid: 9151875808831475200)
        try entityBuilder.addProperty(name: "importance", type: PropertyType.float, id: 7, uid: 9026988489735336192)

        try entityBuilder.lastProperty(id: 7, uid: 9026988489735336192)
    }
}

extension MemoryEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MemoryEntity.id == myId }
    internal static var id: Property<MemoryEntity, Id, Id> { return Property<MemoryEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MemoryEntity.sessionId.startsWith("X") }
    internal static var sessionId: Property<MemoryEntity, String, Void> { return Property<MemoryEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MemoryEntity.encryptedText.startsWith("X") }
    internal static var encryptedText: Property<MemoryEntity, String, Void> { return Property<MemoryEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MemoryEntity.embedding.isNotNil() }
    internal static var embedding: Property<MemoryEntity, FloatArrayPropertyType, Void> { return Property<MemoryEntity, FloatArrayPropertyType, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MemoryEntity.timestamp > 1234 }
    internal static var timestamp: Property<MemoryEntity, Date, Void> { return Property<MemoryEntity, Date, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MemoryEntity.metadataJson.startsWith("X") }
    internal static var metadataJson: Property<MemoryEntity, String, Void> { return Property<MemoryEntity, String, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { MemoryEntity.importance > 1234 }
    internal static var importance: Property<MemoryEntity, Float, Void> { return Property<MemoryEntity, Float, Void>(propertyId: 7, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == MemoryEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<MemoryEntity, Id, Id> { return Property<MemoryEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .sessionId.startsWith("X") }

    internal static var sessionId: Property<MemoryEntity, String, Void> { return Property<MemoryEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .encryptedText.startsWith("X") }

    internal static var encryptedText: Property<MemoryEntity, String, Void> { return Property<MemoryEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .embedding.isNotNil() }

    internal static var embedding: Property<MemoryEntity, FloatArrayPropertyType, Void> { return Property<MemoryEntity, FloatArrayPropertyType, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .timestamp > 1234 }

    internal static var timestamp: Property<MemoryEntity, Date, Void> { return Property<MemoryEntity, Date, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .metadataJson.startsWith("X") }

    internal static var metadataJson: Property<MemoryEntity, String, Void> { return Property<MemoryEntity, String, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .importance > 1234 }

    internal static var importance: Property<MemoryEntity, Float, Void> { return Property<MemoryEntity, Float, Void>(propertyId: 7, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `MemoryEntity.EntityBindingType`.
internal final class MemoryEntityBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = MemoryEntity
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_sessionId = propertyCollector.prepare(string: entity.sessionId)
        let propertyOffset_encryptedText = propertyCollector.prepare(string: entity.encryptedText)
        let propertyOffset_embedding = propertyCollector.prepare(values: entity.embedding)
        let propertyOffset_metadataJson = propertyCollector.prepare(string: entity.metadataJson)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.timestamp, at: 2 + 2 * 5)
        propertyCollector.collect(entity.importance, at: 2 + 2 * 7)
        propertyCollector.collect(dataOffset: propertyOffset_sessionId, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_encryptedText, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_embedding, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_metadataJson, at: 2 + 2 * 6)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = MemoryEntity()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.sessionId = entityReader.read(at: 2 + 2 * 2)
        entity.encryptedText = entityReader.read(at: 2 + 2 * 3)
        entity.embedding = entityReader.read(at: 2 + 2 * 4)
        entity.timestamp = entityReader.read(at: 2 + 2 * 5)
        entity.metadataJson = entityReader.read(at: 2 + 2 * 6)
        entity.importance = entityReader.read(at: 2 + 2 * 7)

        return entity
    }
}



extension SessionEntity: ObjectBox.__EntityRelatable {
    internal typealias EntityType = SessionEntity

    internal var _id: EntityId<SessionEntity> {
        return EntityId<SessionEntity>(self.id.value)
    }
}

extension SessionEntity: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = SessionEntityBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "SessionEntity", id: 4)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: SessionEntity.self, id: 4, uid: 4212191750095144192)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 7781418489565113600)
        try entityBuilder.addProperty(name: "sessionId", type: PropertyType.string, id: 2, uid: 7902208929269221632)
        try entityBuilder.addProperty(name: "mode", type: PropertyType.string, id: 3, uid: 6979558402522733824)
        try entityBuilder.addProperty(name: "startTime", type: PropertyType.date, id: 4, uid: 1396401923118351872)
        try entityBuilder.addProperty(name: "endTime", type: PropertyType.date, id: 5, uid: 2007412192269666304)
        try entityBuilder.addProperty(name: "isActive", type: PropertyType.bool, id: 6, uid: 206446856905759488)
        try entityBuilder.addProperty(name: "metadataJson", type: PropertyType.string, id: 7, uid: 5851405349870049536)
        try entityBuilder.addProperty(name: "encryptionKey", type: PropertyType.string, id: 8, uid: 3191032832508991232)

        try entityBuilder.lastProperty(id: 8, uid: 3191032832508991232)
    }
}

extension SessionEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.id == myId }
    internal static var id: Property<SessionEntity, Id, Id> { return Property<SessionEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.sessionId.startsWith("X") }
    internal static var sessionId: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.mode.startsWith("X") }
    internal static var mode: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.startTime > 1234 }
    internal static var startTime: Property<SessionEntity, Date, Void> { return Property<SessionEntity, Date, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.endTime > 1234 }
    internal static var endTime: Property<SessionEntity, Date?, Void> { return Property<SessionEntity, Date?, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.isActive == true }
    internal static var isActive: Property<SessionEntity, Bool, Void> { return Property<SessionEntity, Bool, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.metadataJson.startsWith("X") }
    internal static var metadataJson: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { SessionEntity.encryptionKey.startsWith("X") }
    internal static var encryptionKey: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 8, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == SessionEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<SessionEntity, Id, Id> { return Property<SessionEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .sessionId.startsWith("X") }

    internal static var sessionId: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .mode.startsWith("X") }

    internal static var mode: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .startTime > 1234 }

    internal static var startTime: Property<SessionEntity, Date, Void> { return Property<SessionEntity, Date, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .endTime > 1234 }

    internal static var endTime: Property<SessionEntity, Date?, Void> { return Property<SessionEntity, Date?, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .isActive == true }

    internal static var isActive: Property<SessionEntity, Bool, Void> { return Property<SessionEntity, Bool, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .metadataJson.startsWith("X") }

    internal static var metadataJson: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .encryptionKey.startsWith("X") }

    internal static var encryptionKey: Property<SessionEntity, String, Void> { return Property<SessionEntity, String, Void>(propertyId: 8, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `SessionEntity.EntityBindingType`.
internal final class SessionEntityBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = SessionEntity
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_sessionId = propertyCollector.prepare(string: entity.sessionId)
        let propertyOffset_mode = propertyCollector.prepare(string: entity.mode)
        let propertyOffset_metadataJson = propertyCollector.prepare(string: entity.metadataJson)
        let propertyOffset_encryptionKey = propertyCollector.prepare(string: entity.encryptionKey)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.startTime, at: 2 + 2 * 4)
        propertyCollector.collect(entity.endTime, at: 2 + 2 * 5)
        propertyCollector.collect(entity.isActive, at: 2 + 2 * 6)
        propertyCollector.collect(dataOffset: propertyOffset_sessionId, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_mode, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_metadataJson, at: 2 + 2 * 7)
        propertyCollector.collect(dataOffset: propertyOffset_encryptionKey, at: 2 + 2 * 8)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = SessionEntity()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.sessionId = entityReader.read(at: 2 + 2 * 2)
        entity.mode = entityReader.read(at: 2 + 2 * 3)
        entity.startTime = entityReader.read(at: 2 + 2 * 4)
        entity.endTime = entityReader.read(at: 2 + 2 * 5)
        entity.isActive = entityReader.read(at: 2 + 2 * 6)
        entity.metadataJson = entityReader.read(at: 2 + 2 * 7)
        entity.encryptionKey = entityReader.read(at: 2 + 2 * 8)

        return entity
    }
}



extension TranscriptEntity: ObjectBox.__EntityRelatable {
    internal typealias EntityType = TranscriptEntity

    internal var _id: EntityId<TranscriptEntity> {
        return EntityId<TranscriptEntity>(self.id.value)
    }
}

extension TranscriptEntity: ObjectBox.EntityInspectable {
    internal typealias EntityBindingType = TranscriptEntityBinding

    /// Generated metadata used by ObjectBox to persist the entity.
    internal static let entityInfo = ObjectBox.EntityInfo(name: "TranscriptEntity", id: 5)

    internal static let entityBinding = EntityBindingType()

    fileprivate static func buildEntity(modelBuilder: ObjectBox.ModelBuilder) throws {
        let entityBuilder = try modelBuilder.entityBuilder(for: TranscriptEntity.self, id: 5, uid: 5398475576309847296)
        try entityBuilder.addProperty(name: "id", type: PropertyType.long, flags: [.id], id: 1, uid: 7350394064774895616)
        try entityBuilder.addProperty(name: "sessionId", type: PropertyType.string, id: 2, uid: 2058239952326252032)
        try entityBuilder.addProperty(name: "speaker", type: PropertyType.string, id: 3, uid: 91728609553828608)
        try entityBuilder.addProperty(name: "encryptedText", type: PropertyType.string, id: 4, uid: 570261145231283200)
        try entityBuilder.addProperty(name: "timestamp", type: PropertyType.date, id: 5, uid: 7252534220551550464)
        try entityBuilder.addProperty(name: "wasRedacted", type: PropertyType.bool, id: 6, uid: 8647838031010104832)
        try entityBuilder.addProperty(name: "metadataJson", type: PropertyType.string, id: 7, uid: 7934176081934150400)
        try entityBuilder.addProperty(name: "textHash", type: PropertyType.string, id: 8, uid: 1807002689113542144)

        try entityBuilder.lastProperty(id: 8, uid: 1807002689113542144)
    }
}

extension TranscriptEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.id == myId }
    internal static var id: Property<TranscriptEntity, Id, Id> { return Property<TranscriptEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.sessionId.startsWith("X") }
    internal static var sessionId: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.speaker.startsWith("X") }
    internal static var speaker: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.encryptedText.startsWith("X") }
    internal static var encryptedText: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 4, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.timestamp > 1234 }
    internal static var timestamp: Property<TranscriptEntity, Date, Void> { return Property<TranscriptEntity, Date, Void>(propertyId: 5, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.wasRedacted == true }
    internal static var wasRedacted: Property<TranscriptEntity, Bool, Void> { return Property<TranscriptEntity, Bool, Void>(propertyId: 6, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.metadataJson.startsWith("X") }
    internal static var metadataJson: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 7, isPrimaryKey: false) }
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { TranscriptEntity.textHash.startsWith("X") }
    internal static var textHash: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 8, isPrimaryKey: false) }

    fileprivate func __setId(identifier: ObjectBox.Id) {
        self.id = Id(identifier)
    }
}

extension ObjectBox.Property where E == TranscriptEntity {
    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .id == myId }

    internal static var id: Property<TranscriptEntity, Id, Id> { return Property<TranscriptEntity, Id, Id>(propertyId: 1, isPrimaryKey: true) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .sessionId.startsWith("X") }

    internal static var sessionId: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 2, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .speaker.startsWith("X") }

    internal static var speaker: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 3, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .encryptedText.startsWith("X") }

    internal static var encryptedText: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 4, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .timestamp > 1234 }

    internal static var timestamp: Property<TranscriptEntity, Date, Void> { return Property<TranscriptEntity, Date, Void>(propertyId: 5, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .wasRedacted == true }

    internal static var wasRedacted: Property<TranscriptEntity, Bool, Void> { return Property<TranscriptEntity, Bool, Void>(propertyId: 6, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .metadataJson.startsWith("X") }

    internal static var metadataJson: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 7, isPrimaryKey: false) }

    /// Generated entity property information.
    ///
    /// You may want to use this in queries to specify fetch conditions, for example:
    ///
    ///     box.query { .textHash.startsWith("X") }

    internal static var textHash: Property<TranscriptEntity, String, Void> { return Property<TranscriptEntity, String, Void>(propertyId: 8, isPrimaryKey: false) }

}


/// Generated service type to handle persisting and reading entity data. Exposed through `TranscriptEntity.EntityBindingType`.
internal final class TranscriptEntityBinding: ObjectBox.EntityBinding, Sendable {
    internal typealias EntityType = TranscriptEntity
    internal typealias IdType = Id

    internal required init() {}

    internal func generatorBindingVersion() -> Int { 1 }

    internal func setEntityIdUnlessStruct(of entity: EntityType, to entityId: ObjectBox.Id) {
        entity.__setId(identifier: entityId)
    }

    internal func entityId(of entity: EntityType) -> ObjectBox.Id {
        return entity.id.value
    }

    internal func collect(fromEntity entity: EntityType, id: ObjectBox.Id,
                                  propertyCollector: ObjectBox.FlatBufferBuilder, store: ObjectBox.Store) throws {
        let propertyOffset_sessionId = propertyCollector.prepare(string: entity.sessionId)
        let propertyOffset_speaker = propertyCollector.prepare(string: entity.speaker)
        let propertyOffset_encryptedText = propertyCollector.prepare(string: entity.encryptedText)
        let propertyOffset_metadataJson = propertyCollector.prepare(string: entity.metadataJson)
        let propertyOffset_textHash = propertyCollector.prepare(string: entity.textHash)

        propertyCollector.collect(id, at: 2 + 2 * 1)
        propertyCollector.collect(entity.timestamp, at: 2 + 2 * 5)
        propertyCollector.collect(entity.wasRedacted, at: 2 + 2 * 6)
        propertyCollector.collect(dataOffset: propertyOffset_sessionId, at: 2 + 2 * 2)
        propertyCollector.collect(dataOffset: propertyOffset_speaker, at: 2 + 2 * 3)
        propertyCollector.collect(dataOffset: propertyOffset_encryptedText, at: 2 + 2 * 4)
        propertyCollector.collect(dataOffset: propertyOffset_metadataJson, at: 2 + 2 * 7)
        propertyCollector.collect(dataOffset: propertyOffset_textHash, at: 2 + 2 * 8)
    }

    internal func createEntity(entityReader: ObjectBox.FlatBufferReader, store: ObjectBox.Store) -> EntityType {
        let entity = TranscriptEntity()

        entity.id = entityReader.read(at: 2 + 2 * 1)
        entity.sessionId = entityReader.read(at: 2 + 2 * 2)
        entity.speaker = entityReader.read(at: 2 + 2 * 3)
        entity.encryptedText = entityReader.read(at: 2 + 2 * 4)
        entity.timestamp = entityReader.read(at: 2 + 2 * 5)
        entity.wasRedacted = entityReader.read(at: 2 + 2 * 6)
        entity.metadataJson = entityReader.read(at: 2 + 2 * 7)
        entity.textHash = entityReader.read(at: 2 + 2 * 8)

        return entity
    }
}


/// Helper function that allows calling Enum(rawValue: value) with a nil value, which will return nil.
fileprivate func optConstruct<T: RawRepresentable>(_ type: T.Type, rawValue: T.RawValue?) -> T? {
    guard let rawValue = rawValue else { return nil }
    return T(rawValue: rawValue)
}

// MARK: - Store setup

fileprivate func cModel() throws -> OpaquePointer {
    let modelBuilder = try ObjectBox.ModelBuilder()
    try AuditEntity.buildEntity(modelBuilder: modelBuilder)
    try FileEntity.buildEntity(modelBuilder: modelBuilder)
    try MemoryEntity.buildEntity(modelBuilder: modelBuilder)
    try SessionEntity.buildEntity(modelBuilder: modelBuilder)
    try TranscriptEntity.buildEntity(modelBuilder: modelBuilder)
    modelBuilder.lastEntity(id: 5, uid: 5398475576309847296)
    return modelBuilder.finish()
}

extension ObjectBox.Store {
    /// A store with a fully configured model. Created by the code generator with your model's metadata in place.
    ///
    /// # In-memory database
    /// To use a file-less in-memory database, instead of a directory path pass `memory:` 
    /// together with an identifier string:
    /// ```swift
    /// let inMemoryStore = try Store(directoryPath: "memory:test-db")
    /// ```
    ///
    /// - Parameters:
    ///   - directoryPath: The directory path in which ObjectBox places its database files for this store,
    ///     or to use an in-memory database `memory:<identifier>`.
    ///   - maxDbSizeInKByte: Limit of on-disk space for the database files. Default is `1024 * 1024` (1 GiB).
    ///   - fileMode: UNIX-style bit mask used for the database files; default is `0o644`.
    ///     Note: directories become searchable if the "read" or "write" permission is set (e.g. 0640 becomes 0750).
    ///   - maxReaders: The maximum number of readers.
    ///     "Readers" are a finite resource for which we need to define a maximum number upfront.
    ///     The default value is enough for most apps and usually you can ignore it completely.
    ///     However, if you get the maxReadersExceeded error, you should verify your
    ///     threading. For each thread, ObjectBox uses multiple readers. Their number (per thread) depends
    ///     on number of types, relations, and usage patterns. Thus, if you are working with many threads
    ///     (e.g. in a server-like scenario), it can make sense to increase the maximum number of readers.
    ///     Note: The internal default is currently around 120. So when hitting this limit, try values around 200-500.
    ///   - readOnly: Opens the database in read-only mode, i.e. not allowing write transactions.
    ///
    /// - important: This initializer is created by the code generator. If you only see the internal `init(model:...)`
    ///              initializer, trigger code generation by building your project.
    internal convenience init(directoryPath: String, maxDbSizeInKByte: UInt64 = 1024 * 1024,
                            fileMode: UInt32 = 0o644, maxReaders: UInt32 = 0, readOnly: Bool = false) throws {
        try self.init(
            model: try cModel(),
            directory: directoryPath,
            maxDbSizeInKByte: maxDbSizeInKByte,
            fileMode: fileMode,
            maxReaders: maxReaders,
            readOnly: readOnly)
    }
}

// swiftlint:enable all
