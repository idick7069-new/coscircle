import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/app_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            'CosCircle',
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('Cos小圈圈', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(
            '大型活動中快速找到朋友、分享位置、管理預訂與小圈圈。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.go('/onboarding'),
              icon: const Icon(Icons.g_mobiledata),
              label: const Text('使用 Google 登入'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/onboarding'),
              icon: const Icon(Icons.facebook),
              label: const Text('使用 Facebook 登入'),
            ),
          ),
        ],
      ),
    );
  }
}
