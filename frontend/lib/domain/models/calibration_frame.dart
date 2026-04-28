import 'dart:convert';
import 'dart:typed_data';

class CalibrationFrame {
  final String imageBase64;
  final int width;
  final int height;

  CalibrationFrame({
    required this.imageBase64,
    required this.width,
    required this.height,
  });

  Uint8List get bytes => base64Decode(imageBase64);

  factory CalibrationFrame.fromJson(Map<String, dynamic> json) {
    return CalibrationFrame(
      imageBase64: json['image_base64']?.toString() ?? '',
      width: _toInt(json['width']),
      height: _toInt(json['height']),
    );
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
