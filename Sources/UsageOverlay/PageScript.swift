import Foundation

/// 탭 안에서 실행할 JS.
///
/// 주의: AppleScript 문자열로 넣기 위해 줄바꿈이 공백으로 치환되므로
/// `//` 줄 주석을 쓰면 뒤쪽 코드가 통째로 주석 처리된다. 블록 주석만 사용할 것.
///
/// DOM을 긁지 않고 로그인된 세션으로 사용량 API를 직접 부른다.
/// 화면 문구에서 퍼센트를 줍는 방식은 프로모션 배너의 "50% 더 높아집니다" 같은
/// 문장을 사용량으로 오인해서 걷어냈다. 틀린 숫자를 띄우느니 로컬 캐시로 떨어지는 편이 낫다.
enum PageScript {
    /// claude.ai: 조직 uuid를 먼저 알아낸 뒤 그 조직의 사용량을 부른다.
    /// 응답은 `~/.claude.json` 의 `cachedUsageUtilization.utilization` 과 같은 모양.
    static let claudeResolver = """
    function (S) {
      var usage = function (uuid) {
        S.endpoint = '/api/organizations/' + uuid + '/usage';
        return fetch(S.endpoint, { credentials: 'include', headers: { accept: 'application/json' } })
          .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); });
      };
      if (S.uuid) return usage(S.uuid);
      return fetch('/api/organizations', { credentials: 'include', headers: { accept: 'application/json' } })
        .then(function (r) { if (!r.ok) throw new Error('organizations HTTP ' + r.status); return r.json(); })
        .then(function (list) {
          var org = (list && list.length) ? list[0] : null;
          if (!org || !org.uuid) throw new Error('No organization found (sign in required)');
          S.uuid = org.uuid;
          return usage(S.uuid);
        });
    }
    """

    /// chatgpt.com: 쿠키만으로는 401이라 세션 토큰을 받아 Bearer로 붙인다.
    static let codexResolver = """
    function (S) {
      var usage = function (token) {
        S.endpoint = '/backend-api/codex/usage';
        var headers = { accept: 'application/json' };
        if (token) headers.authorization = 'Bearer ' + token;
        return fetch(S.endpoint, { credentials: 'include', headers: headers })
          .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); });
      };
      if (S.token) return usage(S.token);
      return fetch('/api/auth/session', { credentials: 'include' })
        .then(function (r) { if (!r.ok) throw new Error('session HTTP ' + r.status); return r.json(); })
        .then(function (j) {
          if (!j || !j.accessToken) throw new Error('No session token (sign in required)');
          S.token = j.accessToken;
          return usage(S.token);
        });
    }
    """

    /// 사용량 요청을 띄우고, 이번 요청을 식별할 시각(ms)을 돌려준다.
    ///
    /// `fetch` 가 비동기라 요청과 읽기를 나눠야 한다. 한 번의 호출로 "요청을 띄우고
    /// 지금 저장된 값을 반환"하면 화면 값이 늘 한 주기 뒤처진다 — 10초 주기에서는
    /// 눈에 띄지 않지만 10분 주기에서는 10분 낡은 값이 보인다.
    static func request(resolver: String, hash: String) -> String {
        """
        (function () {
          var S = window.__uo;
          if (!S) S = window.__uo = { endpoint: null, result: null, resultAt: 0,
                                      err: null, errAt: 0, uuid: null, token: null };
          try { if ('\(hash)' && location.hash !== '\(hash)') location.hash = '\(hash)'; } catch (e) {}
          var mark = Date.now();
          var fail = function (e) { S.err = String(e && e.message ? e.message : e); S.errAt = Date.now(); };
          try {
            var pending = (\(resolver))(S);
            if (pending && pending.then) {
              pending.then(function (j) { S.result = j; S.resultAt = Date.now(); S.err = null; }, fail);
            } else {
              fail('resolver did not return a promise');
            }
          } catch (e) { fail(e); }
          return String(mark);
        })()
        """
    }

    /// 저장된 결과만 읽는다. 새 요청을 띄우지 않는다.
    static let readState = """
    (function () {
      var S = window.__uo;
      if (!S) return JSON.stringify({ resultAt: 0, errAt: 0 });
      return JSON.stringify({ resultAt: S.resultAt, errAt: S.errAt, err: S.err, result: S.result });
    })()
    """
}
