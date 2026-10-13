import CloudKit
import Combine
import CryptoKit
import Foundation

private struct FamilyMembership: Codable {
    let name: String
    let zoneName: String
    let ownerName: String
    let accountID: String
    let isOwner: Bool

    var id: String { zoneName }
    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }
}

private struct FamilyQueuedChange: Codable, Equatable {
    let recordType: String
    let recordName: String
    let payload: Data?

    var key: String { "\(recordType):\(recordName)" }
}

private struct FamilyPlaybackDeviceRecord: Codable {
    let deviceID: String
    let snapshot: PlaybackStatsSnapshot
}

private struct FamilyReviewRecord: Codable {
    let mediaID: String
    let state: ReviewState
}

private struct FamilyProgressRecord: Codable {
    let memberID: String
    let mediaID: String
    let positionMS: Int
    let updatedAt: Date
}

private enum FamilyRecordType {
    static let media = "LumeMedia"
    static let group = "LumeFavoriteGroup"
    static let entry = "LumeFavoriteEntry"
    static let playback = "LumePlaybackDevice"
    static let review = "LumeReviewState"
    static let progress = "LumeProgress"

    static let library: Set<String> = [media, group, entry]
}

enum FamilySharingError: LocalizedError {
    case iCloudUnavailable
    case accountChanged
    case noSavedFamily
    case invalidShare

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: return "Sign in to iCloud on this device to use a family library."
        case .accountChanged: return "The iCloud account changed. Open the family invitation again."
        case .noSavedFamily: return "No family library is available on this device."
        case .invalidShare: return "The family invitation could not be opened."
        }
    }
}

@MainActor
final class FamilySharingManager: ObservableObject {
    static let shared = FamilySharingManager()

    @Published private(set) var familyName: String?
    @Published private(set) var hasSavedFamily = false
    @Published private(set) var isOwner = false
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var isBusy = false
    @Published private(set) var isSyncing = false
    @Published private(set) var shareRecord: CKShare?
    @Published private(set) var lastSyncAt: Date?
    @Published var errorMessage: String?

    var isUsingFamily: Bool { activeFamily != nil }
    var sessionStoragePrefix: String { activeFamily.map { "lume.family.\($0.id)." } ?? "lume." }

    private let container = CKContainer.default()
    private let defaults = UserDefaults.standard
    private let library = LocalLibraryStore.shared
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let savedFamilyKey = "lume.family.membership"
    private static let useFamilyKey = "lume.family.isActive"
    private static let deviceIDKey = "lume.family.deviceID"

    private let deviceID: String
    private var activeFamily: FamilyMembership?
    private var cloudRecords: [String: FamilyQueuedChange] = [:]
    private var pending: [String: FamilyQueuedChange] = [:]
    private var knownLibraryRecords: [String: FamilyQueuedChange] = [:]
    private var knownReviewRecords: [String: FamilyQueuedChange] = [:]
    private var progressRecords: [String: FamilyProgressRecord] = [:]
    private var changeToken: CKServerChangeToken?
    private var started = false
    private var startTask: Task<Void, Never>?
    private var syncRequested = false
    private var scheduledSync: Task<Void, Never>?
    private var scheduledPlayback: Task<Void, Never>?

    private init() {
        let id = defaults.string(forKey: Self.deviceIDKey) ?? UUID().uuidString
        deviceID = id
        defaults.set(id, forKey: Self.deviceIDKey)
        hasSavedFamily = defaults.data(forKey: Self.savedFamilyKey) != nil
    }

    func start() async {
        if let startTask {
            await startTask.value
            return
        }
        guard !started else { return }
        let task = Task { await initialize() }
        startTask = task
        await task.value
        startTask = nil
    }

