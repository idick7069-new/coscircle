import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/profile.dart';
import '../../../core/models/work.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../works/presentation/work_selector.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _nickname = TextEditingController();
  final _facebook = TextEditingController();
  final _bio = TextEditingController();
  String _avatarUrl = '';
  List<WorkTag> _pitWorks = const [];
  bool _initialized = false;

  @override
  void dispose() {
    _nickname.dispose();
    _facebook.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: ref.watch(profileRepositoryProvider).currentProfile(),
      builder: (context, snapshot) {
        final profile =
            snapshot.data ?? const UserProfile(id: 'me', nickname: '');
        if (!_initialized) {
          _nickname.text = profile.nickname;
          _facebook.text = profile.facebookUrl;
          _bio.text = profile.bio;
          _avatarUrl = profile.avatarUrl;
          _pitWorks = profile.pitWorks;
          _initialized = true;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '個人資訊',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: pickedImageProvider(_avatarUrl),
                    child: _avatarUrl.isEmpty
                        ? const Icon(Icons.person, size: 42)
                        : null,
                  ),
                  IconButton.filled(
                    tooltip: '上傳頭像',
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.photo_camera),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nickname,
              decoration: const InputDecoration(labelText: '暱稱'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _facebook,
              decoration: const InputDecoration(labelText: 'Facebook 網址'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              decoration: const InputDecoration(labelText: '自我介紹'),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            WorkMultiSelector(
              label: '坑單',
              selected: _pitWorks,
              onChanged: (works) => setState(() => _pitWorks = works),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await ref
                    .read(profileRepositoryProvider)
                    .saveProfile(
                      profile.copyWith(
                        nickname: _nickname.text,
                        avatarUrl: _avatarUrl,
                        facebookUrl: _facebook.text,
                        bio: _bio.text,
                        pitWorks: _pitWorks,
                      ),
                    );
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已同步更新個人資訊')));
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('儲存'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (image == null || !mounted) return;
    setState(() => _avatarUrl = image.path);
  }
}
