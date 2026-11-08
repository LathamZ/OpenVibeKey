"""Pure metadata projection for an existing local, read-only WeChat backend.

No database/key/network access here. The backend supplies SessionTable metadata.
"""
import math
import uuid

NAMESPACE = uuid.UUID('7252069b-2cdd-49bb-8e18-40cbe5c538dd')


def recent_projection(rows, *, account_scope, generated_at, native_root_verified):
    if not native_root_verified:
        raise ValueError('native_account_not_verified')
    if len(account_scope) != 64 or any(c not in '0123456789abcdef' for c in account_scope):
        raise ValueError('invalid_account_scope')
    candidates = {}
    excluded = 0
    for row in rows:
        hidden = row.get('is_hidden')
        if hidden is None:
            raise ValueError('hidden_state_unavailable')
        try:
            hidden = int(hidden)
            stamp = float(row.get('last_timestamp') or 0)
            while math.isfinite(stamp) and stamp > 10_000_000_000:
                stamp /= 1000
        except (ValueError, TypeError):
            excluded += 1
            continue
        username = row.get('username')
        title = row.get('nick_name') or username
        if hidden != 0 or not math.isfinite(stamp) or stamp <= 0 or stamp > generated_at + 300:
            excluded += 1
            continue
        if not isinstance(username, str) or not username or not isinstance(title, str) or not title.strip():
            excluded += 1
            continue
        # Do not use sort_timestamp: pinned conversations can have artificial sort weights.
        candidate = {'id': str(uuid.uuid5(NAMESPACE, account_scope + ':' + username)),
                     'title': title.strip(), 'last_activity': stamp}
        if username not in candidates or stamp > candidates[username]['last_activity']:
            candidates[username] = candidate
    sessions = sorted(candidates.values(), key=lambda r: (-r['last_activity'], r['id']))[:50]
    return {'version': 1, 'source': 'macOS.WeChat.SessionTable', 'account_scope': account_scope,
            'generated_at': generated_at, 'hidden_filtered': True, 'native_root_verified': True,
            'metadata_only': True, 'limit': 50, 'sessions': sessions,
            'excluded_count': excluded}
