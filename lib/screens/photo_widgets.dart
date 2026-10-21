import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/image_compress.dart';

/// Chọn một ảnh từ máy rồi nén. Trả về null nếu người dùng hủy hoặc ảnh không hợp lệ.
Future<Uint8List?> pickCompressedPhoto(BuildContext context) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
  );
  if (file == null) return null;
  final compressed = compressPhoto(await file.readAsBytes());
  if (compressed == null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Không đọc được ảnh này, vui lòng chọn ảnh khác'),
      ),
    );
  }
  return compressed;
}

/// Dãy ảnh đã chọn (chưa lưu): xem, xóa và thêm tối đa [max] ảnh.
class PhotoPickerStrip extends StatelessWidget {
  const PhotoPickerStrip({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onRemove,
    this.max = maxPhotosPerKind,
  });

  final List<Uint8List> photos;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < photos.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  photos[i],
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filledTonal(
                  tooltip: 'Xóa ảnh',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => onRemove(i),
                ),
              ),
            ],
          ),
        if (photos.length < max)
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text('Thêm ảnh (${photos.length}/$max)'),
          ),
      ],
    );
  }
}

/// Hiển thị ảnh đã lưu trong Firestore (base64) dạng ô vuông nhỏ.
class SavedPhotoStrip extends StatelessWidget {
  const SavedPhotoStrip({super.key, required this.data});

  /// Danh sách base64 của các ảnh.
  final List<String> data;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in data)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              base64Decode(d),
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
      ],
    );
  }
}
