import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:invoiso/services/server/app_server.dart';
import 'package:invoiso/widgets/server_settings_dialog.dart';
import 'package:invoiso_core/rpc/rpc_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Server mode's replacement for the local Backup screen: data lives in the
/// server's Postgres (backed up there), and this is where a desktop
/// install's existing data is uploaded once as a new company.
class ServerDataScreen extends StatefulWidget {
  const ServerDataScreen({super.key});

  @override
  State<ServerDataScreen> createState() => _ServerDataScreenState();
}

class _ServerDataScreenState extends State<ServerDataScreen> {
  List<File> _localDbs = [];
  bool _busy = false;
  String? _result;

  @override
  void initState() {
    super.initState();
    _findLocalDatabases();
  }

  /// The desktop app kept each company in `invoice_manager*.db` under the
  /// application-support folder.
  Future<void> _findLocalDatabases() async {
    final dir = await getApplicationSupportDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('invoice_manager') &&
            f.path.endsWith('.db'))
        .toList();
    if (mounted) setState(() => _localDbs = files);
  }

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose an invoiso database (.db)',
      type: FileType.any,
    );
    final path = picked?.files.single.path;
    if (path != null) await _upload(File(path));
  }

  Future<void> _upload(File file) async {
    final nameController = TextEditingController(
        text: 'Imported ${p.basenameWithoutExtension(file.path)}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload to server'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${p.basename(file.path)} '
                  '(${(file.lengthSync() / 1024).toStringAsFixed(0)} KB) will be '
                  'added to the server as a new company. Its users and '
                  'passwords come with it. The file on this computer is not '
                  'changed.'),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Company name on the server',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
              child: const Text('Upload')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final rows = await AppServer.connection
          .importDatabase(name, await file.readAsBytes());
      final summary = rows.entries
          .where((e) => e.value > 0 && !e.key.startsWith('_'))
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      setState(() => _result =
          'Uploaded as "$name". Log out and pick it on the login screen. ($summary)');
    } on RpcException catch (e) {
      setState(() => _result = 'Upload failed: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Server & data')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Connected server'),
              subtitle: Text(AppServer.connection.baseUrl),
              trailing: TextButton(
                onPressed: () => showServerSettingsDialog(context),
                child: const Text('Change'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Your data is stored in the server\'s Postgres database, so '
                'backups are taken there (Railway: enable backups on the '
                'Postgres service; docker compose: back up the "pgdata" '
                'volume, e.g. with pg_dump). Nothing is stored on this '
                'computer.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Move desktop data to the server', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Upload a database from the offline desktop app as a new company '
              '(admin only). Do this once per company.'),
          const SizedBox(height: 12),
          for (final f in _localDbs)
            ListTile(
              leading: const Icon(Icons.storage),
              title: Text(p.basename(f.path)),
              subtitle: Text('On this computer · '
                  '${(f.lengthSync() / 1024).toStringAsFixed(0)} KB · '
                  'modified ${f.lastModifiedSync().toLocal().toString().substring(0, 16)}'),
              trailing: FilledButton.tonal(
                onPressed: _busy ? null : () => _upload(f),
                child: const Text('Upload'),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose a .db file…'),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(_result!),
          ],
        ],
      ),
    );
  }
}
