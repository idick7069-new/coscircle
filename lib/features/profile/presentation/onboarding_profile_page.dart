import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/profile.dart';
import '../../../core/repositories/profile_repository.dart';
import '../../../shared/widgets/app_page.dart';

class OnboardingProfilePage extends ConsumerStatefulWidget {
  const OnboardingProfilePage({super.key});

  @override
  ConsumerState<OnboardingProfilePage> createState() =>
      _OnboardingProfilePageState();
}

class _OnboardingProfilePageState extends ConsumerState<OnboardingProfilePage> {
  final _nicknameController = TextEditingController();

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      appBar: AppBar(title: const Text('建立個人資料')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('先讓大家知道怎麼稱呼你', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          TextField(
            controller: _nicknameController,
            decoration: const InputDecoration(labelText: '暱稱'),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final nickname = _nicknameController.text.trim().isEmpty
                    ? '圈圈新朋友'
                    : _nicknameController.text.trim();
                await ref
                    .read(profileRepositoryProvider)
                    .saveProfile(UserProfile(id: 'me', nickname: nickname));
                if (context.mounted) context.go('/');
              },
              child: const Text('進入 Cos小圈圈'),
            ),
          ),
        ],
      ),
    );
  }
}
