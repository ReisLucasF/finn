import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String? notes;
  final String assetName;
  final int? assetId;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.assetName,
    this.notes,
    this.assetId,
  });
}

/// Compara versões semânticas simples (ex.: 1.0.7 vs 1.0.8).
int compareVersions(String a, String b) {
  List<int> parts(String v) {
    final clean =
        v.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    return clean
        .split(RegExp(r'[.+-]'))
        .where((s) => s.isNotEmpty)
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
  }

  final pa = parts(a);
  final pb = parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Repo canônico. Releases existem aqui.
  static const githubOwner = 'ReisLucasF';
  static const githubRepo = 'finan';

  /// Token opcional para repo privado.
  /// Preferência: `--dart-define=GITHUB_UPDATE_TOKEN=...` no build,
  /// ou arquivo `%APPDATA%\Finan\github_token.txt` (pasta mantida do nome antigo).
  static const _tokenFromDefine = String.fromEnvironment('GITHUB_UPDATE_TOKEN');

  Future<String> versaoAtual() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<String> _token() async {
    if (_tokenFromDefine.isNotEmpty) return _tokenFromDefine.trim();
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'github_token.txt'));
      if (await file.exists()) {
        return (await file.readAsString()).trim();
      }
    } catch (_) {}
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        final file = File(p.join(appData, 'Finan', 'github_token.txt'));
        if (await file.exists()) {
          return (await file.readAsString()).trim();
        }
      }
    } catch (_) {}
    return '';
  }

  Map<String, String> _headers({bool forBinary = false}) {
    return {
      'Accept': forBinary
          ? 'application/octet-stream'
          : 'application/vnd.github+json',
      'User-Agent': 'Finn-Updater',
      'X-GitHub-Api-Version': '2022-11-28',
    };
  }

  Future<Map<String, String>> _headersAsync({bool forBinary = false}) async {
    final h = _headers(forBinary: forBinary);
    final token = await _token();
    if (token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  /// Retorna info da release mais nova, ou null se já estiver atualizado / sem tag.
  Future<UpdateInfo?> verificarAtualizacao() async {
    final atual = await versaoAtual();
    final uri = Uri.parse(
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
    );

    final res = await http.get(uri, headers: await _headersAsync());

    if (res.statusCode == 404) {
      final token = await _token();
      if (token.isEmpty) {
        throw Exception(
          'O repositório ReisLucasF/finn é privado. '
          'Este instalador foi gerado sem um token de leitura.',
        );
      }
      throw Exception(
        'O token deste instalador não tem acesso a ReisLucasF/finn. '
        'Crie um PAT fine-grained (owner ReisLucasF, repo finn, '
        'Contents: Read) e gere o instalador de novo.',
      );
    }

    if (res.statusCode != 200) {
      throw Exception(
        'Não foi possível consultar atualizações (HTTP ${res.statusCode}).',
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String? ?? '').trim();
    final remota = tag.replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    if (remota.isEmpty) return null;
    if (compareVersions(remota, atual) <= 0) return null;

    final assets = (json['assets'] as List<dynamic>? ?? []);
    Map<String, dynamic>? setup;
    for (final raw in assets) {
      if (raw is! Map<String, dynamic>) continue;
      final name = (raw['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.exe') &&
          (name.contains('setup') || name.contains('finan'))) {
        setup = raw;
        break;
      }
    }
    if (setup == null) {
      for (final raw in assets) {
        if (raw is! Map<String, dynamic>) continue;
        final name = (raw['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.exe')) {
          setup = raw;
          break;
        }
      }
    }

    if (setup == null) {
      throw Exception('Release $remota sem instalador .exe.');
    }

    final url = setup['browser_download_url'] as String?;
    final name = setup['name'] as String? ?? 'Finn-Setup.exe';
    final assetId = setup['id'] as int?;
    if (url == null || url.isEmpty) {
      throw Exception('URL de download inválida na release $remota.');
    }

    return UpdateInfo(
      version: remota,
      downloadUrl: url,
      assetName: name,
      notes: json['body'] as String?,
      assetId: assetId,
    );
  }

  /// Baixa o setup e inicia instalação silenciosa. Encerra o app em seguida.
  Future<void> baixarEInstalar(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw Exception('Atualização automática disponível apenas no Windows.');
    }

    final tmp = await getTemporaryDirectory();
    final dest = File(p.join(tmp.path, info.assetName));
    if (await dest.exists()) {
      await dest.delete();
    }

    // Em repo privado, o download autenticado via API de assets é o mais confiável.
    final token = await _token();
    final downloadUri = (token.isNotEmpty && info.assetId != null)
        ? Uri.parse(
            'https://api.github.com/repos/$githubOwner/$githubRepo/releases/assets/${info.assetId}',
          )
        : Uri.parse(info.downloadUrl);

    final client = http.Client();
    try {
      final req = http.Request('GET', downloadUri);
      req.headers.addAll(await _headersAsync(forBinary: token.isNotEmpty));
      final streamed = await client.send(req);
      if (streamed.statusCode != 200) {
        throw Exception(
          'Falha ao baixar atualização (HTTP ${streamed.statusCode}).',
        );
      }

      final total = streamed.contentLength ?? 0;
      var received = 0;
      final sink = dest.openWrite();
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
    } finally {
      client.close();
    }

    await Process.start(
      dest.path,
      const ['/SILENT', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );

    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }
}
