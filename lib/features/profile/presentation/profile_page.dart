import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/models/booking_visibility.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/work.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../core/utils/event_day_display.dart';
import '../../../core/utils/picked_image_provider.dart';
import '../../../shared/widgets/cos_ui.dart';
import '../../works/presentation/work_selector.dart';

const _profileRegionOptions = ['北部', '中部', '南部', '離島', '海外'];
const _genderLabels = {'male': '生理男', 'female': '生理女', 'private': '不公開'};
const _bookingVisibilityLabels = {'public': '全部人', 'circle': '僅小圈圈'};

final bookingFollowersProvider =
    FutureProvider.autoDispose<List<BookingFollowerGroup>>((ref) {
      return ref.watch(profileRepositoryProvider).fetchBookingFollowers();
    });

final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((
  ref,
) {
  return ref.watch(profileRepositoryProvider).fetchBlockedUsers();
});

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
  String _bookingVisibility = 'public';
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
          return const _ProfileLoadingState();
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
                      bookingVisibility: _bookingVisibility,
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
                      onBookingVisibilityChanged: (value) =>
                          setState(() => _bookingVisibility = value),
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
    _bookingVisibility =
        _bookingVisibilityLabels.containsKey(profile.bookingVisibility)
        ? profile.bookingVisibility
        : 'public';
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
          bookingVisibility: _bookingVisibility,
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
          delay: const Duration(milliseconds: 45),
          child: _ProfileReadinessCard(profile: profile),
        ),
        const SizedBox(height: 12),
        CosReveal(
          delay: const Duration(milliseconds: 60),
          child: _ProfileConnectionSignalCard(profile: profile),
        ),
        const SizedBox(height: 12),
        CosReveal(
          delay: const Duration(milliseconds: 75),
          child: _BookingPrivacyDashboard(profile: profile),
        ),
        const SizedBox(height: 12),
        CosReveal(
          delay: const Duration(milliseconds: 90),
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
          delay: const Duration(milliseconds: 140),
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
          delay: const Duration(milliseconds: 190),
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

class _ProfileLoadingState extends StatelessWidget {
  const _ProfileLoadingState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CosPageHeader(
          title: 'Cos 名片',
          subtitle: '正在整理你的同好識別資料',
          leading: CosIconBubble(icon: Icons.badge_outlined),
        ),
        const SizedBox(height: 12),
        CosGradientPanel(
          icon: Icons.theater_comedy_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 94,
                    height: 94,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest.withValues(
                        alpha: 0.62,
                      ),
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileSkeletonLine(widthFactor: 0.42),
                        const SizedBox(height: 10),
                        _ProfileSkeletonLine(widthFactor: 0.86, height: 22),
                        const SizedBox(height: 10),
                        _ProfileSkeletonLine(widthFactor: 0.62),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: const [
                  Expanded(child: _ProfileSkeletonMetric()),
                  SizedBox(width: 8),
                  Expanded(child: _ProfileSkeletonMetric()),
                  SizedBox(width: 8),
                  Expanded(child: _ProfileSkeletonMetric()),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const CosCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileSkeletonLine(widthFactor: 0.42, height: 18),
              SizedBox(height: 14),
              _ProfileSkeletonLine(widthFactor: 0.95),
              SizedBox(height: 10),
              _ProfileSkeletonLine(widthFactor: 0.72),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSkeletonMetric extends StatelessWidget {
  const _ProfileSkeletonMetric();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileSkeletonLine(widthFactor: 0.58, height: 16),
            SizedBox(height: 8),
            _ProfileSkeletonLine(widthFactor: 0.82, height: 10),
          ],
        ),
      ),
    );
  }
}

