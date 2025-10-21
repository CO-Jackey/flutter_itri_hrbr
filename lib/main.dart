import 'package:device_calendar/device_calendar.dart' as tz;
import 'package:flutter/material.dart';
import 'package:flutter_itri_hrbr/muti_view_mac_page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_itri_hrbr/broadcast_mac_page.dart';
import 'package:flutter_itri_hrbr/data_match_page.dart';
import 'package:flutter_itri_hrbr/muti_mac_page.dart';
import 'package:flutter_itri_hrbr/normal_data_page.dart';
import 'package:flutter_itri_hrbr/widget/device_calendar_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日期格式（支援所有 locale）
  await initializeDateFormatting();

  // 初始化時區資料庫
  tz.initializeTimeZones();

  // ⭐ 自動使用系統時區（不需要手動取得字串）
  // tz.local 會依據系統自動判斷，但若要強制設定為系統時區名稱：
  final systemOffset = DateTime.now().timeZoneOffset;
  final localName = DateTime.now().timeZoneName; // 例如 "GMT+8" 或 "CST"

  // 若你的裝置系統時區是標準名稱（如 "Asia/Taipei"），可直接用：
  tz.setLocalLocation(tz.getLocation('Asia/Taipei'));
  // 但為了完全跟隨系統，最簡單是讓 tz.local 自己判斷（預設已正確）

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Material App',
      // 跟隨系統語言與地區
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'TW'),
        Locale('zh', 'CN'),
        Locale('ja'),
        // 加上你需要的其他語言
      ],
      // 不設定 locale 會自動跟隨系統
      home: const ChoosePage(),
    );
  }
}

class ChoosePage extends StatelessWidget {
  const ChoosePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Page'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NormalDataPage(),
                  ),
                );
              },
              child: const Text('一般資料頁面'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DataMatchPage(),
                  ),
                );
              },
              child: const Text('分類資料頁面'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MutiMacPage(),
                  ),
                );
              },
              child: const Text('一連多測試資料頁面'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BroadcastTestPage(),
                  ),
                );
              },
              child: const Text('廣播測試資料頁面'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CalendarCrudExample(),
                  ),
                );
              },
              child: const Text('行事曆範例'),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PetMonitorSimplePage(),
                  ),
                );
              },
              child: const Text('多寵物監控簡易頁面'),
            ),
          ],
        ),
      ),
    );
  }
}
