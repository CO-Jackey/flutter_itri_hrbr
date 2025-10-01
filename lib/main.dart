import 'package:flutter/material.dart';
import 'package:flutter_itri_hrbr/data_match_page.dart';
import 'package:flutter_itri_hrbr/muti_mac_page.dart';
import 'package:flutter_itri_hrbr/normal_data_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Material App',
      home: ChoosePage(),
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
          ],
        ),
      ),
    );
  }
}