    private func initialize() async {
        started = true
        do {
            let accountID = try await requireICloudAccount()
            guard activeFamily == nil else { return }
            guard defaults.bool(forKey: Self.useFamilyKey),
                  let saved = savedMembership() else { return }
            guard saved.accountID == accountID else {
                defaults.removeObject(forKey: Self.savedFamilyKey)
                defaults.set(false, forKey: Self.useFamilyKey)
                hasSavedFamily = false
                errorMessage = FamilySharingError.accountChanged.localizedDescription
                return
            }
            try await activate(saved, copyPersonalData: false)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createFamily(name: String) async throws {
        let accountID = try await requireICloudAccount()
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanedName.isEmpty ? "Family Library" : cleanedName
        isBusy = true
        defer { isBusy = false }

        let zone = CKRecordZone(zoneName: "lume-family-\(UUID().uuidString)")
        _ = try await container.privateCloudDatabase.save(zone)
        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = title as NSString
        share.publicPermission = .none
        guard let savedShare = try await container.privateCloudDatabase.save(share) as? CKShare else {
            throw FamilySharingError.invalidShare
        }

        let membership = FamilyMembership(
            name: title,
            zoneName: zone.zoneID.zoneName,
            ownerName: zone.zoneID.ownerName,
            accountID: accountID,
            isOwner: true
        )
        try await activate(membership, copyPersonalData: true)
        shareRecord = savedShare
        try await queueInitialRecords()
        await refresh()
        if let errorMessage { throw NSError(domain: "LumeFamily", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage]) }
    }

    func accept(_ metadata: CKShare.Metadata) async {
        await start()
        isBusy = true
        defer { isBusy = false }
        do {
            let accountID = try await requireICloudAccount()
            let share: CKShare
            if metadata.participantStatus == .pending {
                share = try await container.accept(metadata)
            } else {
                share = metadata.share
            }
            let zoneID = try await sharedZoneID(for: share)
            let title = (share[CKShare.SystemFieldKey.title] as? String) ?? "Family Library"
            let membership = FamilyMembership(
                name: title,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                accountID: accountID,
                isOwner: false
            )
            try await activate(membership, copyPersonalData: false)
            shareRecord = share
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeFamily() async throws {
        let accountID = try await requireICloudAccount()
        guard let saved = savedMembership() else { throw FamilySharingError.noSavedFamily }
        guard saved.accountID == accountID else { throw FamilySharingError.accountChanged }
        try await activate(saved, copyPersonalData: false)
        await refresh()
    }

    func usePersonalLibrary() async {
        guard activeFamily != nil else { return }
        scheduledSync?.cancel()
        scheduledSync = nil
        scheduledPlayback?.cancel()
        scheduledPlayback = nil
        activeFamily = nil
        familyName = nil
        isOwner = false
        shareRecord = nil
        cloudRecords = [:]
        pending = [:]
        knownLibraryRecords = [:]
        knownReviewRecords = [:]
        progressRecords = [:]
        changeToken = nil
        defaults.set(false, forKey: Self.useFamilyKey)
        await library.switchToPersonalLibrary()
        PlaybackStatsStore.shared.deactivateFamily()
        SpacedRepetitionStore.shared.deactivateFamily()
        NotificationCenter.default.post(name: APIClient.didSwitchLibrary, object: nil)
        NotificationCenter.default.post(name: APIClient.didChangeFamilyLibrary, object: nil)
    }

    func iCloudAccountDidChange() async {
        let accountID = try? await requireICloudAccount()
        if let accountID, let saved = savedMembership(), saved.accountID != accountID {
            if activeFamily != nil { await usePersonalLibrary() }
            defaults.removeObject(forKey: Self.savedFamilyKey)
            defaults.set(false, forKey: Self.useFamilyKey)
            hasSavedFamily = false
            errorMessage = FamilySharingError.accountChanged.localizedDescription
            return
        }
        if let activeFamily, activeFamily.accountID != accountID {
            await usePersonalLibrary()
            defaults.set(true, forKey: Self.useFamilyKey)
            errorMessage = FamilySharingError.iCloudUnavailable.localizedDescription
        } else if activeFamily != nil {
            await refresh()
        } else if accountID != nil, defaults.bool(forKey: Self.useFamilyKey), savedMembership() != nil {
            do { try await resumeFamily() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func refresh() async {
        guard let family = activeFamily else { return }
        guard !isSyncing else { syncRequested = true; return }
        isSyncing = true
        defer {
            isSyncing = false
            if syncRequested { scheduleSync(after: 1) }
        }
        repeat {
            syncRequested = false
            do {
                try await pullChanges(for: family)
                guard activeFamily?.id == family.id else { return }
                try await pushPending(for: family)
                guard activeFamily?.id == family.id else { return }
                try await pullChanges(for: family)
                guard activeFamily?.id == family.id else { return }
                lastSyncAt = Date()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } while syncRequested && activeFamily?.id == family.id
    }

    func libraryDidChange() async {
        guard activeFamily != nil else { return }
        do {
            let current = try encodeLibrary(await library.familySnapshot())
            for key in Set(current.keys).union(knownLibraryRecords.keys) where current[key] != knownLibraryRecords[key] {
                let previous = knownLibraryRecords[key]
                pending[key] = current[key] ?? FamilyQueuedChange(
                    recordType: previous!.recordType,
                    recordName: previous!.recordName,
                    payload: nil
                )
            }
            knownLibraryRecords = current
            persistPending()
            scheduleSync(after: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playbackDidChange(immediate: Bool = false) {
        guard activeFamily != nil else { return }
        if immediate {
            scheduledPlayback?.cancel()
            scheduledPlayback = nil
            queuePlaybackSnapshot()
            scheduleSync(after: 1)
        } else if scheduledPlayback == nil {
            scheduledPlayback = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                self?.scheduledPlayback = nil
                self?.queuePlaybackSnapshot()
                self?.scheduleSync(after: 1)
            }
        }
    }

    func reviewDidChange(mediaID: String) {
        guard activeFamily != nil else { return }
        do {
            let key = Self.recordKey(type: FamilyRecordType.review, name: Self.recordName(prefix: "review", value: mediaID))
            if let state = SpacedRepetitionStore.shared.states[mediaID] {
                let value = FamilyReviewRecord(mediaID: mediaID, state: state)
                let change = try makeChange(type: FamilyRecordType.review, name: Self.recordName(prefix: "review", value: mediaID), value: value)
                knownReviewRecords[key] = change
                pending[key] = change
            } else {
                knownReviewRecords[key] = nil
                pending[key] = FamilyQueuedChange(recordType: FamilyRecordType.review, recordName: Self.recordName(prefix: "review", value: mediaID), payload: nil)
            }
            persistPending()
            scheduleSync(after: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func allReviewStatesDidChange() {
        guard activeFamily != nil else { return }
        do {
            let current = try encodeReviews(SpacedRepetitionStore.shared.currentSnapshot())
            for key in Set(current.keys).union(knownReviewRecords.keys) where current[key] != knownReviewRecords[key] {
                let previous = knownReviewRecords[key]
                pending[key] = current[key] ?? FamilyQueuedChange(recordType: previous!.recordType, recordName: previous!.recordName, payload: nil)
            }
            knownReviewRecords = current
            persistPending()
            scheduleSync(after: 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func progressDidChange(mediaID: String, positionMS: Int, event: String?) {
        guard let family = activeFamily else { return }
        let value = FamilyProgressRecord(
            memberID: family.accountID,
            mediaID: mediaID,
            positionMS: event == "end" ? 0 : max(0, positionMS),
            updatedAt: Date()
        )
        do {
            let change = try makeChange(
                type: FamilyRecordType.progress,
                name: Self.recordName(prefix: "progress", value: "\(family.accountID):\(mediaID)"),
                value: value
            )
            pending[change.key] = change
            progressRecords["\(family.accountID):\(mediaID)"] = value
            persistPending()
            scheduleSync(after: event == nil ? 20 : 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumePositionMS(for mediaID: String) -> Int? {
        guard let family = activeFamily else { return nil }
        let key = "\(family.accountID):\(mediaID)"
        let recordName = Self.recordName(prefix: "progress", value: key)
        let recordKey = Self.recordKey(type: FamilyRecordType.progress, name: recordName)
        if let payload = pending[recordKey]?.payload,
           let value = try? decoder.decode(FamilyProgressRecord.self, from: payload) {
            return value.positionMS
        }
        return progressRecords[key].map(\.positionMS)
    }

    func mostRecentProgressMediaID() -> String? {
        guard let family = activeFamily else { return nil }
        return progressRecords.values
            .filter { $0.memberID == family.accountID }
            .max { $0.updatedAt < $1.updatedAt }?
            .mediaID
    }

    private func sharedZoneID(for share: CKShare) async throws -> CKRecordZone.ID {
        let database = container.sharedCloudDatabase
        var token: CKServerChangeToken?
        repeat {
            let page = try await database.databaseChanges(since: token)
            if let zone = page.modifications.map(\.zoneID).first(where: {
                $0.zoneName == share.recordID.zoneID.zoneName
            }) {
                return zone
            }
            token = page.changeToken
            if !page.moreComing { break }
        } while true
        throw FamilySharingError.invalidShare
    }

    private func requireICloudAccount() async throws -> String {
        let status = try await container.accountStatus()
        guard status == .available else {
            iCloudAvailable = false
            throw FamilySharingError.iCloudUnavailable
        }
        iCloudAvailable = true
        return try await container.userRecordID().recordName
    }

    private func activate(_ family: FamilyMembership, copyPersonalData: Bool) async throws {
        let didSwitch = activeFamily?.id != family.id
        if didSwitch {
            cloudRecords = [:]
            changeToken = nil
            pending = loadPending(for: family.id)
            progressRecords = [:]
        }
        try await library.switchToFamily(id: family.id, copyPersonalLibrary: copyPersonalData)
        PlaybackStatsStore.shared.activateFamily(id: family.id, copyPersonalStats: copyPersonalData)
        SpacedRepetitionStore.shared.activateFamily(id: family.id, copyPersonalStates: copyPersonalData)
        activeFamily = family
        familyName = family.name
        isOwner = family.isOwner
        hasSavedFamily = true
        defaults.set(try encoder.encode(family), forKey: Self.savedFamilyKey)
        defaults.set(true, forKey: Self.useFamilyKey)
        knownLibraryRecords = try encodeLibrary(await library.familySnapshot())
        knownReviewRecords = try encodeReviews(SpacedRepetitionStore.shared.currentSnapshot())
        if didSwitch { NotificationCenter.default.post(name: APIClient.didSwitchLibrary, object: nil) }
        NotificationCenter.default.post(name: APIClient.didChangeFamilyLibrary, object: nil)
        await ensureSubscription(for: family)
        if family.isOwner {
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: family.zoneID)
            shareRecord = (try? await database(for: family).record(for: shareID)) as? CKShare
        }
    }

    private func queueInitialRecords() async throws {
        let libraryRecords = try encodeLibrary(await library.familySnapshot())
        let reviewRecords = try encodeReviews(SpacedRepetitionStore.shared.currentSnapshot())
        for change in libraryRecords.values { pending[change.key] = change }
        for change in reviewRecords.values { pending[change.key] = change }
        queuePlaybackSnapshot()
        persistPending()
    }

    private func queuePlaybackSnapshot() {
        guard activeFamily != nil else { return }
        do {
            let value = FamilyPlaybackDeviceRecord(deviceID: deviceID, snapshot: PlaybackStatsStore.shared.localFamilySnapshot())
            let change = try makeChange(type: FamilyRecordType.playback, name: "playback-\(deviceID)", value: value)
            pending[change.key] = change
            persistPending()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSync(after seconds: UInt64) {
        guard scheduledSync == nil else { return }
        scheduledSync = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.scheduledSync = nil
            await self?.refresh()
        }
    }

    private func database(for family: FamilyMembership) -> CKDatabase {
        family.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private func ensureSubscription(for family: FamilyMembership) async {
        let subscription = CKDatabaseSubscription(subscriptionID: family.isOwner ? "lume-family-private" : "lume-family-shared")
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        _ = try? await database(for: family).save(subscription)
    }

    private func pullChanges(for family: FamilyMembership) async throws {
        let database = database(for: family)
        var moreComing = true
        while moreComing {
            let page = try await database.recordZoneChanges(inZoneWith: family.zoneID, since: changeToken)
            guard activeFamily?.id == family.id else { return }
            for result in page.modificationResultsByID.values {
                let record = try result.get().record
                if let share = record as? CKShare {
                    shareRecord = share
                } else if let data = record["payload"] as? Data {
                    let change = FamilyQueuedChange(recordType: record.recordType, recordName: record.recordID.recordName, payload: data)
                    cloudRecords[change.key] = change
                }
            }
            for deletion in page.deletions {
                cloudRecords[Self.recordKey(type: deletion.recordType, name: deletion.recordID.recordName)] = nil
            }
            changeToken = page.changeToken
            moreComing = page.moreComing
        }
        try await applyCloudRecords(for: family)
    }

    private func pushPending(for family: FamilyMembership) async throws {
        let database = database(for: family)
        while !pending.isEmpty {
            guard activeFamily?.id == family.id else { return }
            let batch = Array(pending.values.prefix(100))
            let saves = batch.compactMap { change -> CKRecord? in
                guard let payload = change.payload else { return nil }
                let id = CKRecord.ID(recordName: change.recordName, zoneID: family.zoneID)
                let record = CKRecord(recordType: change.recordType, recordID: id)
                record["payload"] = payload as NSData
                return record
            }
            let deletions = batch.filter { $0.payload == nil }.map {
                CKRecord.ID(recordName: $0.recordName, zoneID: family.zoneID)
            }
            let result = try await database.modifyRecords(saving: saves, deleting: deletions, savePolicy: .allKeys, atomically: false)
            guard activeFamily?.id == family.id else { return }
            var firstError: Error?
            for change in batch {
                let id = CKRecord.ID(recordName: change.recordName, zoneID: family.zoneID)
                let itemResult: Result<Void, Error>?
                if change.payload != nil {
                    itemResult = result.saveResults[id].map { $0.map { _ in () } }
                } else {
                    itemResult = result.deleteResults[id]
                }
                switch itemResult {
                case .success:
                    if pending[change.key] == change { pending[change.key] = nil }
                    cloudRecords[change.key] = change.payload == nil ? nil : change
                case .failure(let error):
                    if change.payload == nil, (error as? CKError)?.code == .unknownItem {
                        if pending[change.key] == change { pending[change.key] = nil }
                        cloudRecords[change.key] = nil
                    } else {
                        firstError = firstError ?? error
                    }
                case .none:
                    firstError = firstError ?? FamilySharingError.invalidShare
                }
            }
            persistPending()
            if let firstError { throw firstError }
        }
    }

    private func applyCloudRecords(for family: FamilyMembership) async throws {
        guard activeFamily?.id == family.id else { return }
        var effective = cloudRecords
        for (key, change) in pending {
            effective[key] = change.payload == nil ? nil : change
        }

        var librarySnapshot = FamilyLibrarySnapshot()
        var remotePlayback: [String: PlaybackStatsSnapshot] = [:]
        var reviewStates: [String: ReviewState] = [:]
        var progress: [String: FamilyProgressRecord] = [:]
        var libraryRecords: [String: FamilyQueuedChange] = [:]
        var reviewRecords: [String: FamilyQueuedChange] = [:]
        for (key, change) in effective {
            guard let payload = change.payload else { continue }
            switch change.recordType {
            case FamilyRecordType.media:
                librarySnapshot.media.append(try decoder.decode(MediaRecord.self, from: payload))
                libraryRecords[key] = change
            case FamilyRecordType.group:
                librarySnapshot.groups.append(try decoder.decode(FamilyFavoriteGroup.self, from: payload))
                libraryRecords[key] = change
            case FamilyRecordType.entry:
                librarySnapshot.entries.append(try decoder.decode(FamilyFavoriteEntry.self, from: payload))
                libraryRecords[key] = change
            case FamilyRecordType.playback:
                let value = try decoder.decode(FamilyPlaybackDeviceRecord.self, from: payload)
                remotePlayback[value.deviceID] = value.snapshot.normalized
            case FamilyRecordType.review:
                let value = try decoder.decode(FamilyReviewRecord.self, from: payload)
                reviewStates[value.mediaID] = value.state
                reviewRecords[key] = change
            case FamilyRecordType.progress:
                let value = try decoder.decode(FamilyProgressRecord.self, from: payload)
                progress["\(value.memberID):\(value.mediaID)"] = value
            default:
                break
            }
        }
        try await library.replaceFamilySnapshot(librarySnapshot, for: family.id)
        guard activeFamily?.id == family.id else { return }
        knownLibraryRecords = libraryRecords
        knownReviewRecords = reviewRecords
        progressRecords = progress
        PlaybackStatsStore.shared.applyRemoteFamilySnapshots(remotePlayback, localDeviceID: deviceID)
        SpacedRepetitionStore.shared.applyRemoteFamilyStates(reviewStates)
        NotificationCenter.default.post(name: APIClient.didChangeFamilyLibrary, object: nil)
    }

    private func encodeLibrary(_ snapshot: FamilyLibrarySnapshot) throws -> [String: FamilyQueuedChange] {
        var records: [String: FamilyQueuedChange] = [:]
        for item in snapshot.media {
            let change = try makeChange(type: FamilyRecordType.media, name: Self.recordName(prefix: "media", value: item.id), value: item)
            records[change.key] = change
        }
        for group in snapshot.groups {
            let change = try makeChange(type: FamilyRecordType.group, name: Self.recordName(prefix: "group", value: group.id), value: group)
            records[change.key] = change
        }
        for entry in snapshot.entries {
            let change = try makeChange(type: FamilyRecordType.entry, name: Self.recordName(prefix: "entry", value: "\(entry.groupID):\(entry.mediaID)"), value: entry)
            records[change.key] = change
        }
        return records
    }

    private func encodeReviews(_ snapshot: ReviewSnapshot) throws -> [String: FamilyQueuedChange] {
        var records: [String: FamilyQueuedChange] = [:]
        for (mediaID, state) in snapshot.states {
            let change = try makeChange(type: FamilyRecordType.review, name: Self.recordName(prefix: "review", value: mediaID), value: FamilyReviewRecord(mediaID: mediaID, state: state))
            records[change.key] = change
        }
        return records
    }

    private func makeChange<T: Encodable>(type: String, name: String, value: T) throws -> FamilyQueuedChange {
        FamilyQueuedChange(recordType: type, recordName: name, payload: try encoder.encode(value))
    }

    private static func recordKey(type: String, name: String) -> String { "\(type):\(name)" }

    private static func recordName(prefix: String, value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(digest)"
    }

    private func savedMembership() -> FamilyMembership? {
        guard let data = defaults.data(forKey: Self.savedFamilyKey) else { return nil }
        return try? decoder.decode(FamilyMembership.self, from: data)
    }

    private func pendingKey(for familyID: String) -> String { "lume.family.pending.\(familyID)" }

    private func loadPending(for familyID: String) -> [String: FamilyQueuedChange] {
        guard let data = defaults.data(forKey: pendingKey(for: familyID)) else { return [:] }
        return (try? decoder.decode([String: FamilyQueuedChange].self, from: data)) ?? [:]
    }

    private func persistPending() {
        guard let family = activeFamily, let data = try? encoder.encode(pending) else { return }
        defaults.set(data, forKey: pendingKey(for: family.id))
    }
}
