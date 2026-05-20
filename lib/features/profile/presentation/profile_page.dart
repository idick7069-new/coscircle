import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  bool _editing = false;

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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile =
            snapshot.data ?? const UserProfile(id: 'me', nickname: '');
        if (!_initialized) {
          _loadProfile(profile);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '個人資訊',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '分享個人資訊',
                  onPressed: () => _showShareSheet(context, profile),
                  icon: const Icon(Icons.qr_code_2),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: _editing ? '取消編輯' : '編輯',
                  onPressed: () {
                    setState(() {
                      if (_editing) _loadProfile(profile);
                      _editing = !_editing;
                    });
                  },
                  icon: Icon(_editing ? Icons.close : Icons.edit),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_editing)
              _EditProfileForm(
                avatarUrl: _avatarUrl,
                nickname: _nickname,
                facebook: _facebook,
                bio: _bio,
                pitWorks: _pitWorks,
                onPickAvatar: _pickAvatar,
                onPitWorksChanged: (works) => setState(() => _pitWorks = works),
                onSave: () => _saveProfile(context, profile),
              )
            else
              _ProfileSummary(profile: profile),
          ],
        );
      },
    );
  }

  void _loadProfile(UserProfile profile) {
    _nickname.text = profile.nickname;
    _facebook.text = profile.facebookUrl;
    _bio.text = profile.bio;
    _avatarUrl = profile.avatarUrl;
    _pitWorks = profile.pitWorks;
    _initialized = true;
  }

  Future<void> _saveProfile(BuildContext context, UserProfile profile) async {
    final saved = await ref
        .read(profileRepositoryProvider)
        .saveProfile(
          profile.copyWith(
            nickname: _nickname.text.trim(),
            avatarUrl: _avatarUrl,
            facebookUrl: _facebook.text.trim(),
            bio: _bio.text.trim(),
            pitWorks: _pitWorks,
          ),
        );
    setState(() {
      _editing = false;
      _loadProfile(saved);
    });
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已同步更新個人資訊')));
    }
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (image == null || !mounted) return;
    setState(() => _avatarUrl = image.path);
  }

  void _showShareSheet(BuildContext context, UserProfile profile) {
    final url = 'coscircle://users/${profile.id}';
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('分享個人資訊', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 12),
                Text(
                  profile.nickname,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(url),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: CircleAvatar(
            radius: 52,
            backgroundImage: pickedImageProvider(profile.avatarUrl),
            child: profile.avatarUrl.isEmpty
                ? const Icon(Icons.person, size: 46)
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          profile.nickname.isEmpty ? '尚未設定暱稱' : profile.nickname,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        _InfoTile(
          icon: Icons.article_outlined,
          label: '自我介紹',
          value: profile.bio.isEmpty ? '尚未填寫自我介紹' : profile.bio,
        ),
        _InfoTile(
          icon: Icons.facebook,
          label: 'Facebook',
          value: profile.facebookUrl.isEmpty ? '尚未設定' : profile.facebookUrl,
        ),
        const SizedBox(height: 12),
        Text('坑單', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (profile.pitWorks.isEmpty)
          const Text('尚未新增坑單')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final work in profile.pitWorks) Chip(label: Text(work.name)),
            ],
          ),
      ],
    );
  }
}

class _EditProfileForm extends StatelessWidget {
  const _EditProfileForm({
    required this.avatarUrl,
    required this.nickname,
    required this.facebook,
    required this.bio,
    required this.pitWorks,
    required this.onPickAvatar,
    required this.onPitWorksChanged,
    required this.onSave,
  });

  final String avatarUrl;
  final TextEditingController nickname;
  final TextEditingController facebook;
  final TextEditingController bio;
  final List<WorkTag> pitWorks;
  final VoidCallback onPickAvatar;
  final ValueChanged<List<WorkTag>> onPitWorksChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: pickedImageProvider(avatarUrl),
                child: avatarUrl.isEmpty
                    ? const Icon(Icons.person, size: 42)
                    : null,
              ),
              IconButton.filled(
                tooltip: '上傳頭像',
                onPressed: onPickAvatar,
                icon: const Icon(Icons.photo_camera),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: nickname,
          decoration: const InputDecoration(labelText: '暱稱'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: facebook,
          decoration: const InputDecoration(labelText: 'Facebook 網址'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: bio,
          decoration: const InputDecoration(labelText: '自我介紹'),
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        WorkMultiSelector(
          label: '坑單',
          selected: pitWorks,
          onChanged: onPitWorksChanged,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save),
            label: const Text('儲存'),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