class _ProfileSkeletonLine extends StatelessWidget {
  const _ProfileSkeletonLine({required this.widthFactor, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(99),
        ),
        child: SizedBox(height: height),
      ),
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

class _ProfileReadinessCard extends StatelessWidget {
  const _ProfileReadinessCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cues = <_ProfileReadinessCue>[
      _ProfileReadinessCue(
        label: '暱稱',
        ready: profile.nickname.trim().isNotEmpty,
        icon: Icons.badge_outlined,
      ),
      _ProfileReadinessCue(
        label: '頭像',
        ready: profile.avatarUrl.trim().isNotEmpty,
        icon: Icons.face_retouching_natural_outlined,
      ),
      _ProfileReadinessCue(
        label: '自介',
        ready: profile.bio.trim().isNotEmpty,
        icon: Icons.article_outlined,
      ),
      _ProfileReadinessCue(
        label: '座標',
        ready: profile.regions.isNotEmpty,
        icon: Icons.explore_outlined,
      ),
      _ProfileReadinessCue(
        label: '跑場',
        ready: profile.travelRegions.isNotEmpty,
        icon: Icons.directions_run_outlined,
      ),
      _ProfileReadinessCue(
        label: '深坑',
        ready: profile.deepPitWorks.isNotEmpty,
        icon: Icons.label_important_outline,
      ),
      _ProfileReadinessCue(
        label: '淺坑',
        ready: profile.shallowPitWorks.isNotEmpty,
        icon: Icons.sell_outlined,
      ),
      _ProfileReadinessCue(
        label: '照片',
        ready: profile.otherPhotoUrls.isNotEmpty,
        icon: Icons.photo_library_outlined,
      ),
    ];
    final readyCount = cues.where((cue) => cue.ready).length;
    final progress = readyCount / cues.length;
    final nextCue = cues.where((cue) => !cue.ready).firstOrNull;

    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CosIconBubble(
                icon: Icons.radar_outlined,
                color: scheme.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '認親準備度',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      nextCue == null
                          ? '名片資訊完整，現場交換時更容易被認出。'
                          : '下一步補上「${nextCue.label}」，同好更快找到開話題的點。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$readyCount/${cues.length}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cue in cues)
                _ProfileReadinessChip(cue: cue, color: scheme.primary),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileReadinessCue {
  const _ProfileReadinessCue({
    required this.label,
    required this.ready,
    required this.icon,
  });

  final String label;
  final bool ready;
  final IconData icon;
}

class _ProfileReadinessChip extends StatelessWidget {
  const _ProfileReadinessChip({required this.cue, required this.color});

  final _ProfileReadinessCue cue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = cue.ready ? color : scheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: cue.ready ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              cue.ready ? Icons.check_circle : cue.icon,
              size: 15,
              color: accent,
            ),
            const SizedBox(width: 5),
            Text(
              cue.label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cue.ready ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileConnectionSignalCard extends StatelessWidget {
  const _ProfileConnectionSignalCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final favoriteWork =
        profile.deepPitWorks.firstOrNull ?? profile.shallowPitWorks.firstOrNull;
    final travelText = profile.travelRegions.isNotEmpty
        ? profile.travelRegions.join('、')
        : profile.regions.isNotEmpty
        ? profile.regions.join('、')
        : '尚未設定跑場';
    final boundaryText = profile.landmine.trim().isEmpty
        ? '尚未填寫雷點'
        : profile.landmine.trim();

    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CosSectionHeader(
            title: '同好訊號',
            subtitle: '把最容易開場的資訊排在一起',
            icon: Icons.diversity_3_outlined,
          ),
          const SizedBox(height: 12),
          _ProfileConnectionHero(
            title: favoriteWork == null ? '等你補上主坑' : favoriteWork.name,
            subtitle: favoriteWork == null
                ? '深坑或淺坑會成為同好最快的開場點'
                : profile.deepPitWorks.contains(favoriteWork)
                ? '主坑訊號，最適合拿來找同作品同好'
                : '淺坑訊號，適合讓同好知道你也有興趣',
            color: scheme.primary,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ProfileSignalCueTile(
                  icon: Icons.directions_run_outlined,
                  label: '跑場',
                  value: travelText,
                  color: scheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ProfileSignalCueTile(
                  icon: Icons.photo_library_outlined,
                  label: '辨識',
                  value: profile.otherPhotoUrls.isEmpty
                      ? '照片待補'
                      : '${profile.otherPhotoUrls.length} 張代表作',
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ProfileSignalCueTile(
            icon: Icons.warning_amber_outlined,
            label: '界線',
            value: boundaryText,
            color: scheme.error,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _BookingPrivacyDashboard extends ConsumerWidget {
  const _BookingPrivacyDashboard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final groups = ref.watch(bookingFollowersProvider);
    final blockedUsers = ref.watch(blockedUsersProvider);
    final visibilityLabel =
        _bookingVisibilityLabels[profile.bookingVisibility] ?? '全部人';
    final followerCount = groups.whenOrNull(
      data: (items) =>
          items.fold<int>(0, (total, group) => total + group.followers.length),
    );
    final blockedCount = blockedUsers.whenOrNull(data: (items) => items.length);

    return CosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CosSectionHeader(
            title: '場次安全',
            subtitle: '管理誰能看見你的場次預定與追蹤訊號',
            icon: Icons.shield_outlined,
            trailing: CosBadge(
              label: visibilityLabel,
              icon: profile.bookingVisibility == 'circle'
                  ? Icons.groups_outlined
                  : Icons.public_outlined,
              color: scheme.primary,
              highlighted: true,
            ),
          ),
          const SizedBox(height: 14),
          _SafetySignalStrip(
            visibilityLabel: visibilityLabel,
            visibilityIcon: profile.bookingVisibility == 'circle'
                ? Icons.groups_2_outlined
                : Icons.public_outlined,
            followerCount: followerCount,
            blockedCount: blockedCount,
          ),
          const SizedBox(height: 14),
          groups.when(
            data: (items) {
              if (items.isEmpty) {
                return const _BookingPrivacyEmptyState();
              }
              return Column(
                children: [
                  for (final group in items) ...[
                    _BookingFollowerGroupTile(group: group),
                    if (group != items.last) const SizedBox(height: 10),
                  ],
                ],
              );
            },
            error: (error, stack) => _BookingPrivacyMessage(
              icon: Icons.wifi_off_outlined,
              message: '追蹤資訊載入失敗',
              actionLabel: '重新整理',
              onAction: () => ref.invalidate(bookingFollowersProvider),
            ),
            loading: () => const _BookingPrivacyLoadingState(),
          ),
          const SizedBox(height: 14),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          CosSectionHeader(
            title: '黑名單',
            subtitle: '被封鎖的人不能看見你的名片、場次預定與現場訊號',
            icon: Icons.block_outlined,
            trailing: blockedUsers.whenOrNull(
              data: (items) => CosBadge(
                label: '${items.length}',
                icon: Icons.shield_outlined,
                color: scheme.error,
              ),
            ),
          ),
          const SizedBox(height: 10),
          blockedUsers.when(
            data: (items) {
              if (items.isEmpty) {
                return const _BookingPrivacyMessage(
                  icon: Icons.verified_user_outlined,
                  message: '目前沒有封鎖任何使用者。',
                );
              }
              return Column(
                children: [
                  for (final user in items)
                    _BlockedUserRow(
                      user: user,
                      onUnblock: () => _confirmUnblockUser(context, ref, user),
                    ),
                ],
              );
            },
            error: (error, stack) => _BookingPrivacyMessage(
              icon: Icons.wifi_off_outlined,
              message: '黑名單載入失敗',
              actionLabel: '重新整理',
              onAction: () => ref.invalidate(blockedUsersProvider),
            ),
            loading: () => const _BookingPrivacyLoadingState(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnblockUser(
    BuildContext context,
    WidgetRef ref,
    BlockedUser user,
  ) async {
    final confirmed = await _confirmSafetyAction(
      context,
      title: '解除封鎖 ${user.nickname}？',
      message: '解除後對方仍不會自動恢復關注，但可以依你的可見範圍重新看到公開資訊。',
      actionLabel: '解除封鎖',
    );
    if (!confirmed) return;
    await ref.read(profileRepositoryProvider).unblockUser(user.userId);
    ref.invalidate(blockedUsersProvider);
    ref.invalidate(bookingFollowersProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已解除封鎖')));
  }
}

class _BookingFollowerGroupTile extends ConsumerWidget {
  const _BookingFollowerGroupTile({required this.group});

  final BookingFollowerGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CosIconBubble(
                  icon: Icons.event_available_outlined,
                  color: scheme.secondary,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cleanEventName(group.eventName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_compactDate(group.startDate)} · Day ${group.dayIndex}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                CosBadge(
                  label: '${group.followers.length}',
                  icon: Icons.visibility_outlined,
                  color: scheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (group.followers.isEmpty)
              Text(
                '目前沒有追蹤者能看到這筆預定。',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Column(
                children: [
                  for (final follower in group.followers)
                    _BookingFollowerRow(
                      follower: follower,
                      onRemove: () =>
                          _confirmRemoveFollower(context, ref, follower),
                      onBlock: () =>
                          _confirmBlockFollower(context, ref, follower),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveFollower(
    BuildContext context,
    WidgetRef ref,
    BookingFollower follower,
  ) async {
    final confirmed = await _confirmSafetyAction(
      context,
      title: '取消 ${follower.nickname} 的關注？',
      message: '對方會從你的追蹤者中移除，但仍可依你的可見範圍看到公開資訊。',
      actionLabel: '取消關注',
    );
    if (!confirmed) return;
    await ref.read(profileRepositoryProvider).removeFollower(follower.userId);
    ref.invalidate(bookingFollowersProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已移除追蹤者')));
  }

  Future<void> _confirmBlockFollower(
    BuildContext context,
    WidgetRef ref,
    BookingFollower follower,
  ) async {
    final confirmed = await _confirmSafetyAction(
      context,
      title: '封鎖 ${follower.nickname}？',
      message: '封鎖後對方將看不到你的個人資訊、場次預定與現場訊號，也不能再關注你。',
      actionLabel: '封鎖',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(profileRepositoryProvider).blockUser(follower.userId);
    ref.invalidate(bookingFollowersProvider);
    ref.invalidate(blockedUsersProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已封鎖使用者')));
  }
}

class _BookingFollowerRow extends StatelessWidget {
  const _BookingFollowerRow({
    required this.follower,
    required this.onRemove,
    required this.onBlock,
  });

  final BookingFollower follower;
  final VoidCallback onRemove;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nickname = follower.nickname.isEmpty ? '未命名使用者' : follower.nickname;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                backgroundImage: pickedImageProvider(follower.avatarUrl),
                child: follower.avatarUrl.isEmpty
                    ? Text(nickname.characters.firstOrNull ?? '?')
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '正在關注你的場次預定',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '取消關注',
                onPressed: onRemove,
                icon: const Icon(Icons.person_remove_outlined),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: '封鎖',
                onPressed: onBlock,
                color: scheme.error,
                icon: const Icon(Icons.block_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetySignalStrip extends StatelessWidget {
  const _SafetySignalStrip({
    required this.visibilityLabel,
    required this.visibilityIcon,
    required this.followerCount,
    required this.blockedCount,
  });

  final String visibilityLabel;
  final IconData visibilityIcon;
  final int? followerCount;
  final int? blockedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final metrics = [
          _SafetySignalMetric(
            icon: visibilityIcon,
            label: '可見',
            value: visibilityLabel,
            color: scheme.primary,
          ),
          _SafetySignalMetric(
            icon: Icons.visibility_outlined,
            label: '關注中',
            value: followerCount == null ? '讀取中' : '$followerCount 人',
            color: scheme.secondary,
          ),
          _SafetySignalMetric(
            icon: Icons.block_outlined,
            label: '已封鎖',
            value: blockedCount == null ? '讀取中' : '$blockedCount 人',
            color: scheme.error,
          ),
        ];
        if (compact) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in metrics)
                SizedBox(width: (constraints.maxWidth - 8) / 2, child: metric),
            ],
          );
        }
        return Row(
          children: [
            for (final metric in metrics) ...[
              Expanded(child: metric),
              if (metric != metrics.last) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }
}

class _SafetySignalMetric extends StatelessWidget {
  const _SafetySignalMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedUserRow extends StatelessWidget {
  const _BlockedUserRow({required this.user, required this.onUnblock});

  final BlockedUser user;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nickname = user.nickname.isEmpty ? '未命名使用者' : user.nickname;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(color: scheme.error.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.errorContainer,
                backgroundImage: pickedImageProvider(user.avatarUrl),
                child: user.avatarUrl.isEmpty
                    ? Text(nickname.characters.firstOrNull ?? '?')
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      user.blockedAt.isEmpty
                          ? '已加入黑名單'
                          : '封鎖於 ${user.blockedAt}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onUnblock,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('解除'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingPrivacyEmptyState extends StatelessWidget {
  const _BookingPrivacyEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _BookingPrivacyMessage(
      icon: Icons.visibility_off_outlined,
      message: '目前沒有追蹤者正在看你的場次預定。',
    );
  }
}

class _BookingPrivacyLoadingState extends StatelessWidget {
  const _BookingPrivacyLoadingState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CosLoadingPulse(color: scheme.secondary, size: 24),
            const SizedBox(width: 10),
            Text(
              '正在整理追蹤訊號',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingPrivacyMessage extends StatelessWidget {
  const _BookingPrivacyMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CosIconBubble(icon: icon, size: 36),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

String _compactDate(DateTime date) {
  if (date.millisecondsSinceEpoch == 0) return '日期未定';
  return '${date.month}/${date.day}';
}

Future<bool> _confirmSafetyAction(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => CosSafetyConfirmDialog(
      title: title,
      message: message,
      actionLabel: actionLabel,
      icon: destructive ? Icons.block_outlined : Icons.verified_user_outlined,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class _ProfileConnectionHero extends StatelessWidget {
  const _ProfileConnectionHero({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(CosUi.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CosIconBubble(icon: Icons.auto_awesome, color: color, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
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

class _ProfileSignalCueTile extends StatelessWidget {
  const _ProfileSignalCueTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(CosUi.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
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
    required this.bookingVisibility,
    required this.otherPhotoUrls,
    required this.onPickAvatar,
    required this.onDeepPitWorksChanged,
    required this.onShallowPitWorksChanged,
    required this.onRegionsChanged,
    required this.onTravelRegionsChanged,
    required this.onUseSameRegions,
    required this.onGenderChanged,
    required this.onBookingVisibilityChanged,
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
  final String bookingVisibility;
  final List<String> otherPhotoUrls;
  final VoidCallback onPickAvatar;
  final ValueChanged<List<WorkTag>> onDeepPitWorksChanged;
  final ValueChanged<List<WorkTag>> onShallowPitWorksChanged;
  final ValueChanged<List<String>> onRegionsChanged;
  final ValueChanged<List<String>> onTravelRegionsChanged;
  final VoidCallback onUseSameRegions;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<String> onBookingVisibilityChanged;
  final ValueChanged<int> onPickOtherPhoto;
  final ValueChanged<int> onRemoveOtherPhoto;
  final VoidCallback onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final totalWorks = deepPitWorks.length + shallowPitWorks.length;
    final photoCount = otherPhotoUrls.where((url) => url.isNotEmpty).length;
    return Column(
      children: [
        _EditProfilePassPanel(
          nickname: nickname.text,
          regions: regions,
          travelRegions: travelRegions,
          totalWorks: totalWorks,
          photoCount: photoCount,
        ),
        const SizedBox(height: 12),
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
            TextField(
              controller: age,
              decoration: const InputDecoration(labelText: '年齡'),
            ),
            const SizedBox(height: 10),
            _GenderSelector(
              value: _genderLabels.containsKey(gender) ? gender : 'private',
              enabled: !saving,
              onChanged: onGenderChanged,
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
          title: '安全與可見範圍',
          icon: Icons.shield_outlined,
          children: [
            _BookingVisibilitySelector(
              value: bookingVisibility,
              enabled: !saving,
              onChanged: onBookingVisibilityChanged,
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
          child: _ProfileSaveButton(
            saving: saving,
            onPressed: saving ? null : onSave,
          ),
        ),
      ],
    );
  }
}

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '性別',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in _genderLabels.entries)
              CosChoicePill(
                label: entry.value,
                selected: value == entry.key,
                enabled: enabled,
                icon: switch (entry.key) {
                  'male' => Icons.male,
                  'female' => Icons.female,
                  _ => Icons.visibility_off_outlined,
                },
                onTap: () => onChanged(entry.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProfileSaveButton extends StatelessWidget {
  const _ProfileSaveButton({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: saving
          ? CosLoadingPulse(color: scheme.onPrimary, size: 20)
          : const Icon(Icons.save),
      label: Text(saving ? '儲存中' : '儲存'),
    );
  }
}

class _EditProfilePassPanel extends StatelessWidget {
  const _EditProfilePassPanel({
    required this.nickname,
    required this.regions,
    required this.travelRegions,
    required this.totalWorks,
    required this.photoCount,
  });

  final String nickname;
  final List<String> regions;
  final List<String> travelRegions;
  final int totalWorks;
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CosReveal(
      child: CosGradientPanel(
        icon: Icons.edit_note_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CosIconBubble(
                  icon: Icons.theater_comedy_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nickname.trim().isEmpty ? '名片調整台' : nickname.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '調整同好能快速辨識你的資訊，不會改變任何公開範圍設定。',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: CosMetricTile(
                    icon: Icons.explore_outlined,
                    label: '座標',
                    value: regions.isEmpty ? '未設' : regions.join('、'),
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CosMetricTile(
                    icon: Icons.label_important_outline,
                    label: '坑單',
                    value: '$totalWorks',
                    color: scheme.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CosMetricTile(
                    icon: Icons.photo_library_outlined,
                    label: '照片',
                    value: '$photoCount',
                    color: scheme.tertiary,
                  ),
                ),
              ],
            ),
            if (travelRegions.isNotEmpty) ...[
              const SizedBox(height: 12),
              CosBadge(
                label: '可跑場：${travelRegions.join('、')}',
                icon: Icons.directions_run_outlined,
                color: scheme.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileFormSection extends StatefulWidget {
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
  State<_ProfileFormSection> createState() => _ProfileFormSectionState();
}

class _ProfileFormSectionState extends State<_ProfileFormSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CosCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CosUi.radiusLg),
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scheme.primaryContainer.withValues(
                            alpha: _expanded ? 0.42 : 0.22,
                          ),
                          scheme.surfaceContainerLowest,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        CosIconBubble(icon: widget.icon, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _expanded ? '正在編輯這段資訊' : '點一下展開設定',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Column(children: widget.children),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingVisibilitySelector extends StatelessWidget {
  const _BookingVisibilitySelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('場次預定可見範圍', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _BookingVisibilityOption(
          icon: Icons.public_outlined,
          title: '全部人',
          subtitle: '所有登入使用者都能在活動頁看到你的場次預定。',
          selected: value != 'circle',
          enabled: enabled,
          color: scheme.primary,
          onTap: () => onChanged('public'),
        ),
        const SizedBox(height: 8),
        _BookingVisibilityOption(
          icon: Icons.groups_outlined,
          title: '僅小圈圈',
          subtitle: '只有和你同小圈圈的人能看到你的場次預定與現場訊號。',
          selected: value == 'circle',
          enabled: enabled,
          color: scheme.secondary,
          onTap: () => onChanged('circle'),
        ),
      ],
    );
  }
}

class _BookingVisibilityOption extends StatelessWidget {
  const _BookingVisibilityOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(CosUi.radiusMd),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(CosUi.radiusMd),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.45)
                : scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CosIconBubble(icon: icon, color: color, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? color : scheme.onSurfaceVariant,
              ),
            ],
          ),
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
          runSpacing: 8,
          children: [
            for (final region in _profileRegionOptions)
              CosChoicePill(
                label: region,
                selected: selected.contains(region),
                enabled: enabled,
                icon: Icons.place_outlined,
                onTap: () {
                  final next = List<String>.from(selected);
                  if (next.contains(region)) {
                    next.remove(region);
                  } else {
                    next.add(region);
                  }
                  onChanged(next);
                },
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
