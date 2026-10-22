// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — OAuth consent screen.
//
// Displays the OAuth client name, requested scopes, and asks the user
// to approve or deny the authorization. When a consent flow is detected
// (consent_flow param set by Sentin8:Auth's authorize redirect), the
// consent screen fetches the RFW consent page definition from the
// vertical service that owns the consent flow (via /v1/auth/consent/ui).
// For the platform-default consent (OIDC standard scopes only), a
// simple approve/deny is shown with no vertical knowledge.
// See sentin8-architecture-principles.md §4.16.
import 'package:web/web.dart' as web;
import '../test_bridge.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../branding_provider.dart';
import '../api.dart';

class ConsentPage extends StatefulWidget {
  final String? clientId;
  final String? clientName;
  final String? redirectUri;
  final String? state;
  final String? scope;
  final String? userId;
  final String? sessionToken;
  final String? codeChallenge;
  final String? consentFlow;
  // OIDC Core §3.1.2.1 protocol params forwarded from the sign-in page
  // (the authorize request's context - the consent screen completes the
  // SAME request: nonce in the ID token, JARM response_mode, the §5.5
  // claims selection, acr_values, the RFC 8707 resource indicator, the
  // RFC 9449 pre-bound dpop_jkt).
  final String? nonce;
  final String? responseMode;
  final String? claims;
  final String? acrValues;
  final String? resource;
  final String? dpopJkt;

  const ConsentPage({
    super.key,
    this.clientId,
    this.clientName,
    this.redirectUri,
    this.state,
    this.scope,
    this.userId,
    this.sessionToken,
    this.codeChallenge,
    this.consentFlow,
    this.nonce,
    this.responseMode,
    this.claims,
    this.acrValues,
    this.resource,
    this.dpopJkt,
  });

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _isLoading = false;
  bool _accountsLoading = false;
  List<Map<String, dynamic>> _accounts = [];
  Set<String> _selectedAccountIds = {};

  List<String> get _scopes {
    final s = widget.scope ?? '';
    return s.split(' ').where((s) => s.isNotEmpty).toList();
  }

  // Whether this is a consent flow that requires account selection.
  // Determined by the presence of a `consent_flow` query param (set by
  // Sentin8:Auth's authorize redirect when a consent flow matches).
  // The platform-default consent page (no consent_flow) shows only OIDC
  // standard scopes — no vertical knowledge needed.
  bool get _hasConsentFlow => widget.consentFlow != null && widget.consentFlow!.isNotEmpty;

  // OIDC standard scope descriptions — these are platform-builtin (OIDC spec,
  // not vertical-specific). All other scope descriptions come from the
  // vertical service's RFW consent page definition (fetched via
  // GET /v1/auth/consent/ui). For the platform-default consent page (no
  // consent flow), only OIDC standard scopes are shown.
  String _scopeDescription(String scope) => switch (scope) {
    'openid' => 'Verify your identity',
    'profile' => 'Read your profile information',
    'email' => 'Read your email address',
    'offline_access' => 'Maintain access when you are offline',
    _ => scope, // Non-OIDC scopes are described by the RFW consent page
  };

  IconData _scopeIcon(String scope) => switch (scope) {
    'openid' => Icons.verified_user_outlined,
    'profile' => Icons.person_outline,
    'email' => Icons.email_outlined,
    'offline_access' => Icons.access_time_outlined,
    _ => Icons.circle_outlined,
  };

  @override
  void initState() {
    super.initState();
    // Account selection is triggered when a consent flow is present
    // (the vertical service's RFW consent page declares whether account
    // selection is needed). For now, we fetch accounts if a consent_flow
    // is present and user/session tokens are available.
    if (_hasConsentFlow && widget.userId != null && widget.sessionToken != null) {
      _fetchAccounts();
    }
    // E2E/bridge: the approval + deny buttons are driven through the
    // SAME widget methods the clicks use (the certification rig drives
    // the consent screen - approve AND the user-rejects DENY path).
    setConsentHandlers(
      approve: _approve,
      deny: _deny,
    );
  }

