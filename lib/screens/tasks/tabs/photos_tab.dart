import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;
import '../../../providers/database_provider.dart';
import '../../../db/database.dart';

final _photosProvider = FutureProvider.family<List<Photo>, String>((ref, taskId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.photos)
        ..where((p) => p.taskId.equals(taskId))
        ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
      .get();
});

class PhotosTab extends ConsumerWidget {
  final String taskId;
  const PhotosTab({super.key, required this.taskId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(_photosProvider(taskId));

    return Scaffold(
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (photos) {
          if (photos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_camera_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text('Noch keine Fotos',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: photos.length,
            itemBuilder: (_, i) => _PhotoTile(
              photo: photos[i],
              onDelete: () async {
                await _deletePhoto(ref, photos[i]);
              },
              onTap: () => _showPhoto(context, photos[i]),
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isDesktop) ...[
            FloatingActionButton.small(
              heroTag: 'gallery',
              onPressed: () => _addPhoto(context, ref, ImageSource.gallery),
              tooltip: 'Aus Galerie',
              child: const Icon(Icons.photo_library_outlined),
            ),
            const SizedBox(height: 8),
            FloatingActionButton(
              heroTag: 'camera',
              onPressed: () => _addPhoto(context, ref, ImageSource.camera),
              child: const Icon(Icons.camera_alt),
            ),
          ] else
            FloatingActionButton(
              heroTag: 'file',
              onPressed: () => _addPhotoDesktop(context, ref),
              tooltip: 'Bild hinzufügen',
              child: const Icon(Icons.add_photo_alternate_outlined),
            ),
        ],
      ),
    );
  }

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  Future<void> _addPhotoDesktop(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/photos');
    await photoDir.create(recursive: true);
    final ext = path.contains('.') ? '.${path.split('.').last}' : '.jpg';
    final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = File('${photoDir.path}/$fileName');
    await File(path).copy(dest.path);

    final db = ref.read(databaseProvider);
    await db.into(db.photos).insert(PhotosCompanion.insert(
          taskId: taskId,
          filePath: dest.path,
        ));
    ref.invalidate(_photosProvider(taskId));
  }

  Future<void> _addPhoto(
      BuildContext context, WidgetRef ref, ImageSource source) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (xFile == null) return;

    // Foto in App-Datenordner kopieren
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${appDir.path}/photos');
    await photoDir.create(recursive: true);
    final fileName =
        'photo_${DateTime.now().millisecondsSinceEpoch}${xFile.name.contains('.') ? '.${xFile.name.split('.').last}' : '.jpg'}';
    final dest = File('${photoDir.path}/$fileName');
    await File(xFile.path).copy(dest.path);

    final db = ref.read(databaseProvider);
    await db.into(db.photos).insert(PhotosCompanion.insert(
          taskId: taskId,
          filePath: dest.path,
        ));
    ref.invalidate(_photosProvider(taskId));
  }

  Future<void> _deletePhoto(WidgetRef ref, Photo photo) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.photos)..where((p) => p.id.equals(photo.id))).go();
    // Datei löschen
    try {
      await File(photo.filePath).delete();
    } catch (_) {}
    ref.invalidate(_photosProvider(taskId));
  }

  void _showPhoto(BuildContext context, Photo photo) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoViewer(photo: photo),
        fullscreenDialog: true,
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final Photo photo;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  const _PhotoTile(
      {required this.photo, required this.onDelete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final file = File(photo.filePath);
    return GestureDetector(
      onTap: onTap,
      onLongPress: () async {
        final del = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Foto löschen?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Löschen')),
            ],
          ),
        );
        if (del == true) onDelete();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.broken_image_outlined),
              ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final Photo photo;
  const _PhotoViewer({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          DateFormat('dd.MM.yyyy HH:mm').format(photo.createdAt.toLocal()),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(photo.filePath)),
        ),
      ),
    );
  }
}
