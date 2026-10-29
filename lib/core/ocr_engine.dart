import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrLine {
  const OcrLine(this.text, this.box);
  final String text;

  /// Position in image pixels.
  final Rect box;
}

/// On-device text recognition. No image or text leaves the phone.
abstract class OcrEngine {
  Future<List<OcrLine>> recognize(String path);
}

class MlKitOcrEngine implements OcrEngine {
  @override
  Future<List<OcrLine>> recognize(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(path),
      );
      return [
        for (final block in result.blocks)
          for (final line in block.lines) OcrLine(line.text, line.boundingBox),
      ];
    } finally {
      await recognizer.close();
    }
  }
}

/// Text inside [region] (image pixels), in reading order.
String linesText(List<OcrLine> lines, [Rect? region]) => lines
    .where((l) => region == null || region.contains(l.box.center))
    .map((l) => l.text)
    .join('\n');
