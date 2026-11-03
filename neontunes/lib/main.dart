import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const bg = Color(0xFF090811);
const panel = Color(0xFF171326);
const purple = Color(0xFFB56CFF);
const blue = Color(0xFF55C8FF);

void main() => runApp(const NeonTunesApp());

class NeonTunesApp extends StatelessWidget {
  const NeonTunesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeonTunes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(primary: purple, secondary: blue, surface: panel),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: panel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          hintStyle: const TextStyle(color: Colors.white38),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class Track {
  final String title, artist, identifier, url, license;
  const Track({required this.title, required this.artist, required this.identifier, required this.url, this.license = ''});
  String get safeName => '${title.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim()}'
      '${artist.isNotEmpty ? ' - ${artist.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim()}' : ''}.mp3';
}

class Lyrics {
  final String plain, synced;
  const Lyrics(this.plain, this.synced);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final searchController = TextEditingController();
  final player = AudioPlayer();
  final List<Track> results = [];
  final List<File> downloads = [];
  final List<String> lines = [];
  int tab = 0;
  bool searching = false, downloading = false, loadingLyrics = false;
  String status = 'Search freely downloadable audio from Internet Archive.';
  String currentTitle = 'Nothing playing yet';
  String currentArtist = '';
  Lyrics? lyrics;
  Track? currentTrack;
  Duration position = Duration.zero, duration = Duration.zero;
  StreamSubscription<Duration>? positionSub;
  StreamSubscription<Duration?>? durationSub;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
    positionSub = player.positionStream.listen((v) { if (mounted) setState(() => position = v); });
    durationSub = player.durationStream.listen((v) { if (mounted) setState(() => duration = v ?? Duration.zero); });
    player.playerStateStream.listen((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    searchController.dispose();
    positionSub?.cancel();
    durationSub?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> searchMusic() async {
    final q = searchController.text.trim();
    if (q.isEmpty) return;
    setState(() { searching = true; results.clear(); status = 'Searching Internet Archive…'; });
    try {
      final query = Uri.encodeQueryComponent('mediatype:audio AND ($q)');
      final uri = Uri.parse('https://archive.org/advancedsearch.php?q=$query&fl[]=identifier,title,creator,licenseurl&rows=25&page=1&output=json');
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) throw Exception('Search service returned ${response.statusCode}');
      final docs = (jsonDecode(response.body)['response']['docs'] as List).cast<Map<String, dynamic>>();
      final found = <Track>[];
      for (final doc in docs) {
        final id = (doc['identifier'] ?? '').toString();
        if (id.isEmpty) continue;
        final metaResponse = await http.get(Uri.parse('https://archive.org/metadata/$id')).timeout(const Duration(seconds: 20));
        if (metaResponse.statusCode != 200) continue;
        final meta = jsonDecode(metaResponse.body) as Map<String, dynamic>;
        final fs = (meta['files'] as List? ?? []);
        final audio = fs.whereType<Map>().where((f) {
          final name = (f['name'] ?? '').toString().toLowerCase();
          return name.endsWith('.mp3') && f['private'] != 'true';
        }).cast<Map>();
        if (audio.isEmpty) continue;
        final f = audio.first;
        final name = (f['name'] ?? '').toString();
        final title = (doc['title'] ?? name.replaceAll('.mp3', '')).toString();
        final artist = (doc['creator'] ?? '').toString();
        final license = (doc['licenseurl'] ?? meta['metadata']?['licenseurl'] ?? '').toString();
        final url = 'https://archive.org/download/$id/${Uri.encodeComponent(name)}';
        found.add(Track(title: title, artist: artist, identifier: id, url: url, license: license));
        if (found.length >= 15) break;
      }
      if (!mounted) return;
      setState(() { results.addAll(found); status = found.isEmpty ? 'No downloadable MP3 results found. Try another search.' : 'Found ${found.length} downloadable MP3 item(s). Check each item’s usage rights before sharing.'; });
    } catch (e) {
      if (mounted) setState(() => status = 'Search failed: $e');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<Directory> _musicDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/NeonTunes');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadDownloads() async {
    try {
      final dir = await _musicDir();
      final files = dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.mp3')).toList();
      if (mounted) setState(() { downloads..clear()..addAll(files); });
    } catch (_) {}
  }

  Future<void> downloadTrack(Track track) async {
    if (downloading) return;
    setState(() { downloading = true; status = 'Downloading ${track.title}…'; });
    try {
      final dir = await _musicDir();
      final file = File('${dir.path}/${track.safeName}');
      final response = await http.get(Uri.parse(track.url)).timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) throw Exception('Download failed (${response.statusCode})');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      await _loadDownloads();
      if (mounted) setState(() => status = 'Saved ${track.safeName} in NeonTunes app storage.');
    } catch (e) {
      if (mounted) setState(() => status = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> importAudio() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (picked?.files.single.path == null) return;
    final source = File(picked!.files.single.path!);
    final dir = await _musicDir();
    final name = picked.files.single.name.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
    await source.copy('${dir.path}/$name');
    await _loadDownloads();
  }

  Future<void> playFile(File file, {Track? track}) async {
    try {
      await player.setFilePath(file.path);
      await player.play();
      setState(() {
        currentTitle = file.uri.pathSegments.last.replaceAll('.mp3', '');
        currentArtist = track?.artist ?? 'Local music';
        currentTrack = track;
        lyrics = null;
      });
      _findLyrics(currentTitle, currentArtist);
    } catch (e) {
      setState(() => status = 'Could not play this file: $e');
    }
  }

  Future<void> _findLyrics(String title, String artist) async {
    setState(() { loadingLyrics = true; lyrics = null; });
    try {
      final uri = Uri.https('lrclib.net', '/api/search', {'track_name': title, if (artist.isNotEmpty) 'artist_name': artist});
      final response = await http.get(uri, headers: {'User-Agent': 'NeonTunes/1.0 (Android music player)'}).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        if (list.isNotEmpty) {
          final item = list.first as Map<String, dynamic>;
          final l = Lyrics((item['plainLyrics'] ?? '').toString(), (item['syncedLyrics'] ?? '').toString());
          if (mounted) setState(() => lyrics = l);
        }
      }
    } catch (_) {
      // Lyrics are optional; playback continues if the lyrics service is unavailable.
    } finally {
      if (mounted) setState(() => loadingLyrics = false);
    }
  }

  List<String> get visibleLyrics {
    final synced = lyrics?.synced ?? '';
    if (synced.isNotEmpty) {
      final parsed = <String>[];
      for (final line in synced.split('\n')) {
        final match = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)').firstMatch(line);
        if (match != null) {
          final mins = int.parse(match.group(1)!);
          final secs = int.parse(match.group(2)!);
          final fraction = int.tryParse((match.group(3) ?? '0').padRight(3, '0').substring(0, 3)) ?? 0;
          final stamp = Duration(minutes: mins, seconds: secs, milliseconds: fraction);
          if (stamp <= position + const Duration(seconds: 1)) parsed.add(match.group(4)!.trim());
        }
      }
      return parsed;
    }
    return (lyrics?.plain ?? '').split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  String fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: bg,
        title: const Row(children: [
          Icon(Icons.graphic_eq, color: purple, size: 28),
          SizedBox(width: 8),
          Text('NEON', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
          Text('TUNES', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: purple)),
        ]),
        actions: [IconButton(onPressed: importAudio, icon: const Icon(Icons.library_add, color: blue), tooltip: 'Import audio')],
      ),
      body: SafeArea(child: Column(children: [
        Expanded(child: IndexedStack(index: tab, children: [_home(), _downloadsPage(), _playerPage()])),
        if (currentTitle != 'Nothing playing yet') _miniPlayer(),
        NavigationBar(
          backgroundColor: panel,
          indicatorColor: purple.withOpacity(.18),
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.search), label: 'Discover'),
            NavigationDestination(icon: Icon(Icons.download_done), label: 'Downloads'),
            NavigationDestination(icon: Icon(Icons.lyrics), label: 'Player'),
          ],
        ),
      ])),
    );
  }

  Widget _home() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Find your next track', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    const Text('Search freely downloadable audio. Availability depends on the source.', style: TextStyle(color: Colors.white60)),
    const SizedBox(height: 18),
    Row(children: [
      Expanded(child: TextField(controller: searchController, textInputAction: TextInputAction.search, onSubmitted: (_) => searchMusic(), decoration: const InputDecoration(prefixIcon: Icon(Icons.search, color: purple), hintText: 'Song, artist or keyword'))),
      const SizedBox(width: 8),
      IconButton.filled(onPressed: searching ? null : searchMusic, icon: searching ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward), style: IconButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.black)),
    ]),
    const SizedBox(height: 14),
    _statusCard(status),
    const SizedBox(height: 14),
    if (results.isNotEmpty) const Text('SEARCH RESULTS', style: TextStyle(color: blue, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
    ...results.map(_trackTile),
    const SizedBox(height: 20),
    const Text('A note about downloads', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 5),
    const Text('Results come from Internet Archive. A downloadable file is not automatically free of copyright restrictions. Check the item’s license and use only tracks you have permission to download and use.', style: TextStyle(color: Colors.white54, height: 1.4)),
  ]);

  Widget _downloadsPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Your library', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6),
    Text('${downloads.length} downloaded or imported file(s)', style: const TextStyle(color: Colors.white60)),
    const SizedBox(height: 14),
    FilledButton.icon(onPressed: importAudio, icon: const Icon(Icons.add), label: const Text('Import music from device')),
    const SizedBox(height: 12),
    if (downloads.isEmpty) _statusCard('Your offline library is empty. Search Discover or import audio files.'),
    ...downloads.map((f) => ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: const CircleAvatar(backgroundColor: panel, child: Icon(Icons.music_note, color: purple)),
      title: Text(f.uri.pathSegments.last, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: const Text('Stored in NeonTunes app folder', style: TextStyle(color: Colors.white54)),
      trailing: IconButton(icon: const Icon(Icons.play_circle_fill, color: purple), onPressed: () { playFile(f); setState(() => tab = 2); }),
    )),
  ]);

  Widget _playerPage() => ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Now playing', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
    const SizedBox(height: 14),
    Container(
      width: double.infinity, constraints: const BoxConstraints(minHeight: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF21163A), Color(0xFF101B2D)]),
        border: Border.all(color: purple.withOpacity(.35)),
        boxShadow: [BoxShadow(color: purple.withOpacity(.12), blurRadius: 24)],
      ),
      child: Column(children: [
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lyrics, color: blue), SizedBox(width: 8), Text('LYRICS', style: TextStyle(letterSpacing: 3, color: blue, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 16),
        if (loadingLyrics) const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(color: purple))
        else if (visibleLyrics.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Text(lyrics == null ? 'Lyrics will appear here when available.' : 'No lyrics were provided for this track.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 16)))
        else ...visibleLyrics.take(9).map((line) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(line, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: line == visibleLyrics.last ? purple : Colors.white70)),
        )),
        if ((lyrics?.plain ?? '').isEmpty && (lyrics?.synced ?? '').isEmpty && !loadingLyrics)
          const Text('Lyrics may not exist for every song or language.', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
    ),
    const SizedBox(height: 16),
    Text(currentTitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
    Text(currentArtist, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
    Slider(value: duration.inMilliseconds == 0 ? 0 : position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(), max: duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds.toDouble(), activeColor: purple, onChanged: duration.inMilliseconds == 0 ? null : (v) => player.seek(Duration(milliseconds: v.round()))),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(fmt(position), style: const TextStyle(color: Colors.white54)), Text(fmt(duration), style: const TextStyle(color: Colors.white54))]),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(onPressed: () => player.seek(Duration.zero), icon: const Icon(Icons.replay, color: blue)),
      IconButton.filled(onPressed: currentTitle == 'Nothing playing yet' ? null : () => player.playing ? player.pause() : player.play(), iconSize: 34, style: IconButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.black), icon: Icon(player.playing ? Icons.pause : Icons.play_arrow)),
      IconButton(onPressed: () => player.seek(duration), icon: const Icon(Icons.skip_next, color: blue)),
    ]),
    TextButton.icon(onPressed: currentTitle == 'Nothing playing yet' ? null : () => _findLyrics(currentTitle, currentArtist), icon: const Icon(Icons.refresh), label: const Text('Refresh lyrics')),
  ]);

  Widget _miniPlayer() => Material(
    color: const Color(0xFF201A30),
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.graphic_eq, color: purple),
      title: Text(currentTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(currentArtist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(onPressed: () => player.playing ? player.pause() : player.play(), icon: Icon(player.playing ? Icons.pause : Icons.play_arrow, color: purple)),
      onTap: () => setState(() => tab = 2),
    ),
  );

  Widget _trackTile(Track track) => Card(
    color: panel,
    margin: const EdgeInsets.only(top: 8),
    child: ListTile(
      leading: const CircleAvatar(backgroundColor: Color(0xFF302044), child: Icon(Icons.music_note, color: purple)),
      title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artist.isEmpty ? 'Internet Archive' : track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(onPressed: downloading ? null : () => downloadTrack(track), icon: const Icon(Icons.download, color: blue)),
      onTap: () async {
        final dir = await _musicDir();
        final f = File('${dir.path}/${track.safeName}');
        if (!await f.exists()) {
          await downloadTrack(track);
        }
        if (await f.exists()) {
          await playFile(f, track: track);
          setState(() => tab = 2);
        }
      },
    ),
  );

  Widget _statusCard(String text) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: purple.withOpacity(.18))),
    child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.35)),
  );
}
