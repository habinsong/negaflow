import Foundation
import Chromabase
import ScannerKit

/// 스캔 세션이 결과를 publish할 물리 롤을 카탈로그 안에서 예약한다.
/// 첫 성공 전에는 같은 `rollID`의 `LibraryRoll`이 아직 존재하지 않을 수 있다.
struct LibraryScanRollAssignment: Codable, Equatable, Sendable {
    var sessionID: UUID
    var rollID: UUID
    var draftName: String
    /// 물리 롤과 스캔 저장 분류에 사용하는 필름 종류.
    var filmType: FilmType
    /// 캡처 중에도 바꿀 수 있는 초기 현상 프로세스. 기존 카탈로그는 `filmType`으로 폴백한다.
    var developFilmType: FilmType? = nil
    var createdAt: Date
}

// MARK: - LibraryCatalog (라이브러리 영속화 스키마)
//
// 카탈로그 격의 JSON 스냅샷. 원본 파일은 경로 참조만 하고(비파괴), 썸네일은 디스크
// 캐시에서 프레임 id 로 결정되는 경로를 쓰므로 카탈로그에 저장하지 않는다 — 썸네일 캐시를
// 지워도 카탈로그와 원본은 무사하고, 다음 현상 때 다시 채워진다.
struct LibraryCatalog: Codable, Equatable {
    static let currentVersion = 6
    static let oldestReaderVersion = 6
    var version: Int
    /// 이 스키마를 안전하게 해석할 수 있는 최소 reader 버전.
    var minimumReaderVersion: Int
    /// 폴더 가져오기로 등록된 라이브러리 폴더 경로.
    var folders: [String]
    var frames: [LibraryFrameRecord]
    /// 물리 폴더와 분리된 필름 롤 컬렉션. 프레임 소속의 단일 source of truth다.
    var rolls: [LibraryRoll]
    /// 새 스캔을 받을 현재 물리 롤. 선택되지 않았거나 legacy migration이면 nil이다.
    var activeRollID: UUID?
    /// 프리뷰를 제외한 영속 스캔 세션과 재시도 가능한 job 상태.
    var scanSessions: [ScanSession]
    /// 각 영속 스캔 세션이 publish할 물리 롤 예약. 세션마다 정확히 하나다.
    var scanRollAssignments: [LibraryScanRollAssignment]
    /// frame ID를 순서대로 보유하는 사용자 컬렉션.
    var manualCollections: [LibraryManualCollection]
    /// query payload가 catalog 구조 decode를 막지 않도록 독립 envelope로 저장한다.
    var smartCollections: [LibrarySmartCollection]
    var savedSearches: [LibrarySavedSearch]
    /// 사진 정리용 논리 스택. 원본/가상 사본 수명주기와 물리 롤 소속은 변경하지 않는다.
    var stacks: [LibraryPhotoStack]

    init(
        version: Int = currentVersion,
        minimumReaderVersion: Int = oldestReaderVersion,
        folders: [String] = [],
        frames: [LibraryFrameRecord] = [],
        rolls: [LibraryRoll]? = nil,
        activeRollID: UUID? = nil,
        scanSessions: [ScanSession] = [],
        scanRollAssignments: [LibraryScanRollAssignment] = [],
        manualCollections: [LibraryManualCollection] = [],
        smartCollections: [LibrarySmartCollection] = [],
        savedSearches: [LibrarySavedSearch] = [],
        stacks: [LibraryPhotoStack] = []
    ) {
        self.version = version
        self.minimumReaderVersion = minimumReaderVersion
        self.folders = folders
        self.frames = frames
        if let rolls {
            self.rolls = rolls
        } else if let createdAt = frames.map(\.scannedAt).min() {
            self.rolls = [LibraryRoll.unassigned(
                createdAt: createdAt,
                frameIDs: frames.map(\.id)
            )]
        } else {
            self.rolls = []
        }
        self.activeRollID = activeRollID
        self.scanSessions = scanSessions
        self.scanRollAssignments = scanRollAssignments
        self.manualCollections = manualCollections
        self.smartCollections = smartCollections
        self.savedSearches = savedSearches
        self.stacks = stacks
    }
}

extension LibraryCatalog {
    private enum CodingKeys: String, CodingKey {
        case version
        case minimumReaderVersion
        case folders
        case frames
        case rolls
        case activeRollID
        case scanSessions
        case scanRollAssignments
        case manualCollections
        case smartCollections
        case savedSearches
        case stacks
    }

    /// v6 key는 모두 required다. 잘린 current catalog를 빈 컬렉션이나 미추적 상태로
    /// 조용히 열면 다음 저장에서 사용자 조직 정보가 유실될 수 있다.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        minimumReaderVersion = try container.decode(Int.self, forKey: .minimumReaderVersion)
        folders = try container.decode([String].self, forKey: .folders)
        frames = try container.decode([LibraryFrameRecord].self, forKey: .frames)
        rolls = try container.decode([LibraryRoll].self, forKey: .rolls)
        activeRollID = try container.decodeIfPresent(UUID.self, forKey: .activeRollID)
        scanSessions = try container.decode([ScanSession].self, forKey: .scanSessions)
        scanRollAssignments = try container.decode(
            [LibraryScanRollAssignment].self,
            forKey: .scanRollAssignments
        )
        manualCollections = try container.decode(
            [LibraryManualCollection].self,
            forKey: .manualCollections
        )
        smartCollections = try container.decode(
            [LibrarySmartCollection].self,
            forKey: .smartCollections
        )
        savedSearches = try container.decode(
            [LibrarySavedSearch].self,
            forKey: .savedSearches
        )
        stacks = try container.decode([LibraryPhotoStack].self, forKey: .stacks)
    }
}
