import os from 'node:os';

export function assertSourceFetchHost(hostname = os.hostname()) {
  if (!/^coscircle-free-vm(?:\.|$)/.test(hostname)) {
    throw Object.assign(new Error('Activity source requests are allowed only on coscircle-free-vm; local fetching is disabled.'), {
      code: 'gcp_only_source_fetch',
    });
  }
}
