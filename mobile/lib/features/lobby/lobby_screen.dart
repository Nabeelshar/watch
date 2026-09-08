import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models.dart';
import '../../data/party_repository.dart';
import '../room/room_model.dart';
import '../room/room_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _client = Supabase.instance.client;
  late final SupabasePartyRepository _repository = SupabasePartyRepository(
    _client,
  );
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _code = TextEditingController();
  StreamSubscription<AuthState>? _auth;
  List<PartyRoom> _rooms = [];
  bool _busy = false, _signUp = false, _recovering = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    _auth = _client.auth.onAuthStateChange.listen((state) {
      if (mounted) {
        setState(() {
          if (state.event == AuthChangeEvent.passwordRecovery) {
            _recovering = true;
          }
        });
        unawaited(_load());
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_client.auth.currentUser == null) return;
    try {
      final name = await _repository.profileName();
      final rooms = await _repository.rooms();
      if (mounted) {
        setState(() {
          if (_name.text.isEmpty) _name.text = name ?? '';
          _rooms = rooms;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _authenticate() => _run(() async {
    if (_email.text.trim().isEmpty || _password.text.length < 8) {
      throw const FormatException(
        'Enter your email and a password of at least 8 characters.',
      );
    }
    if (_signUp) {
      final result = await _client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: 'afterglow://auth-callback/',
      );
      if (result.session == null && mounted) {
        setState(
          () => _notice =
              'Check your email to confirm your account, then sign in.',
        );
      }
    } else {
      await _client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
    _password.clear();
  });
  Future<void> _enter({String? code}) => _run(() async {
    if (_name.text.trim().isEmpty) {
      throw const FormatException('Choose a display name first.');
    }
    await _repository.saveName(_name.text);
    final data = await _repository.command(
      code == null ? 'create' : 'join',
      code == null
          ? {'title': '${_name.text.trim()}’s watch party'}
          : {'code': code},
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomScreen(
          repository: _repository,
          initialRoom: PartyRoom.fromJson(Map<String, dynamic>.from(data)),
          client: _client,
        ),
      ),
    );
    await _load();
  });
  @override
  Widget build(BuildContext context) {
    final signedIn = _client.auth.currentUser != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'afterglow',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -.8),
        ),
        actions: [
          if (signedIn)
            IconButton(
              tooltip: 'Sign out',
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      await _client.auth.signOut();
                      _name.clear();
                      _rooms = [];
                    }),
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                Icon(
                  Icons.nights_stay_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  signedIn
                      ? 'Make tonight a watch party.'
                      : 'Good company.\nGreat watching.',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  signedIn
                      ? 'Choose a video. Invite your people. Stay close.'
                      : 'Watch in sync, chat, and talk with your people.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 36),
                if (_recovering) ...[
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            if (_password.text.length < 8) {
                              throw const FormatException(
                                'Choose a password of at least 8 characters.',
                              );
                            }
                            await _client.auth.updateUser(
                              UserAttributes(password: _password.text),
                            );
                            _password.clear();
                            if (mounted) {
                              setState(() {
                                _recovering = false;
                                _notice = 'Your password has been updated.';
                              });
                            }
                          }),
                    child: const Text('Update password'),
                  ),
                ] else if (!signedIn) ...[
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [
                      _signUp
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    onSubmitted: (_) => _authenticate(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _authenticate,
                    child: Text(
                      _busy
                          ? 'Please wait…'
                          : _signUp
                          ? 'Create account'
                          : 'Sign in',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _signUp = !_signUp),
                    child: Text(
                      _signUp
                          ? 'Already have an account? Sign in'
                          : 'New here? Create an account',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            if (_email.text.trim().isEmpty) {
                              throw const FormatException(
                                'Enter your email first.',
                              );
                            }
                            await _client.auth.resetPasswordForEmail(
                              _email.text.trim(),
                              redirectTo: 'afterglow://auth-callback/',
                            );
                            if (mounted) {
                              setState(
                                () => _notice =
                                    'Password reset instructions have been sent to your email.',
                              );
                            }
                          }),
                    child: const Text('Forgot password?'),
                  ),
                ] else ...[
                  TextField(
                    controller: _name,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Your display name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _enter(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create a room'),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 16,
                    decoration: const InputDecoration(
                      labelText: 'Invitation code',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                    onSubmitted: (value) => _enter(code: value.trim()),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _enter(code: _code.text.trim()),
                    child: const Text('Join a room'),
                  ),
                  if (_rooms.isNotEmpty) ...[
                    const SizedBox(height: 36),
                    Text(
                      'Your rooms',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final room in _rooms)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.movie_outlined),
                        ),
                        title: Text(room.title),
                        subtitle: Text(room.code),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy ? null : () => _enter(code: room.code),
                      ),
                  ],
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_notice!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _auth?.cancel();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }
}
