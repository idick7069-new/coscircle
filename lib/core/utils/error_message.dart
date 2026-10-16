import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

String userFacingError(Object error) {
  final source = error is Exception ? error.toString() : '$error';
  final cleaned = source
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^DioException\s*\[.*?\]:\s*'), '')
      .trim();
  if (error is TimeoutException) return '連線逾時，請稍後再試';
  if (error is SocketException) return '無法連線，請確認網路或後端服務';
  if (error is DioException) return _dioMessage(error);
  if (cleaned.contains('connection refused') ||
      cleaned.contains('Connection refused')) {
    return '後端服務沒有回應，請確認伺服器是否啟動';
  }
  if (cleaned.contains('No route to host')) {
    return '找不到後端主機，請確認手機與電腦在同一個 Wi-Fi';
  }
  if (cleaned.contains('connectionTimeout') || cleaned.contains('timeout')) {
    return '連線逾時，請稍後再試';
  }
  return cleaned.isEmpty ? '操作失敗，請稍後再試' : cleaned;
}

String _dioMessage(DioException error) {
  final statusCode = error.response?.statusCode;
  final data = error.response?.data;
  if (data is Map && data['error'] != null) {
    return _apiCodeMessage(data['error'].toString());
  }

  if (statusCode == 401) return '登入狀態已失效，請重新登入';
  if (statusCode == 403) return '沒有操作權限';
  if (statusCode == 404) return '找不到資料或後端 API 尚未更新';
  if (statusCode == 409) return '資料已存在，請換一個內容再試';
  if (statusCode != null && statusCode >= 500) {
    return '伺服器暫時發生問題，請稍後再試';
  }

  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => '連線逾時，請稍後再試',
    DioExceptionType.connectionError => '無法連線，請確認網路或後端服務',
    DioExceptionType.badCertificate => '連線憑證異常，請確認伺服器設定',
    DioExceptionType.cancel => '操作已取消',
    _ => '操作失敗，請稍後再試',
  };
}

String _apiCodeMessage(String code) {
  return switch (code) {
    'invalid_email_or_password' || 'invalid_credentials' => 'Email 或密碼不正確',
    'email_already_registered' => '這個 Email 已經註冊過',
    'invalid_email' => '請輸入有效信箱',
    'invalid_new_password' => '新密碼須為 8 至 1024 個字元',
    'invalid_or_expired_email_link' => '連結已失效或使用過，請重新申請',
    'email_resend_cooldown' => '寄信請求過於頻繁，請稍後再試（每日最多 6 封）',
    'account_mail_unavailable' => '寄信服務暫時無法使用，請稍後再試；既有帳號仍可登入',
    'invalid_social_login' => '社群登入資料不完整',
    'invalid_social_token' => '社群登入授權已失效，請重新授權',
    'line_login_not_configured' => 'LINE 登入尚未啟用，請先使用 Email 登入',
    'line_login_unavailable' => 'LINE 登入服務暫時無法連線，請稍後再試',
    'account_suspended' => '此帳號已停權，請聯絡管理員',
    'secure_transport_required' => '登入與綁定需要安全的 HTTPS 連線',
    'reauthentication_required' => '請輸入目前帳號正確的 Email 登入密碼',
    'line_identity_already_linked' => '此 LINE 已綁定其他帳號，或目前帳號已綁定另一個 LINE；未進行任何合併',
    'social_identity_conflict' => '登入資料已存在，請重新登入；若仍失敗請聯絡管理員',
    'authentication_required' => '請先登入',
    'admin_required' => '需要管理員權限',
    'event_name_required' => '請輸入活動名稱',
    'event_venue_required' => '請輸入活動地點',
    'invalid_date' => '日期格式不正確',
    'end_before_start' => '結束日期不能早於開始日期',
    'invalid_image_size' => '圖片大小不可超過限制',
    'invalid_image' || 'invalid_image_bytes' => '圖片格式不正確',
    'invalid_booking_role' => '請選擇有效的活動身份',
    'invalid_day_index' => '活動日期選擇不正確',
    'invalid_latitude' || 'invalid_longitude' => '位置座標不正確，請重新定位',
    'rate_limit_exceeded' => '操作太頻繁，請稍後再試',
    'recognition_pending_exists' => '已送出認親通知，請等對方回覆或 5 分鐘後再試',
    'recognition_declined_cooldown' => '對方剛表示不方便，請稍後再試',
    'recognition_hourly_limit' => '認親通知太頻繁，請晚點再試',
    'recognition_request_not_found' => '這則認親通知已過期或已被回覆',
    'event_booking_required' => '請先加入這一天的活動再使用現場功能',
    'location_share_expired' => '位置分享已停止或到期，請重新分享位置',
    'event_sync_busy' => '已有同步任務正在啟動，請稍後重新讀取進度',
    'event_ended' => '此日期已結束，無法新增、修改或取消預定',
    'nickname_required' => '請輸入暱稱',
    'circle_owner_cannot_leave' => '建立者需解散小圈圈，才能移除整個圈圈',
    'circle_not_found' => '找不到小圈圈，邀請可能已失效',
    'circle_membership_required' => '請先加入這個小圈圈',
    'circle_name_required' => '請輸入小圈圈名稱',
    'internal_server_error' => '伺服器暫時發生問題，請稍後再試',
    'target_not_available_for_event_day' => '對方沒有加入這一天的活動',
    'cannot_recognize_self' => '不能對自己發認親通知',
    'user_unavailable' => '目前無法對這位使用者操作',
    'cannot_friend_self' => '不能對自己送出戳友邀請',
    'invalid_friend_introduction' => '請輸入 1 至 200 字的自我介紹',
    'invalid_friend_event' => '場次或日期已失效，請重新選擇',
    'friend_request_not_found' => '邀請已處理或失效，請重新整理',
    'invalid_friend_action' => '請選擇確認或忽略邀請',
    'cors_origin_not_allowed' => '目前來源不允許連線，請確認後端 CORS 設定',
    _ => '操作失敗，請稍後再試',
  };
}
