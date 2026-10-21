import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Giới hạn dung lượng ảnh sau nén. Ảnh base64 phải nằm trong một document Firestore (tối đa 1 MiB).
const int maxPhotoBytes = 600 * 1024;

/// Số ảnh tối đa cho mỗi lần chụp/chọn (kiểm tra phòng, thanh lý).
const int maxPhotosPerKind = 5;

/// Nén ảnh thành JPEG cạnh dài tối đa vài nghìn px, giảm dần chất lượng cho đến khi dưới [maxPhotoBytes].
/// Trả về null nếu không đọc được ảnh hoặc không nén đủ nhỏ.
Uint8List? compressPhoto(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  final landscape = decoded.width >= decoded.height;
  for (final (side, quality) in const [(1280, 75), (960, 65), (800, 55)]) {
    final resized = (decoded.width > side || decoded.height > side)
        ? img.copyResize(
            decoded,
            width: landscape ? side : null,
            height: landscape ? null : side,
          )
        : decoded;
    final out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    if (out.length <= maxPhotoBytes) return out;
  }
  return null;
}
