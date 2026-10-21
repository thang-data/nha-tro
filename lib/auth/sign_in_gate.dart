import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'access.dart';

/// Chặn toàn bộ app cho tới khi đăng nhập Google và được cấp quyền.
class SignInGate extends StatelessWidget {
  const SignInGate({super.key, required this.signedInBuilder});

  final WidgetBuilder signedInBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          setCurrentAccess(null);
          return const _SignInScreen();
        }
        return _AccessCheck(
          key: ValueKey(user.uid),
          user: user,
          signedInBuilder: signedInBuilder,
        );
      },
    );
  }
}

class _AccessCheck extends StatefulWidget {
  const _AccessCheck({
    super.key,
    required this.user,
    required this.signedInBuilder,
  });

  final User user;
  final WidgetBuilder signedInBuilder;

  @override
  State<_AccessCheck> createState() => _AccessCheckState();
}

class _AccessCheckState extends State<_AccessCheck> {
  late Future<AccessProfile?> _future;

  @override
  void initState() {
    super.initState();
    _future = loadAccess(widget.user);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccessProfile?>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return _MessageScreen(
            message: 'Không kiểm tra được quyền: ${snap.error}',
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final access = snap.data;
        if (access == null) {
          setCurrentAccess(null);
          return _MessageScreen(
            message:
                'Tài khoản ${widget.user.email ?? ''} chưa được cấp quyền. '
                'Nhờ admin thêm email này vào danh sách thành viên.',
          );
        }
        setCurrentAccess(access);
        return widget.signedInBuilder(context);
      },
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: const [LogoutButton()]),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// Đăng xuất để đổi sang tài khoản Google khác.
class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Đăng xuất',
      icon: const Icon(Icons.logout),
      onPressed: () => FirebaseAuth.instance.signOut(),
    );
  }
}

class _SignInScreen extends StatefulWidget {
  const _SignInScreen();

  @override
  State<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<_SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // select_account: luôn hiện danh sách tài khoản để chọn đúng email.
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      await FirebaseAuth.instance.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Quản lý nhà trọ',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _signIn,
                icon: const Icon(Icons.login),
                label: const Text('Đăng nhập bằng Google'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
