// Cấu hình Firebase cho web, project nha-49e0d (app nha-tro-web).
// Các giá trị này là định danh công khai của app web, không phải bí mật.
// Bảo mật dữ liệu nằm ở Firestore rules và Authentication, không nằm ở đây.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA-eHu1XZUnCu8Y7jZ5t8mXdlqS6_2nKeY',
    appId: '1:738903729931:web:3607deb152744d669ba40e',
    messagingSenderId: '738903729931',
    projectId: 'nha-49e0d',
    authDomain: 'nha-49e0d.firebaseapp.com',
    storageBucket: 'nha-49e0d.firebasestorage.app',
    measurementId: 'G-TVPQTE4R5S',
  );
}
