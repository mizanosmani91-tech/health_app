import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/widgets.dart';

/// EAN-13 / EAN-8 / UPC-A check-digit test, so a blurry misread is ignored instead of creating a wrong product.
bool validProductCode(String c) {
  if (!RegExp(r'^\d+$').hasMatch(c) || ![8, 12, 13].contains(c.length)) return false;
  final d = c.split('').map(int.parse).toList();
  var sum = 0;
  for (var i = 0; i < d.length - 1; i++) {
    final fromRight = d.length - 2 - i; // position counted from the digit before the check digit
    sum += d[i] * (fromRight.isEven ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == d.last;
}

/// Full-screen camera that pops with the first valid product barcode it sees.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _ctrl = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && validProductCode(v)) {
        _done = true;
        Navigator.pop(context, v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black, foregroundColor: Colors.white,
          title: const Text('ওষুধের বারকোড স্ক্যান'),
          actions: [
            IconButton(icon: const Icon(Icons.flash_on), onPressed: _ctrl.toggleTorch, tooltip: 'টর্চ'),
          ],
        ),
        body: Stack(children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
            errorBuilder: (c, e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('ক্যামেরা চালু করা যায়নি। সেটিংসে ক্যামেরার অনুমতি দিন।',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 280, height: 150,
              decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2), borderRadius: BorderRadius.circular(16)),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 40,
            child: Text('প্যাকের বারকোডটি বাক্সের ভেতরে ধরুন', textAlign: TextAlign.center, style: TextStyle(color: context.pal.soft, fontSize: 16)),
          ),
        ]),
      );
}
