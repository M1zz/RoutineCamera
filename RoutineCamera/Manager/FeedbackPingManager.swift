//
//  FeedbackPingManager.swift
//  RoutineCamera
//
//  CloudKit 공개 DB를 이용한 피드백 푸시 채널.
//  서버·APNs 키 업로드·유료 요금제 없이 Apple(iCloud)이 푸시를 배달한다.
//  피드백 본문은 Firebase에 있고, 여기로는 "알림 신호(핑)"만 흐른다.
//
//  프라이버시: 공개 DB 특성상 레코드는 다른 사용자도 조회할 수 있으므로
//  내용을 최소화한다 (받는사람 ID, 보낸사람 닉네임, 끼니 이름만 — 피드백 내용 없음).
//

import Foundation
import CloudKit

final class FeedbackPingManager {
    static let shared = FeedbackPingManager()

    private static let recordType = "FeedbackPing"
    private static let subscriptionSavedKey = "feedbackPingSubscriptionUserId"
    private static let sentPingsKey = "sentFeedbackPings" // [recordName: 생성시각] — 내가 보낸 핑의 로컬 장부
    private static let pingRetentionDays = 7

    private var database: CKDatabase {
        CKContainer.default().publicCloudDatabase
    }

    private init() {}

    // MARK: - 핑 보내기 (피드백/콕 작성 직후 호출)

    /// 받는 사람에게 푸시가 가도록 핑 레코드 저장. 실패해도 피드백 저장에는 영향 없음.
    func sendPing(to recipientId: String, mealTypeName: String) {
        _Concurrency.Task {
            do {
                let status = try await CKContainer.default().accountStatus()
                guard status == .available else {
                    print("📡 [Ping] iCloud 미로그인 - 핑 생략")
                    return
                }

                let record = CKRecord(recordType: Self.recordType)
                record["recipientId"] = recipientId as CKRecordValue
                record["authorNickname"] = SettingsManager.shared.nickname as CKRecordValue
                record["mealName"] = mealTypeName as CKRecordValue

                let saved = try await database.save(record)
                rememberSentPing(recordName: saved.recordID.recordName)
                print("📡 [Ping] 전송 완료: \(mealTypeName)")
            } catch {
                print("❌ [Ping] 전송 실패 (피드백은 정상 저장됨): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 푸시 구독 등록 (로그인 후 1회)

    /// 내 앞으로 온 핑에 대한 푸시 구독 등록. 같은 계정으로 이미 등록했으면 스킵.
    func ensureSubscription(for myUserId: String) {
        guard !myUserId.isEmpty else { return }

        if UserDefaults.standard.string(forKey: Self.subscriptionSavedKey) == myUserId {
            return
        }

        _Concurrency.Task {
            do {
                let status = try await CKContainer.default().accountStatus()
                guard status == .available else {
                    print("📡 [Ping] iCloud 미로그인 - 구독 생략")
                    return
                }

                let predicate = NSPredicate(format: "recipientId == %@", myUserId)
                let subscription = CKQuerySubscription(
                    recordType: Self.recordType,
                    predicate: predicate,
                    subscriptionID: "feedback-ping-\(myUserId)",
                    options: [.firesOnRecordCreation]
                )

                let info = CKSubscription.NotificationInfo()
                info.title = "새 피드백이 도착했어요 💬"
                info.alertBody = "친구가 내 식단에 메시지를 남겼어요. 확인해 보세요!"
                info.soundName = "default"
                subscription.notificationInfo = info

                _ = try await database.save(subscription)
                UserDefaults.standard.set(myUserId, forKey: Self.subscriptionSavedKey)
                print("📡 [Ping] 푸시 구독 등록 완료")
            } catch let error as CKError where error.code == .serverRejectedRequest {
                // 동일 ID 구독이 이미 서버에 존재 - 등록된 것으로 간주
                UserDefaults.standard.set(myUserId, forKey: Self.subscriptionSavedKey)
                print("📡 [Ping] 구독이 이미 존재함 - 스킵")
            } catch {
                print("❌ [Ping] 구독 등록 실패: \(error.localizedDescription)")
            }
        }
    }

    /// 로그아웃 시 다음 로그인에서 구독을 다시 확인하도록 로컬 플래그 해제
    func resetSubscriptionFlag() {
        UserDefaults.standard.removeObject(forKey: Self.subscriptionSavedKey)
    }

    // MARK: - 오래된 핑 정리

    /// 내가 보낸 핑 중 보관 기간(7일)이 지난 것 삭제.
    /// 공개 DB 레코드는 생성자만 지울 수 있으므로, 각자 자기가 보낸 것을 정리한다.
    /// (앱을 삭제하면 장부가 사라져 고아 레코드가 남을 수 있지만, 내용이 최소화되어 있어 무해)
    func cleanupOldPings() {
        let sent = UserDefaults.standard.dictionary(forKey: Self.sentPingsKey) as? [String: TimeInterval] ?? [:]
        guard !sent.isEmpty else { return }

        let cutoff = Date().addingTimeInterval(-TimeInterval(Self.pingRetentionDays * 24 * 60 * 60)).timeIntervalSince1970
        let expired = sent.filter { $0.value < cutoff }
        guard !expired.isEmpty else { return }

        _Concurrency.Task {
            var remaining = sent
            for (recordName, _) in expired {
                do {
                    try await database.deleteRecord(withID: CKRecord.ID(recordName: recordName))
                    remaining.removeValue(forKey: recordName)
                } catch let error as CKError where error.code == .unknownItem {
                    // 이미 서버에 없음 - 장부에서만 제거
                    remaining.removeValue(forKey: recordName)
                } catch {
                    // 실패한 항목은 장부에 남겨 다음 실행 때 재시도
                    print("❌ [Ping] 정리 실패(재시도 예정): \(error.localizedDescription)")
                }
            }
            let deletedCount = sent.count - remaining.count
            UserDefaults.standard.set(remaining, forKey: Self.sentPingsKey)
            print("📡 [Ping] 오래된 핑 정리: \(deletedCount)개 삭제")
        }
    }

    private func rememberSentPing(recordName: String) {
        var sent = UserDefaults.standard.dictionary(forKey: Self.sentPingsKey) as? [String: TimeInterval] ?? [:]
        sent[recordName] = Date().timeIntervalSince1970
        UserDefaults.standard.set(sent, forKey: Self.sentPingsKey)
    }
}
