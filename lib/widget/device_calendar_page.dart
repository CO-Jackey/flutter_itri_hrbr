import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_itri_hrbr/helper/devLog.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class CalendarCrudExample extends StatefulWidget {
  const CalendarCrudExample({super.key});

  @override
  _CalendarCrudExampleState createState() => _CalendarCrudExampleState();
}

class _CalendarCrudExampleState extends State<CalendarCrudExample> {
  late DeviceCalendarPlugin _deviceCalendarPlugin;
  List<Calendar> _calendars = [];
  List<Event> _events = [];
  String? _selectedCalendarId;
  String? _selectedCalendarName;
  Calendar? _selectedCalendar;

  String? createResultID;

  final calendarName = 'AmicoiPet';

  _CalendarCrudExampleState() {
    _deviceCalendarPlugin = DeviceCalendarPlugin();
  }

  @override
  void initState() {
    super.initState();
    // initState 不能是 async，所以我們用一個小技巧來呼叫 async 函數
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _fetchCalendarsAndEvents();
    });
  }

  // 取得權限、讀取行事曆、並讀取事件
  Future<void> _fetchCalendarsAndEvents() async {
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
      if (!permissionsGranted.isSuccess ||
          !(permissionsGranted.data ?? false)) {
        // 權限被拒絕
        return;
      }
    }

    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();

    if (calendarsResult.data != null) {
      devLog('所有行事曆', '========== 開始分析 ==========');
      for (var cal in calendarsResult.data!) {
        devLog(
          '行事曆',
          '${cal.name} | 帳號:${cal.accountName} | 類型:${cal.accountType} | 預設:${cal.isDefault} | 唯讀:${cal.isReadOnly}',
        );
      }
    }

    setState(() {
      // 過濾掉唯讀的行事曆
      _calendars =
          calendarsResult.data
              ?.where((cal) => cal.isReadOnly != true)
              .toList() ??
          [];
      if (_calendars.isNotEmpty) {
        // ⭐ 自動選擇最適合同步的行事曆
        _selectedCalendarId = _selectBestSyncCalendar();

        devLog(
          '同步設定',
          '已選擇行事曆: ${_calendars.firstWhere((c) => c.id == _selectedCalendarId).name}',
        );
        devLog('同步設定', '此行事曆將用於接收你的自訂計劃通知');

        _fetchEvents();

        // _selectedCalendarId = _calendars.first.id;
        // _fetchEvents(); // 取得第一個行事曆的事件
      }
    });
    devLog('獲取行事曆', _calendars.map((e) => e.name).toList().toString());
  }

  // 讀取指定行事曆的事件
  Future<void> _fetchEvents() async {
    if (_selectedCalendarId == null) return;

    final now = DateTime.now();
    final startDate = DateTime(
      now.year,
      now.month,
      now.day,
      0,
      0,
      0,
    ); // 讀取今天開始的事件
    final endDate = DateTime(
      now.year,
      now.month,
      now.day + 5,
      0,
      0,
      0,
    ); // 讀取未來 5 天的事件

    final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
      _selectedCalendarId,
      RetrieveEventsParams(startDate: startDate, endDate: endDate),
    );

    setState(() {
      _events = eventsResult.data ?? [];
    });
  }

  // 新增事件
  Future<void> _addEvent() async {
    if (_selectedCalendarId == null) return;

    final eventToAdd = Event(
      _selectedCalendarId,
      title: 'Flutter 新增的事件',
      description: '這是一個可以被管理的事件。',
      start: tz.TZDateTime.now(tz.local).add(Duration(minutes: 10)),
      end: tz.TZDateTime.now(tz.local).add(Duration(minutes: 20)),
    );

    final createEventResult = await _deviceCalendarPlugin.createOrUpdateEvent(
      eventToAdd,
    );
    if (createEventResult?.isSuccess == true) {
      devLog('新增事件', '事件新增成功！');
      _fetchEvents(); // 新增成功後，重新讀取一次事件列表來更新 UI
    } else {
      devLog('新增事件', '新增事件失敗: ${createEventResult?.errors}');
    }
  }

  // 修改事件
  Future<void> _modifyEvent(Event event) async {
    final eventToUpdate = Event(
      _selectedCalendarId,
      eventId: event.eventId, // ‼️ 關鍵：傳入 eventId 來表示這是在更新
      title: '${event.title} (已修改)',
      start: event.start, // 保持原時間或設定新時間
      end: event.end,
    );

    final updateResult = await _deviceCalendarPlugin.createOrUpdateEvent(
      eventToUpdate,
    );
    if (updateResult?.isSuccess == true) {
      devLog('修改事件', '事件修改成功！');
      _fetchEvents(); // 修改成功後，重新整理列表
    } else {
      devLog('修改事件', '修改事件失敗: ${updateResult?.errors}');
    }
  }

  // 刪除事件
  Future<void> _deleteEvent(String? eventId) async {
    if (_selectedCalendarId == null || eventId == null) return;

    final deleteResult = await _deviceCalendarPlugin.deleteEvent(
      _selectedCalendarId!,
      eventId,
    );
    if (deleteResult.isSuccess) {
      devLog('刪除事件', '事件刪除成功！');
      _fetchEvents(); // 刪除成功後，重新整理列表
    } else {
      devLog('刪除事件', '刪除事件失敗: ${deleteResult.errors}');
    }
  }

  // 選擇最適合同步的系統行事曆
  String? _selectBestSyncCalendar() {
    if (_calendars.isEmpty) {
      createCalendar();
    } else {
      if (Platform.isAndroid) {
        final amicoipetCalendar = _calendars.firstWhere(
          (cal) =>
              cal.isDefault == true &&
              cal.accountType?.toLowerCase().contains('amicoipet') == true,
          orElse: () => Calendar(),
        );
        if (amicoipetCalendar.id != null) {
          devLog('選擇行事曆', '使用 AmicoiPet 預設行事曆: ${amicoipetCalendar.name}');
          return amicoipetCalendar.id;
        }
      } else if (Platform.isIOS) {
        final amicoipetCalendar = _calendars.firstWhere(
          (cal) =>
              cal.isDefault == true &&
              cal.accountName?.toLowerCase().contains('icloud') == true,
          orElse: () => Calendar(),
        );
        if (amicoipetCalendar.id != null) {
          devLog('選擇行事曆', '使用 icloud 預設行事曆: ${amicoipetCalendar.name}');
          return amicoipetCalendar.id;
        }
      }

      return _calendars.first.id;
    }
    return null;

    // 優先順序 1: Google 主帳號的預設行事曆 (Android 最佳)
    // final googleDefault = _calendars.firstWhere(
    //   (cal) =>
    //       cal.isDefault == true &&
    //       cal.accountType?.toLowerCase().contains('google') == true,
    //   orElse: () => Calendar(),
    // );
    // if (googleDefault.id != null) {
    //   devLog('選擇行事曆', '使用 Google 預設行事曆: ${googleDefault.name}');
    //   return googleDefault.id;
    // }

    // // 優先順序 2: iCloud 預設行事曆 (iOS 最佳)
    // final iCloudDefault = _calendars.firstWhere(
    //   (cal) =>
    //       cal.isDefault == true &&
    //       cal.accountName?.toLowerCase().contains('icloud') == true,
    //   orElse: () => Calendar(),
    // );
    // if (iCloudDefault.id != null) {
    //   devLog('選擇行事曆', '使用 iCloud 預設行事曆: ${iCloudDefault.name}');
    //   return iCloudDefault.id;
    // }

    // // 優先順序 3: 任何 Google 帳號行事曆
    // final anyGoogle = _calendars.firstWhere(
    //   (cal) =>
    //       cal.accountName?.contains('@gmail.com') == true ||
    //       cal.accountType?.toLowerCase().contains('google') == true,
    //   orElse: () => Calendar(),
    // );
    // if (anyGoogle.id != null) {
    //   devLog('選擇行事曆', '使用 Google 行事曆: ${anyGoogle.name}');
    //   return anyGoogle.id;
    // }

    // // 優先順序 4: 任何 iCloud 行事曆
    // final anyICloud = _calendars.firstWhere(
    //   (cal) => cal.accountName?.toLowerCase().contains('icloud') == true,
    //   orElse: () => Calendar(),
    // );
    // if (anyICloud.id != null) {
    //   devLog('選擇行事曆', '使用 iCloud 行事曆: ${anyICloud.name}');
    //   return anyICloud.id;
    // }

    // // 優先順序 5: 第一個標記為預設的
    // final firstDefault = _calendars.firstWhere(
    //   (cal) => cal.isDefault == true,
    //   orElse: () => Calendar(),
    // );
    // if (firstDefault.id != null) {
    //   devLog('選擇行事曆', '使用預設行事曆: ${firstDefault.name}');
    //   return firstDefault.id;
    // }
  }

  // 從你的自訂日曆同步事件到系統行事曆
  Future<void> _syncEventToSystemCalendar({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    int? reminderMinutes,
  }) async {
    if (_selectedCalendarId == null) {
      devLog('同步事件', '錯誤：未選擇行事曆');
      return;
    }

    final eventToAdd = Event(
      _selectedCalendarId,
      title: title,
      description: description,
      start: tz.TZDateTime.from(startTime, tz.local),
      end: tz.TZDateTime.from(endTime, tz.local),
      // ⭐ 重點：加入提醒通知
      reminders: [
        Reminder(
          minutes: reminderMinutes,
        ), // 預設提前 10 分鐘
      ],
    );

    final createEventResult = await _deviceCalendarPlugin.createOrUpdateEvent(
      eventToAdd,
    );

    if (createEventResult?.isSuccess == true) {
      devLog('同步事件', '事件已同步到系統行事曆，會在 $reminderMinutes 分鐘前提醒');
      _fetchEvents(); // 同步後，更新事件列表
    } else {
      devLog('同步事件', '同步失敗: ${createEventResult?.errors}');
    }
  }

  // 使用者在你的 APP 中建立了一個計劃
  void onUserCreatePlan() {
    final now = DateTime.now();
    _syncEventToSystemCalendar(
      title: '重要會議',
      description: '與客戶討論專案進度',
      startTime: DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ), // 2025/10/5 下午2點
      endTime: DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute + 2,
      ), // 下午3點
      reminderMinutes: 1, // 提前 1 分鐘通知
    );
  }

  Future<void> createCalendar() async {
    // 建立一個新的行事曆
    final newCalendar = Calendar(
      name: calendarName,
      accountName: 'AmicoiPet',
      //accountType: 'GOOGLE', // 或 'GOOGLE'，視需求而定
      // color: Colors.amber, // 使用顏色的 int 值
    );

    final createResult = await _deviceCalendarPlugin.createCalendar(
      newCalendar.name,
      calendarColor: Colors.amber,
      localAccountName: newCalendar.accountName,
    );

    if (createResult.isSuccess && createResult.data != null) {
      devLog('建立行事曆', '行事曆建立成功，ID: ${createResult.data}');

      setState(() {
        createResultID = createResult.data;
      });

      // 重新載入行事曆列表
      _fetchCalendarsAndEvents();
    } else {
      devLog('建立行事曆', '建立行事曆失敗: ${createResult.errors}');
    }
  }

  Future<void> deleteCalendar() async {
    if (_selectedCalendar?.name != 'AmicoiPet' &&
        _selectedCalendar?.accountName != 'AmicoiPet') {
      devLog('刪除行事曆', '只能刪除 AmicoiPet 行事曆');
      return;
    }
    final deleteResult = await _deviceCalendarPlugin.deleteCalendar(
      _selectedCalendarId!,
    );

    if (deleteResult.isSuccess) {
      devLog('刪除行事曆', '行事曆刪除成功');
      // 重新載入行事曆列表
      _fetchCalendarsAndEvents();
    } else {
      devLog('刪除行事曆', '刪除行事曆失敗: ${deleteResult.errors}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('行事曆 CRUD 範例'),
        actions: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.refresh),
                onPressed: _fetchEvents, //_addEvent,
              ),
              IconButton(
                icon: Icon(Icons.add),
                onPressed: onUserCreatePlan, //_addEvent,
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: createCalendar,
                child: Text('建立行事曆'),
              ),
              TextButton(
                onPressed: deleteCalendar,
                child: Text('刪除行事曆'),
              ),
            ],
          ),

          if (_calendars.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: DropdownButton<String>(
                value: _selectedCalendarId,
                isExpanded: true,
                items: _calendars.map((cal) {
                  return DropdownMenuItem(
                    value: cal.id,
                    child: Text(cal.name ?? '未命名行事曆'),
                  );
                }).toList(),
                onChanged: (value) {
                  // 在 onChanged 或選擇行事曆後
                  setState(() {
                    _selectedCalendarId = value;
                    _selectedCalendarName = _calendars
                        .firstWhere((cal) => cal.id == value)
                        .name;

                    _selectedCalendar = _calendars.firstWhere(
                      (cal) => cal.id == value,
                    );

                    devLog('選擇行事曆', '當前選擇: $_selectedCalendarId');
                    devLog('選擇行事曆', '當前選擇: $_selectedCalendarName');
                    final cal = _selectedCalendar;
                    if (cal != null) {
                      final calMap = {
                        'id': cal.id,
                        'name': cal.name,
                        'accountName': cal.accountName,
                        'accountType': cal.accountType,
                        'isDefault': cal.isDefault,
                        'isReadOnly': cal.isReadOnly,
                      };
                      devLog('選擇行事曆', '當前選擇: ${jsonEncode(calMap)}');
                    } else {
                      devLog('選擇行事曆', '當前選擇: null');
                    }
                    _fetchEvents(); // 切換行事曆後，重新讀取事件
                  });
                },
              ),
            ),
          Expanded(
            child: _events.isEmpty
                ? Center(child: Text('今天沒有事件'))
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      // 格式化時間顯示
                      String formatEventTime(tz.TZDateTime? dateTime) {
                        if (dateTime == null) return '未設定時間';

                        // 不需要 .toLocal()，TZDateTime 已經包含時區資訊
                        // DateFormat 會自動使用 Intl.defaultLocale（由系統決定）
                        final formatter = DateFormat('MM/dd HH:mm');
                        return formatter.format(dateTime);
                      }

                      return ListTile(
                        title: Text(event.title ?? '無標題'),
                        subtitle: Text(
                          '${formatEventTime(event.start)} - ${formatEventTime(event.end)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _modifyEvent(event),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteEvent(event.eventId),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
