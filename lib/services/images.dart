import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked images into the app's documents dir so they survive cache clears.
Future<String> persistImage(XFile f) async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'media'))
    ..createSync(recursive: true);
  final dest = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}${p.extension(f.path)}');
  await File(f.path).copy(dest);
  return dest;
}

final _picker = ImagePicker();

Future<String?> pickImage({required bool camera}) async {
  final x = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 2000, imageQuality: 85);
  return x == null ? null : persistImage(x);
}

Future<List<String>> pickMany() async {
  final xs = await _picker.pickMultiImage(maxWidth: 2000, imageQuality: 85);
  return [for (final x in xs) await persistImage(x)];
}
