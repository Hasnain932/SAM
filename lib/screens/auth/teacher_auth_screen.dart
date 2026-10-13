part of '../../main.dart';

// Teacher login and sign up.

// Teacher login / sign up
// Stored at teachers/{username}: name, username, password, status.
// New sign-ups start as 'pending' and need admin approval.
class TeacherAuthScreen extends StatefulWidget {
  const TeacherAuthScreen({super.key});

  @override
  State<TeacherAuthScreen> createState() => _TeacherAuthScreenState();
}

class _TeacherAuthScreenState extends State<TeacherAuthScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(username)) {
      setState(() => _error =
          'Username can only contain letters, numbers, dots, dashes or underscores');
      return;
    }

    final id = username.toLowerCase();
    final ref = FirebaseFirestore.instance.collection('teachers').doc(id);

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final snap = await safeGetDocOrNull(ref);
      final exists = snap != null && snap.exists;

      if (_isLogin) {
        if (!exists) {
          setState(() => _error = 'Account not found. Please sign up first.');
          return;
        }
        final data = snap.data() ?? {};
        if ((data['password'] ?? '').toString() != password) {
          setState(() => _error = 'Incorrect username or password');
          return;
        }
        // Approval is checked only at login. After approval, the saved local session
        // is used and the server is never asked again. Accounts with no status
        // (created before this feature) count as approved.
        final status = teacherStatusOf(data);
        if (status == 'pending') {
          setState(() =>
              _error = 'Your account is waiting for admin approval.');
          return;
        }
        if (status == 'denied') {
          setState(() =>
              _error = 'Your account request was rejected by the admin.');
          return;
        }
        final tName = (data['name'] ?? username).toString();
        unawaited(LocalDb.upsertTeacher(id, tName, username));
        await AppSession.loginTeacher(id, tName);
      } else {
        if (exists) {
          setState(() => _error = 'This username is already taken');
          return;
        }
        // Not awaited: set() does not complete while offline.
        unawaited(ref.set({
          'name': name,
          'username': username,
          'password': password,
          'status': 'pending',
        }).catchError((_) {}));
        // No auto login: the admin has to approve the account first.
        if (mounted) {
          setState(() {
            _isLogin = true;
            _passwordController.clear();
            _error = null;
          });
          showSnack(context,
              'Account created. You can log in after the admin approves it.');
        }
        return;
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      setState(() => _error =
          'No saved data on this device. Please try once with an internet connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const IconBadge(icon: Icons.person_outline, size: 72),
              const SizedBox(height: 16),
              Text(_isLogin ? 'Teacher Login' : 'Teacher Sign Up',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 24),
              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kAbsent)),
                ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: kOnAccent, strokeWidth: 2))
                      : Text(_isLogin ? 'Login' : 'Create Account',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _isLogin = !_isLogin;
                  _error = null;
                }),
                child: Text(_isLogin
                    ? "New teacher? Sign up"
                    : "Already have an account? Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
