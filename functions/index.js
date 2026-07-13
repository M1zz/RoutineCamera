/**
 * RoutineCamera Cloud Functions
 *
 * 피드백(콕 찌르기/댓글)이 작성되면 받는 사람에게 FCM 푸시를 보낸다.
 *
 * 배포:
 *   firebase deploy --only functions
 *
 * 전제:
 *   - Blaze 요금제 (Cloud Functions 필수)
 *   - 앱이 users/{userId}/fcmToken 에 FCM 토큰을 저장함 (클라이언트 구현 완료)
 *   - Firebase Console에 APNs 인증 키 등록 (FIREBASE_SETUP.md 참고)
 */

const { onValueCreated } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendFeedbackPush = onValueCreated(
  {
    // 피드백 저장 경로: feedbacks/{받는사람}/{날짜}/{끼니}/{피드백ID}
    ref: "/feedbacks/{userId}/{date}/{mealType}/{feedbackId}",
    // RTDB 인스턴스가 기본(us-central1)이 아니면 instance/region 옵션 추가 필요
  },
  async (event) => {
    const feedback = event.data.val();
    const { userId, mealType } = event.params;

    if (!feedback || !feedback.content) {
      console.log("피드백 데이터 없음 - 스킵");
      return;
    }

    // 받는 사람의 FCM 토큰 조회
    const tokenSnap = await admin
      .database()
      .ref(`/users/${userId}/fcmToken`)
      .get();
    const token = tokenSnap.val();

    if (!token) {
      console.log(`FCM 토큰 없음: ${userId} - 스킵`);
      return;
    }

    const author = feedback.authorNickname || "친구";
    const content =
      feedback.content.length > 80
        ? feedback.content.slice(0, 80) + "…"
        : feedback.content;

    try {
      await admin.messaging().send({
        token,
        notification: {
          title: `${author}님이 ${mealType}에 남긴 메시지`,
          body: content,
        },
        apns: {
          payload: {
            aps: { sound: "default" },
          },
        },
      });
      console.log(`푸시 전송 완료: ${userId} (${mealType})`);
    } catch (error) {
      // 만료된 토큰이면 정리
      if (
        error.code === "messaging/registration-token-not-registered" ||
        error.code === "messaging/invalid-registration-token"
      ) {
        await admin.database().ref(`/users/${userId}/fcmToken`).remove();
        console.log(`만료된 토큰 삭제: ${userId}`);
      } else {
        console.error("푸시 전송 실패:", error);
      }
    }
  }
);
