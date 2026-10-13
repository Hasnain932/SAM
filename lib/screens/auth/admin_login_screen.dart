part of '../../main.dart';

// Admin login.

// Admin login screen
// Admins sign in with an email, or with a username for the second admin.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  static const String _noInternetMsg =
      "Internet connection is required to log in. Please check your connection and try again.";

  Future<void> _submit() async {
    final id = _idController.text.trim();
    final password = _passwordController.text.trim();

    if (id.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = "Both fields are required");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (id.contains('@')) {
        // ---- First admin: Firebase email/password ----
        if (_isLogin || !kAllowAdminSignUp) {
          await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: id, password: password)
              .timeout(const Duration(seconds: 10));
        } else {
          await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: id, password: password)
              .timeout(const Duration(seconds: 10));
        }
        await AppSession.clearForFirebaseAdmin();
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        // ---- Second admin: username/password from departments ----
        final ok = await _checkHiddenAdmin(id, password);
        if (ok) {
          await AppSession.loginHiddenAdmin();
          if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        } else {
          setState(() => _errorMessage = "Incorrect username or password");
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? "Something went wrong");
    } on TimeoutException {
      setState(() => _errorMessage = _noInternetMsg);
    } catch (e) {
      setState(() => _errorMessage = _noInternetMsg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkHiddenAdmin(String username, String password) async {
    if (username != kHiddenAdminUsername) return false;
    final snap = await safeGetQuery(FirebaseFirestore.instance
        .collection('departments')
        .where('username', isEqualTo: username));
    for (final d in snap.docs) {
      if ((d.data()['password'] ?? '').toString() == password) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showToggle = kAllowAdminSignUp;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const IconBadge(
                  icon: Icons.admin_panel_settings_outlined, size: 72),
              const SizedBox(height: 16),
              Text(
                _isLogin ? 'Admin Login' : 'Create Admin Account',
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _idController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email or username',
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
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: kAbsent),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: kOnAccent, strokeWidth: 2),
                        )
                      : Text(
                          _isLogin ? 'Login' : 'Sign Up',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
              if (showToggle) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = null;
                  }),
                  child: Text(_isLogin
                      ? "Don't have an account? Sign up"
                      : "Already have an account? Login"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
