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
  if (statusCode == 401) return '登入狀態已失效，請重新登入';
  if (statusCode == 403) return '沒有操作權限';
  if (statusCode == 404) return '找不到資料或後端 API 尚未更新';
  if (statusCode == 409) return '資料已存在，請換一個內容再試';
  if (statusCode != null && statusCode >= 500) {
    return '伺服器暫時發生問題，請稍後再試';
  }

  final data = error.response?.data;
  if (data is Map && data['error'] != null) {
    return _apiCodeMessage(data['error'].toString());
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
    'invalid_social_login' => '社群登入資料不完整',
    'invalid_social_token' => '社群登入授權已失效，請重新授權',
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
    'cors_origin_not_allowed' => '目前來源不允許連線，請確認後端 CORS 設定',
    _ => code,
  };
}
