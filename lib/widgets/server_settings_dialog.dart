import 'package:flutter/material.dart';
import 'package:invoiso/l10n/app_localizations.dart';
import 'package:invoiso/services/server/server_connection.dart';
import 'package:invoiso_core/rpc/rpc_client.dart';

/// Lets the user point the app at their invoiso server (Railway, docker
/// compose on a LAN box, …). Returns the saved base URL, or null when
/// cancelled. Reachable from the login screen so it works before signing in.
Future<String?> showServerSettingsDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _ServerSettingsDialog(),
  );
}

class _ServerSettingsDialog extends StatefulWidget {
  const _ServerSettingsDialog();

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

enum _TestState { idle, testing, ok, failed }

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  final _controller = TextEditingController();
  _TestState _state = _TestState.idle;
  String _detail = '';

  @override
  void initState() {
    super.initState();
    ServerSettings.load().then((url) {
      if (mounted) setState(() => _controller.text = url);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final url = ServerSettings.normalize(_controller.text);
    if (url.isEmpty) return;
    setState(() => _state = _TestState.testing);
    try {
      final version = await ServerConnection(url).health();
      if (!mounted) return;
      setState(() {
        _state = _TestState.ok;
        _detail = version;
      });
    } on RpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _TestState.failed;
        _detail = e.message;
      });
    }
  }

  Future<void> _save() async {
    final url = ServerSettings.normalize(_controller.text);
    if (url.isEmpty) return;
    await ServerSettings.save(url);
    if (mounted) Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.serverSettingsTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.serverSettingsHelp,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.serverSettingsUrlLabel,
                hintText: l10n.serverSettingsUrlHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _state = _TestState.idle),
              onSubmitted: (_) => _test(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _state == _TestState.testing ? null : _test,
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(l10n.serverSettingsTestButton),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: switch (_state) {
                    _TestState.idle => const SizedBox.shrink(),
                    _TestState.testing => Text(l10n.serverSettingsTesting),
                    _TestState.ok => Text(l10n.serverSettingsConnected(_detail),
                        style: TextStyle(color: Colors.green.shade700)),
                    _TestState.failed => Text(l10n.serverSettingsFailed(_detail),
                        style: TextStyle(color: scheme.error)),
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.actionSave)),
      ],
    );
  }
}
