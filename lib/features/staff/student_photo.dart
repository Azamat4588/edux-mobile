import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// O'quvchi rasmi (veb 2.93: Components/Student/StudentPhoto.vue).
/// Xodim — `crm/students/{id}/photo` (qo'yish, almashtirish, o'chirish);
/// o'quvchi o'ziga, ota-ona farzandiga — `crm/my/photo` (markaz sozlamasida ruxsat bo'lsa, o'chirish yo'q).
class StudentPhotoAvatar extends StatefulWidget {
  const StudentPhotoAvatar({
    super.key,
    required this.studentId,
    required this.name,
    this.photo,
    this.size = 52,
    this.heroTag,
    this.editable = false,
    this.mine = false,
  });

  final int studentId;
  final String name;
  final String? photo;
  final double size;
  final Object? heroTag;
  final bool editable;
  final bool mine;

  /// Xodim rasm qo'ya oladimi: CRM, direktor / administrator / o'qituvchi, yozish ochiq.
  static bool staffCanEdit(Session session) =>
      session.hasModule('crm') && !session.readOnly && const <String>['director', 'admin', 'teacher'].contains(session.role);

  @override
  State<StudentPhotoAvatar> createState() => _StudentPhotoAvatarState();
}

class _StudentPhotoAvatarState extends State<StudentPhotoAvatar> {
  String? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
  }

  @override
  void didUpdateWidget(covariant StudentPhotoAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo != widget.photo) _photo = widget.photo;
  }

  Future<void> _menu() async {
    final hasPhoto = (_photo ?? '').isNotEmpty;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(tr('Galereyadan tanlash')), onTap: () => Navigator.pop(context, 'gallery')),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(tr('Suratga olish')), onTap: () => Navigator.pop(context, 'camera')),
          if (hasPhoto && !widget.mine)
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text(tr("O'chirish"), style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'delete') return _delete();
    await _upload(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _upload(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 88, maxWidth: 1600, preferredCameraDevice: CameraDevice.front);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      if (mounted) showMessage(context, tr('Rasm 8 MB dan oshmasin.'), error: true);
      return;
    }
    var name = file.name.isEmpty ? 'rasm.jpg' : file.name;
    if (!name.contains('.')) name = '$name.jpg';
    setState(() => _busy = true);
    try {
      final api = AppScope.read(context).api;
      final result = asMap(await api.multipart(
        widget.mine ? 'crm/my/photo' : 'crm/students/${widget.studentId}/photo',
        fields: widget.mine ? <String, String>{'student_id': '${widget.studentId}'} : const <String, String>{},
        files: <http.MultipartFile>[http.MultipartFile.fromBytes('photo', bytes, filename: name)],
      ));
      if (!mounted) return;
      setState(() => _photo = result['photo_url']?.toString());
      showMessage(context, tr('Rasm saqlandi.'));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, tr("Rasm o'chirilsinmi?"), action: tr("O'chirish"), danger: true) || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).api.delete('crm/students/${widget.studentId}/photo');
      if (mounted) setState(() => _photo = null);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = Avatar(widget.name, size: widget.size, heroTag: widget.heroTag, photo: _photo);
    if (!widget.editable) return avatar;
    return Semantics(
      button: true,
      label: tr('Rasm yuklash'),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _busy ? null : _menu,
        child: Stack(clipBehavior: Clip.none, children: <Widget>[
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              child: _busy
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.photo_camera, size: 12, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}