  Future<void> _fetchAccounts() async {
    setState(() => _accountsLoading = true);
    try {
      final api = AuthApi(baseUrl: '');
      final accounts = await api.fetchConsentAccounts(
        userId: widget.userId!,
        sessionToken: widget.sessionToken!,
      );
      setState(() {
        _accounts = accounts;
        // Pre-select all accounts by default (FDX UX §3.1.6: "provide a
        // quick way to select or deselect all accounts to be shared").
        _selectedAccountIds = accounts.map((a) {
          final id = a['id']?.toString() ?? a['accountId']?.toString() ?? '';
          return id;
        }).where((id) => id.isNotEmpty).toSet();
      });
    } catch (_) {
      // Non-fatal — the customer can still approve without selecting accounts.
    } finally {
      if (mounted) setState(() => _accountsLoading = false);
    }
  }

  void _toggleAccount(String accountId) {
    setState(() {
      if (_selectedAccountIds.contains(accountId)) {
        _selectedAccountIds.remove(accountId);
      } else {
        _selectedAccountIds.add(accountId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedAccountIds = _accounts.map((a) {
        final id = a['id']?.toString() ?? a['accountId']?.toString() ?? '';
        return id;
      }).where((id) => id.isNotEmpty).toSet();
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedAccountIds.clear();
    });
  }

  Future<void> _approve() async {
    setState(() => _isLoading = true);
    try {
      // Call /oauth/authorize/continue to issue the authorization code
      // (same as the sign-in page does). The session token from sign-in
      // authenticates the request. The selected account IDs are forwarded
      // so the FDX callback can persist them as consent resources.
      final api = AuthApi(baseUrl: '');
      final redirectUrl = await api.authorizeContinue(
        clientId: widget.clientId ?? '',
        redirectUri: widget.redirectUri ?? '',
        scope: widget.scope ?? 'openid profile email',
        state: widget.state ?? '',
        codeChallenge: widget.codeChallenge,
        userId: widget.userId ?? '',
        sessionToken: widget.sessionToken ?? '',
        selectedAccountIds: _selectedAccountIds.toList(),
        nonce: widget.nonce,
        responseMode: widget.responseMode,
        claims: widget.claims,
        acrValues: widget.acrValues,
        resource: widget.resource,
        dpopJkt: widget.dpopJkt,
      );
      // Redirect the browser to the callback URL (FDX consent callback).
      web.window.location.href = redirectUrl;
    } catch (e) {
      // Fallback: redirect to /oauth/authorize (may fail if PAR required)
      final params = <String, String>{
        'client_id': widget.clientId ?? '',
        'redirect_uri': widget.redirectUri ?? '',
        'response_type': 'code',
        'state': widget.state ?? '',
        'scope': widget.scope ?? 'openid profile email',
        'consent': 'granted',
      };
      final qs = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      web.window.location.href = '/oauth/authorize?${qs.toString()}';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _deny() {
    // Deny through the AUTH surface: authorize/continue with deny=true
    // - auth redirects back with error=access_denied + state (+ iss
    // under require_iss) from the SAME code path the approval uses, so
    // the client sees a consistent error redirect (the suite's
    // user-rejects module checks the redirect's parameters).
    final userId = widget.userId ?? '';
    final sessionToken = widget.sessionToken ?? '';
    if (userId.isNotEmpty && sessionToken.isNotEmpty) {
      _denyThroughAuth(userId, sessionToken);
      return;
    }
    // No session yet (deny before sign-in completed) - the client-side
    // fallback redirect stands (the params are already known).
    final redirectUri = widget.redirectUri ?? '';
    final state = widget.state ?? '';
    if (redirectUri.isNotEmpty) {
      web.window.location.href = '$redirectUri?error=access_denied&state=$state';
    } else {
      web.window.location.href = '/sign-in';
    }
  }

  Future<void> _denyThroughAuth(String userId, String sessionToken) async {
    setState(() => _isLoading = true);
    try {
      final api = AuthApi(baseUrl: '');
      final redirectUrl = await api.authorizeContinue(
        clientId: widget.clientId ?? '',
        redirectUri: widget.redirectUri ?? '',
        scope: widget.scope ?? 'openid profile email',
        state: widget.state ?? '',
        codeChallenge: widget.codeChallenge,
        userId: userId,
        sessionToken: sessionToken,
        selectedAccountIds: const [],
        nonce: widget.nonce,
        responseMode: widget.responseMode,
        claims: widget.claims,
        acrValues: widget.acrValues,
        resource: widget.resource,
        dpopJkt: widget.dpopJkt,
        deny: true,
      );
      web.window.location.href = redirectUrl;
    } catch (_) {
      // Fall back to the client-side error redirect.
      final redirectUri = widget.redirectUri ?? '';
      final state = widget.state ?? '';
      if (redirectUri.isNotEmpty) {
        web.window.location.href = '$redirectUri?error=access_denied&state=$state';
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassPanel(
        maxWidth: 520,
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Sentin8Logo(size: 32, logoUrl: BrandingProvider.of(context).logoUrl, logoIconUrl: BrandingProvider.of(context).logoIconUrl),
              const SizedBox(height: Sentin8Spacing.lg),
              Text('Authorize Application', style: h2For(context), textAlign: TextAlign.center),
              const SizedBox(height: Sentin8Spacing.sm),
              Text('${widget.clientName ?? widget.clientId ?? 'An application'} is requesting access to your account.',
                  style: bodySecondaryFor(context), textAlign: TextAlign.center),
              const SizedBox(height: Sentin8Spacing.xl),
              // Scope list
              Container(
                padding: const EdgeInsets.all(Sentin8Spacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(Sentin8Radii.medium),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This application will be able to:', style: labelFor(context)),
                    const SizedBox(height: Sentin8Spacing.sm),
                    ..._scopes.map((scope) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(_scopeIcon(scope), color: Theme.of(context).colorScheme.primary, size: 20),
                          const SizedBox(width: Sentin8Spacing.sm),
                          Expanded(child: Text(_scopeDescription(scope), style: bodyFor(context))),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              // Account selection (FDX UX Guidelines §3.1.6 "Select Accounts")
              if (_hasConsentFlow) ...[
                const SizedBox(height: Sentin8Spacing.xl),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Theme.of(context).colorScheme.primary, size: 20),
                    const SizedBox(width: Sentin8Spacing.sm),
                    Expanded(child: Text('Select accounts to share', style: labelFor(context))),
                    TextButton(onPressed: _selectAll, child: const Text('All', style: TextStyle(fontSize: 12))),
                    TextButton(onPressed: _deselectAll, child: const Text('None', style: TextStyle(fontSize: 12))),
                  ],
                ),
                const SizedBox(height: Sentin8Spacing.sm),
                if (_accountsLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sentin8Spacing.lg),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary))),
                  )
                else if (_accounts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(Sentin8Spacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(Sentin8Radii.medium),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Text('No accounts available at this provider.', style: captionFor(context)),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(Sentin8Radii.medium),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _accounts.length,
                      itemBuilder: (context, index) {
                        final a = _accounts[index];
                        final id = a['id']?.toString() ?? a['accountId']?.toString() ?? '';
                        final name = a['nickname']?.toString() ?? a['name']?.toString() ?? 'Account';
                        final type = a['accountType']?.toString() ?? a['accountCategory']?.toString() ?? '';
                        final balance = a['currentBalance'] ?? a['balance'] ?? 0;
                        final masked = a['accountNumberDisplay']?.toString() ?? a['maskedAccountNumber']?.toString() ?? '';
                        final selected = _selectedAccountIds.contains(id);
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (_) => _toggleAccount(id),
                          dense: true,
                          title: Text(name, style: bodyFor(context)),
                          subtitle: Text(
                            [if (type.isNotEmpty) type, if (masked.isNotEmpty) masked].join(' • '),
                            style: captionFor(context),
                          ),
                          secondary: Text(
                            '\$${(balance is num ? balance.toDouble() : 0.0).toStringAsFixed(2)}',
                            style: bodyFor(context),
                          ),
                        );
                      },
                    ),
                  ),
              ],
              const SizedBox(height: Sentin8Spacing.xl),
              // Approve / Deny buttons
              FilledButton(
                onPressed: _isLoading ? null : _approve,
                child: _isLoading
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                    : const Text('Authorize'),
              ),
              const SizedBox(height: Sentin8Spacing.md),
              OutlinedButton(onPressed: _deny, child: const Text('Deny')),
              const SizedBox(height: Sentin8Spacing.lg),
              Text('By authorizing, you allow this application to access the listed resources on your behalf. You can revoke this at any time.',
                  style: captionFor(context), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}