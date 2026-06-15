import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/models/profile.dart';
import '../../../core/models/work.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../works/presentation/work_selector.dart';

const _profileRegionOptions = ['北部', '中部', '南部', '離島', '海外'];
const _genderLabels = {'male': '生理男', 'female': '生理女', 'private': '不公開'};

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _nickname = TextEditingController();
  final _facebook = TextEditingController();
  final _bio = TextEditingController();
  final _age = TextEditingController();
  final _landmine = TextEditingController();
  String _avatarUrl = '';
  XFile? _pickedAvatar;
  List<WorkTag> _deepPitWorks = const [];
  List<WorkTag> _shallowPitWorks = const [];
  List<String> _regions = const [];
  List<String> _travelRegions = const [];
  bool _travelSameRegion = false;
  String _gender = 'private';
  List<String> _otherPhotoUrls = const [];
  final List<XFile?> _pickedOtherPhotos = List<XFile?>.filled(3, null);
  late Future<UserProfile?> _profileFuture;
  bool _initialized = false;
  bool _editing = false;
  bool _saving = false;
  static const _maxUploadBytes = 5 * 1024 * 1024;
  static const _allowedImageMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
  }

  @override
  void dispose() {
    _nickname.dispose();
    _facebook.dispose();
    _bio.dispose();
    _age.dispose();
    _landmine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _profileFuture,
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
            CosPageHeader(
              title: 'Cos 名片',
              subtitle: '讓同好快速認識你的作品、地區和交流方式',
              leading: const CosIconBubble(icon: Icons.badge_outlined),
              actions: [
                IconButton.filledTonal(
                  tooltip: '分享個人資訊',
                  onPressed: () => _showShareSheet(context, profile),
                  icon: const Icon(Icons.qr_code_2),
                ),
                IconButton.filledTonal(
                  tooltip: '掃描個人 QRCode',
                  onPressed: () => context.push('/scan-profile'),
                  icon: const Icon(Icons.qr_code_scanner),
                ),
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
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _editing
                  ? _EditProfileForm(
                      key: const ValueKey('profile-edit'),
                      avatarUrl: _avatarUrl,
                      nickname: _nickname,
                      facebook: _facebook,
                      bio: _bio,
                      age: _age,
                      landmine: _landmine,
                      deepPitWorks: _deepPitWorks,
                      shallowPitWorks: _shallowPitWorks,
                      regions: _regions,
                      travelRegions: _travelRegions,
                      travelSameRegion: _travelSameRegion,
                      gender: _gender,
                      otherPhotoUrls: _otherPhotoUrls,
                      onPickAvatar: _pickAvatar,
                      onDeepPitWorksChanged: (works) =>
                          setState(() => _deepPitWorks = works),
                      onShallowPitWorksChanged: (works) =>
                          setState(() => _shallowPitWorks = works),
                      onRegionsChanged: (regions) =>
                          setState(() => _regions = regions),
                      onTravelRegionsChanged: (regions) => setState(() {
                        _travelRegions = regions;
                        _travelSameRegion = _sameStringSet(_regions, regions);
                      }),
                      onUseSameRegions: () => setState(() {
                        _travelRegions = List<String>.from(_regions);
                        _travelSameRegion = _regions.isNotEmpty;
                      }),
                      onGenderChanged: (value) =>
                          setState(() => _gender = value),
                      onPickOtherPhoto: _pickOtherPhoto,
                      onRemoveOtherPhoto: _removeOtherPhoto,
                      onSave: () => _saveProfile(context, profile),
                      saving: _saving,
                    )
                  : _ProfileSummary(
                      key: const ValueKey('profile-summary'),
                      profile: profile,
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<UserProfile?> _fetchProfile() {
    return ref.read(profileRepositoryProvider).currentProfile();
  }

  void _loadProfile(UserProfile profile) {
    _nickname.text = profile.nickname;
    _facebook.text = profile.facebookUrl;
    _bio.text = profile.bio;
    _age.text = profile.age;
    _landmine.text = profile.landmine;
    _avatarUrl = profile.avatarUrl;
    _pickedAvatar = null;
    _deepPitWorks = profile.deepPitWorks;
    _shallowPitWorks = profile.shallowPitWorks;
    _regions = profile.regions;
    _travelRegions = profile.travelRegions;
    _travelSameRegion = profile.travelSameRegion;
    _gender = _genderLabels.containsKey(profile.gender)
        ? profile.gender
        : 'private';
    _otherPhotoUrls = List<String>.from(profile.otherPhotoUrls.take(3));
    for (var index = 0; index < _pickedOtherPhotos.length; index += 1) {
      _pickedOtherPhotos[index] = null;
    }
    _initialized = true;
  }

  Future<void> _saveProfile(BuildContext context, UserProfile profile) async {
    setState(() => _saving = true);
    try {
      final repository = ref.read(profileRepositoryProvider);
      var avatarUrl = _avatarUrl;
      final pickedAvatar = _pickedAvatar;
      if (pickedAvatar != null) {
        final uploadedUrl = await repository.uploadImage(
          bytes: await pickedAvatar.readAsBytes(),
          mimeType: _mimeTypeForImage(pickedAvatar),
        );
        if (uploadedUrl.isNotEmpty) avatarUrl = uploadedUrl;
      }
      final otherPhotoUrls = List<String>.from(_otherPhotoUrls);
      while (otherPhotoUrls.length < 3) {
        otherPhotoUrls.add('');
      }
      for (var index = 0; index < _pickedOtherPhotos.length; index += 1) {
        final picked = _pickedOtherPhotos[index];
        if (picked == null) continue;
        final uploadedUrl = await repository.uploadImage(
          bytes: await picked.readAsBytes(),
          mimeType: _mimeTypeForImage(picked),
        );
        if (uploadedUrl.isNotEmpty) otherPhotoUrls[index] = uploadedUrl;
      }

      final saved = await repository.saveProfile(
        profile.copyWith(
          nickname: _nickname.text.trim(),
          avatarUrl: avatarUrl,
          facebookUrl: _facebook.text.trim(),
          bio: _bio.text.trim(),
          deepPitWorks: _deepPitWorks,
          shallowPitWorks: _shallowPitWorks,
          age: _age.text.trim(),
          regions: _regions,
          travelRegions: _travelRegions,
          travelSameRegion: _travelSameRegion,
          landmine: _landmine.text.trim(),
          gender: _gender,
          otherPhotoUrls: otherPhotoUrls
              .map((url) => url.trim())
              .where((url) => url.isNotEmpty)
              .take(3)
              .toList(),
        ),
      );
      setState(() {
        _editing = false;
        _loadProfile(saved);
        _profileFuture = Future.value(saved);
      });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已同步更新個人資訊')));
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('個人資訊儲存失敗：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (image == null || !mounted) return;
    if (!await _validatePickedImage(image)) return;
    setState(() {
      _avatarUrl = image.path;
      _pickedAvatar = image;
    });
  }

  Future<void> _pickOtherPhoto(int index) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (image == null || !mounted) return;
    if (!await _validatePickedImage(image)) return;
    setState(() {
      while (_otherPhotoUrls.length <= index) {
        _otherPhotoUrls = [..._otherPhotoUrls, ''];
      }
      _otherPhotoUrls[index] = image.path;
      _pickedOtherPhotos[index] = image;
    });
  }

  void _removeOtherPhoto(int index) {
    setState(() {
      if (index < _otherPhotoUrls.length) {
        final urls = List<String>.from(_otherPhotoUrls);
        urls[index] = '';
        _otherPhotoUrls = urls.where((url) => url.isNotEmpty).toList();
      }
      _pickedOtherPhotos[index] = null;
    });
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return '';
  }

  String _mimeTypeForImage(XFile image) {
    final pickedMimeType = image.mimeType?.toLowerCase();
    if (pickedMimeType != null &&
        _allowedImageMimeTypes.contains(pickedMimeType)) {
      return pickedMimeType;
    }
    return _mimeTypeForPath(image.path);
  }

  Future<bool> _validatePickedImage(XFile image) async {
    final mimeType = _mimeTypeForImage(image);
    if (!_allowedImageMimeTypes.contains(mimeType)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('僅支援 JPG、PNG、WebP 圖片')));
      }
      return false;
    }
    final length = await image.length();
    if (length > _maxUploadBytes) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('圖片大小不可超過 5MB')));
      }
      return false;
    }
    return true;
  }

  bool _sameStringSet(List<String> left, List<String> right) {
    return left.length == right.length && left.every(right.contains);
  }

  void _showShareSheet(BuildContext context, UserProfile profile) {
    if (profile.publicCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('尚未取得分享碼，請稍後再試')));
      return;
    }
    final url = 'coscircle://profiles/${profile.publicCode}';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: CosGradientPanel(
              icon: Icons.qr_code_2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CosSectionHeader(
                    title: '分享 Cos 名片',
                    subtitle: '讓同好掃描後快速看見你的坑單和照片牆',
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: QrImageView(
                        data: url,
                        version: QrVersions.auto,
                        size: 210,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.nickname.isEmpty
                        ? 'CosCircle 名片'
                        : profile.nickname,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    url,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CosReveal(child: _ProfileHeroCard(profile: profile)),
        const SizedBox(height: 14),
        CosReveal(
          delay: const Duration(milliseconds: 70),
          child: CosCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CosSectionHeader(
                  title: '交流資訊',
                  subtitle: '讓同好知道怎麼和你開話題',
                  icon: Icons.forum_outlined,
                ),
                const SizedBox(height: 12),
                _InfoTile(
                  icon: Icons.article_outlined,
                  label: '自我介紹',
                  value: profile.bio.isEmpty ? '尚未填寫自我介紹' : profile.bio,
                ),
                _InfoTile(
                  icon: Icons.cake_outlined,
                  label: '年齡',
                  value: profile.age.isEmpty ? '尚未設定' : profile.age,
                ),
                _InfoTile(
                  icon: Icons.explore_outlined,
                  label: '座標',
                  value: profile.regions.isEmpty
                      ? '尚未設定'
                      : profile.regions.join('、'),
                ),
                _InfoTile(
                  icon: Icons.directions_run_outlined,
                  label: '跑場範圍',
                  value: profile.travelRegions.isEmpty
                      ? '尚未設定'
                      : profile.travelRegions.join('、'),
                ),
                _InfoTile(
                  icon: Icons.facebook,
                  label: 'Facebook',
                  value: profile.facebookUrl.isEmpty
                      ? '尚未設定'
                      : profile.facebookUrl,
                ),
                _InfoTile(
                  icon: Icons.warning_amber_outlined,
                  label: '雷點',
                  value: profile.landmine.isEmpty ? '尚未填寫' : profile.landmine,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        CosReveal(
          delay: const Duration(milliseconds: 120),
          child: CosCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CosSectionHeader(
                  title: '坑單',
                  subtitle: '深坑是最好開口的共同語言',
                  icon: Icons.label_important_outline,
                ),
                const SizedBox(height: 12),
                _WorkTagSection(
                  title: '深坑',
                  emptyText: '尚未新增深坑',
                  works: profile.deepPitWorks,
                  color: scheme.primary,
                ),
                const SizedBox(height: 12),
                _WorkTagSection(
                  title: '淺坑',
                  emptyText: '尚未新增淺坑',
                  works: profile.shallowPitWorks,
                  color: scheme.secondary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        CosReveal(
          delay: const Duration(milliseconds: 170),
          child: CosCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CosSectionHeader(
                  title: '照片牆',
                  subtitle: '用代表作讓同好在現場更快認出你',
                  icon: Icons.photo_library_outlined,
                ),
                const SizedBox(height: 12),
                if (profile.otherPhotoUrls.isEmpty)
                  const _PhotoEmptyState()
                else
                  _OtherPhotoGrid(photoUrls: profile.otherPhotoUrls),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosGradientPanel(
      icon: Icons.theater_comedy_outlined,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.secondary],
                  ),
                  boxShadow: [CosUi.softShadow(scheme.primary)],
                ),
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: scheme.surfaceContainerLowest,
                  backgroundImage: pickedImageProvider(profile.avatarUrl),
                  child: profile.avatarUrl.isEmpty
                      ? Icon(Icons.person, size: 42, color: scheme.primary)
                      : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CosBadge(
                      label: profile.publicCode.isEmpty ? '名片準備中' : '可交換名片',
                      icon: Icons.qr_code_2,
                      highlighted: true,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      profile.nickname.isEmpty ? '尚未設定暱稱' : profile.nickname,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900, height: 1.02),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        CosBadge(
                          label: profile.regions.isEmpty
                              ? '尚未設定座標'
                              : profile.regions.join('、'),
                          icon: Icons.explore_outlined,
                        ),
                        CosBadge(
                          label: profile.deepPitWorks.isEmpty
                              ? '深坑待補'
                              : '${profile.deepPitWorks.length} 個深坑',
                          icon: Icons.label_important_outline,
                          color: scheme.secondary,
                        ),
                        CosBadge(
                          label: _genderLabels[profile.gender] ?? '不公開',
                          icon: Icons.person_outline,
                          color: scheme.tertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ProfileSignalRow(profile: profile),
          if (profile.publicCode.isNotEmpty) ...[
            const SizedBox(height: 14),
            _ProfileQrInvite(profile: profile),
          ],
        ],
      ),
    );
  }
}

class _ProfileSignalRow extends StatelessWidget {
  const _ProfileSignalRow({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalWorks =
        profile.deepPitWorks.length + profile.shallowPitWorks.length;
    return Row(
      children: [
        Expanded(
          child: CosMetricTile(
            icon: Icons.label_important_outline,
            label: '坑單',
            value: '$totalWorks',
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CosMetricTile(
            icon: Icons.photo_library_outlined,
            label: '照片',
            value: '${profile.otherPhotoUrls.length}',
            color: scheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CosMetricTile(
            icon: Icons.directions_run_outlined,
            label: '跑場',
            value: '${profile.travelRegions.length}',
            color: scheme.tertiary,
          ),
        ),
      ],
    );
  }
}

class _ProfileQrInvite extends StatelessWidget {
  const _ProfileQrInvite({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.7),
            scheme.secondaryContainer.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: profile.publicCode,
                  version: QrVersions.auto,
                  size: 72,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '現場交換名片',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '讓同好掃描後追蹤、看坑單和照片牆。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoEmptyState extends StatelessWidget {
  const _PhotoEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CosIconBubble(
              icon: Icons.add_photo_alternate_outlined,
              color: scheme.secondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '尚未新增照片，可以放幾張代表作，讓同好更快認出你的角色。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkTagSection extends StatelessWidget {
  const _WorkTagSection({
    required this.title,
    required this.emptyText,
    required this.works,
    required this.color,
  });

  final String title;
  final String emptyText;
  final List<WorkTag> works;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (works.isEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      emptyText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final work in works)
                CosBadge(label: work.name, color: color),
            ],
          ),
      ],
    );
  }
}

class _EditProfileForm extends StatelessWidget {
  const _EditProfileForm({
    super.key,
    required this.avatarUrl,
    required this.nickname,
    required this.facebook,
    required this.bio,
    required this.age,
    required this.landmine,
    required this.deepPitWorks,
    required this.shallowPitWorks,
    required this.regions,
    required this.travelRegions,
    required this.travelSameRegion,
    required this.gender,
    required this.otherPhotoUrls,
    required this.onPickAvatar,
    required this.onDeepPitWorksChanged,
    required this.onShallowPitWorksChanged,
    required this.onRegionsChanged,
    required this.onTravelRegionsChanged,
    required this.onUseSameRegions,
    required this.onGenderChanged,
    required this.onPickOtherPhoto,
    required this.onRemoveOtherPhoto,
    required this.onSave,
    required this.saving,
  });

  final String avatarUrl;
  final TextEditingController nickname;
  final TextEditingController facebook;
  final TextEditingController bio;
  final TextEditingController age;
  final TextEditingController landmine;
  final List<WorkTag> deepPitWorks;
  final List<WorkTag> shallowPitWorks;
  final List<String> regions;
  final List<String> travelRegions;
  final bool travelSameRegion;
  final String gender;
  final List<String> otherPhotoUrls;
  final VoidCallback onPickAvatar;
  final ValueChanged<List<WorkTag>> onDeepPitWorksChanged;
  final ValueChanged<List<WorkTag>> onShallowPitWorksChanged;
  final ValueChanged<List<String>> onRegionsChanged;
  final ValueChanged<List<String>> onTravelRegionsChanged;
  final VoidCallback onUseSameRegions;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<int> onPickOtherPhoto;
  final ValueChanged<int> onRemoveOtherPhoto;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileFormSection(
          title: '基本資料',
          icon: Icons.badge_outlined,
          initiallyExpanded: true,
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundImage: pickedImageProvider(avatarUrl),
                    child: avatarUrl.isEmpty
                        ? const Icon(Icons.person, size: 38)
                        : null,
                  ),
                  IconButton.filled(
                    tooltip: '上傳頭像',
                    onPressed: saving ? null : onPickAvatar,
                    icon: const Icon(Icons.photo_camera),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nickname,
              decoration: const InputDecoration(labelText: '暱稱'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: age,
                    decoration: const InputDecoration(labelText: '年齡'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _genderLabels.containsKey(gender)
                        ? gender
                        : 'private',
                    decoration: const InputDecoration(labelText: '性別'),
                    items: [
                      for (final entry in _genderLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => onGenderChanged(value ?? 'private'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bio,
              decoration: const InputDecoration(labelText: '自我介紹'),
              maxLines: 4,
            ),
          ],
        ),
        _ProfileFormSection(
          title: '地區與跑場',
          icon: Icons.explore_outlined,
          children: [
            _RegionSelector(
              label: '座標',
              selected: regions,
              onChanged: onRegionsChanged,
              enabled: !saving,
            ),
            const SizedBox(height: 10),
            _RegionSelector(
              label: '跑場範圍',
              selected: travelRegions,
              onChanged: onTravelRegionsChanged,
              enabled: !saving,
              action: TextButton.icon(
                onPressed: saving || regions.isEmpty ? null : onUseSameRegions,
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(travelSameRegion ? '已同座標' : '同座標'),
              ),
            ),
          ],
        ),
        _ProfileFormSection(
          title: '坑單',
          icon: Icons.label_important_outline,
          children: [
            WorkMultiSelector(
              label: '深坑',
              selected: deepPitWorks,
              onChanged: onDeepPitWorksChanged,
            ),
            const SizedBox(height: 10),
            WorkMultiSelector(
              label: '淺坑',
              selected: shallowPitWorks,
              onChanged: onShallowPitWorksChanged,
            ),
          ],
        ),
        _ProfileFormSection(
          title: '社群與雷點',
          icon: Icons.forum_outlined,
          children: [
            TextField(
              controller: facebook,
              decoration: const InputDecoration(labelText: 'Facebook 網址'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: landmine,
              decoration: const InputDecoration(labelText: '雷點'),
              maxLines: 3,
            ),
          ],
        ),
        _ProfileFormSection(
          title: '其他照片',
          icon: Icons.photo_library_outlined,
          children: [
            _EditableOtherPhotoGrid(
              photoUrls: otherPhotoUrls,
              enabled: !saving,
              onPick: onPickOtherPhoto,
              onRemove: onRemoveOtherPhoto,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(saving ? '儲存中' : '儲存'),
          ),
        ),
      ],
    );
  }
}

class _ProfileFormSection extends StatelessWidget {
  const _ProfileFormSection({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CosCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          leading: CosIconBubble(icon: icon, size: 38),
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      ),
    );
  }
}

class _RegionSelector extends StatelessWidget {
  const _RegionSelector({
    required this.label,
    required this.selected,
    required this.onChanged,
    required this.enabled,
    this.action,
  });

  final String label;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final region in _profileRegionOptions)
              FilterChip(
                label: Text(region),
                selected: selected.contains(region),
                onSelected: enabled
                    ? (value) {
                        final next = List<String>.from(selected);
                        if (value) {
                          if (!next.contains(region)) next.add(region);
                        } else {
                          next.remove(region);
                        }
                        onChanged(next);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _OtherPhotoGrid extends StatelessWidget {
  const _OtherPhotoGrid({required this.photoUrls});

  final List<String> photoUrls;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: photoUrls.length.clamp(0, 3),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        return CosReveal(
          delay: Duration(milliseconds: 40 * index),
          offset: const Offset(0, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
              boxShadow: [
                CosUi.softShadow(Theme.of(context).colorScheme.shadow),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CosUi.radiusMd),
              child: Image(
                image: pickedImageProvider(photoUrls[index])!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditableOtherPhotoGrid extends StatelessWidget {
  const _EditableOtherPhotoGrid({
    required this.photoUrls,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final List<String> photoUrls;
  final bool enabled;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('其他照片', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            final url = index < photoUrls.length ? photoUrls[index] : '';
            return _EditablePhotoSlot(
              imageUrl: url,
              enabled: enabled,
              onPick: () => onPick(index),
              onRemove: url.isEmpty ? null : () => onRemove(index),
            );
          },
        ),
      ],
    );
  }
}

class _EditablePhotoSlot extends StatelessWidget {
  const _EditablePhotoSlot({
    required this.imageUrl,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final String imageUrl;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? onPick : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isEmpty)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 6),
                    Text('新增', style: Theme.of(context).textTheme.labelMedium),
                  ],
                )
              else
                Image(
                  image: pickedImageProvider(imageUrl)!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              if (onRemove != null && enabled)
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CosInfoTile(icon: icon, label: label, value: value),
    );
  }
}
