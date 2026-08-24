'use strict';

(function () {
  // ---------- 工具 ----------
  var $ = function (sel) { return document.querySelector(sel); };

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function weekdayCn(dateStr) {
    try {
      var d = new Date(String(dateStr) + 'T00:00:00');
      if (isNaN(d.getTime())) return '';
      return '星期' + '日一二三四五六'[d.getDay()];
    } catch (e) { return ''; }
  }

  var state = {
    report: null,
    latestDate: null,
    history: []
  };

  // ---------- 数据加载 ----------
  function loadJSON(url) {
    return fetch(url, { cache: 'no-store' }).then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return res.json();
    });
  }

  function showLoading() {
    $('#app').innerHTML = '<div class="loading"><div class="spinner"></div><p>正在加载今日早报…</p></div>';
  }

  function showError() {
    $('#app').innerHTML =
      '<div class="error-box">' +
      '<div class="big">🌙</div>' +
      '<p>还没有可显示的早报</p>' +
      '<p class="hint">请先在电脑端双击「启动手机版.cmd」，并确认「每日经济早报」自动化已在工作日 8:30 生成报告。<br>报告会写入 data/latest.json，刷新本页即可查看。</p>' +
      '</div>';
  }

  function loadLatest(silent) {
    if (!silent) showLoading();
    return loadJSON('data/latest.json').then(function (r) {
      state.report = r;
      state.latestDate = (r.meta && r.meta.date) || '';
      render();
      toast('已加载最新早报');
    }).catch(function () {
      if (!silent) showError();
      else toast('刷新失败：请确认电脑端服务器在运行');
    });
  }

  function loadHistory() {
    return loadJSON('data/history.json').then(function (h) {
      state.history = Array.isArray(h) ? h : (h.items || []);
    }).catch(function () {
      state.history = [];
    });
  }

  // ---------- 渲染 ----------
  function render() {
    var r = state.report;
    if (!r) { showError(); return; }
    var meta = r.meta || {};
    document.title = '每日经济早报 · ' + (meta.date || '');

    $('#metaBar').hidden = false;
    $('#dateChip').textContent = (meta.date || '—') + (meta.weekday ? ' ' + meta.weekday : '');
    $('#cutoffChip').textContent = meta.dataCutoff || '';
    var off = $('#offlineChip');
    off.hidden = !!navigator.onLine;

    var app = $('#app');
    app.innerHTML = '';

    app.appendChild(section('一', '今日焦点速览', '30 秒版', renderFocus(r.focus)));
    app.appendChild(section('二', '中国：政策与数据', '', renderChina(r.china)));
    app.appendChild(section('三', '全球市场与央行', '', renderGlobal(r.global)));
    app.appendChild(section('四', '大类资产表现', '数据截至最近交易日', renderAssets(r.assets)));
    app.appendChild(section('五', '今日 / 本周重要日程', '', renderSchedule(r.schedule)));
    app.appendChild(section('六', '经济学学习视角', '先思考再看答案', renderLearning(r.learning)));
    if (r.tracker && r.tracker.length) {
      app.appendChild(section('七', '关键指标追踪', '每周更新', renderTracker(r.tracker)));
    }

    // 若正在查看历史报告，显示“回到最新”
    var back = $('#backLatest');
    if (back) {
      back.hidden = !(state.latestDate && meta.date && state.latestDate !== meta.date);
    }

    window.scrollTo(0, 0);
    setProgress(100);
    setTimeout(function () { setProgress(0); }, 600);
  }

  function section(num, title, tag, bodyHtml) {
    var sec = document.createElement('section');
    sec.className = 'section';
    var head = document.createElement('div');
    head.className = 'section-head';
    head.innerHTML = '<span class="num">' + esc(num) + '</span><h2>' + esc(title) + '</h2>' +
      (tag ? '<span class="tag">' + esc(tag) + '</span>' : '');
    var body = document.createElement('div');
    body.className = 'section-body';
    body.innerHTML = bodyHtml || '<p class="empty">—</p>';
    sec.appendChild(head);
    sec.appendChild(body);
    return sec;
  }

  // 一、焦点速览
  var FOCUS_META = [
    { key: 'chinaPolicy', label: '🇨🇳 中国政策' },
    { key: 'chinaData', label: '📊 中国数据' },
    { key: 'globalCentralBanks', label: '🏦 全球央行' },
    { key: 'assets', label: '💹 大类资产' },
    { key: 'industry', label: '🏭 产业/公司' }
  ];

  function renderFocus(f) {
    if (!f) return '';
    return FOCUS_META.map(function (m) {
      var txt = f[m.key];
      if (!txt) return '';
      return '<div class="focus-row">' +
        '<div class="focus-ico">' + esc(m.label.split(' ')[0]) + '</div>' +
        '<div><div class="focus-label">' + esc(m.label) + '</div>' +
        '<div class="focus-text">' + esc(txt) + '</div></div></div>';
    }).join('');
  }

  // 二、中国
  function bulletList(arr) {
    if (!arr || !arr.length) return '';
    return '<ul class="bullets">' + arr.map(function (x) {
      return '<li>' + esc(x) + '</li>';
    }).join('') + '</ul>';
  }

  function renderChina(c) {
    if (!c) return '';
    var html = '';
    if (c.policy && c.policy.length) html += subTitle('政策动态') + bulletList(c.policy);
    if (c.data && c.data.length) html += subTitle('最新经济数据') + bulletList(c.data);
    if (c.highlights && c.highlights.length) html += subTitle('结构亮点') + bulletList(c.highlights);
    return html;
  }

  function subTitle(t) {
    return '<div class="sub-title">' + esc(t) + '</div>';
  }

  // 三、全球
  function renderGlobal(g) {
    if (!g) return '';
    var html = '';
    if (g.centralBanks && g.centralBanks.length) {
      html += subTitle('主要央行');
      html += '<ul class="bullets">' + g.centralBanks.map(function (b) {
        return '<li><b>' + esc(b.name || '') + '</b>：' + esc(b.content || '') + '</li>';
      }).join('') + '</ul>';
    }
    if (g.bondsFx && g.bondsFx.length) html += subTitle('债市与汇市') + bulletList(g.bondsFx);
    if (g.geopolitics && g.geopolitics.length) html += subTitle('地缘与贸易') + bulletList(g.geopolitics);
    return html;
  }

  // 四、资产
  function changeDir(c) {
    var s = String(c == null ? '' : c).trim();
    if (/^[-－]/.test(s)) return 'down';
    if (/^[+]/.test(s)) return 'up';
    if (/跌|下|降|回落/.test(s)) return 'down';
    if (/涨|升|上|走高|创新高/.test(s)) return 'up';
    return 'flat';
  }

  function renderAssets(arr) {
    if (!arr || !arr.length) return '';
    var html = '<div class="asset-grid">';
    arr.forEach(function (a) {
      var dir = changeDir(a.change);
      html += '<div class="asset-card ' + dir + '">' +
        '<div class="asset-name">' + esc(a.name) + '</div>' +
        '<div class="asset-value">' + esc(a.value) +
        (a.unit ? '<span class="unit"> ' + esc(a.unit) + '</span>' : '') + '</div>' +
        '<span class="asset-change ' + dir + '">' + esc(a.change || '—') + '</span>' +
        (a.comment ? '<div class="asset-comment">' + esc(a.comment) + '</div>' : '') +
        '</div>';
    });
    html += '</div>';
    html += '<div class="legend"><span><i class="u"></i>上涨（红）</span><span><i class="d"></i>下跌（绿）</span><span>按 A 股习惯配色</span></div>';
    return html;
  }

  // 五、日程
  function renderSchedule(arr) {
    if (!arr || !arr.length) return '';
    return arr.map(function (s) {
      return '<div class="sched-row">' +
        '<div class="sched-time">' + esc(s.time || '—') + '</div>' +
        '<div class="sched-body">' +
        '<div class="sched-event">' + esc(s.event || '') + '</div>' +
        (s.watch ? '<div class="sched-watch">👀 ' + esc(s.watch) + '</div>' : '') +
        '</div></div>';
    }).join('');
  }

  // 六、学习视角
  function renderLearning(arr) {
    if (!arr || !arr.length) return '';
    var html = '<div class="quiz-wrap">';
    arr.forEach(function (q, i) {
      html += '<div class="quiz-card" data-i="' + i + '">' +
        (q.concept ? '<span class="quiz-concept">📖 ' + esc(q.concept) + '</span>' : '') +
        '<div class="quiz-q"><span class="q-no">Q' + (i + 1) + '.</span>' + esc(q.question || '') + '</div>' +
        '<button type="button" class="quiz-toggle"><span class="arr">▸</span><span>查看参考答案</span></button>' +
        '<div class="quiz-answer">' + esc(q.answer || '') + '</div>' +
        '</div>';
    });
    html += '</div>';
    return html;
  }

  // 七、追踪
  function renderTracker(arr) {
    var html = '<div class="tracker-wrap">';
    arr.forEach(function (t) {
      html += '<div class="tracker-row">' +
        '<span class="tracker-name">' + esc(t.name || '') + '</span>' +
        '<span class="tracker-val">' + esc(t.value || '—') + '</span>' +
        '<span class="tracker-freq">' + esc(t.freq || '') + '</span>' +
        '</div>' +
        (t.note ? '<div class="tracker-note">' + esc(t.note) + '</div>' : '');
    });
    html += '</div>';
    return html;
  }

  // ---------- 历史抽屉 ----------
  function openDrawer() {
    var scrim = $('#scrim'), drawer = $('#drawer');
    scrim.hidden = false;
    drawer.hidden = false;
    var list = $('#drawerList');
    list.innerHTML = '';
    if (!state.history.length) {
      list.innerHTML = '<li class="drawer-empty">暂无历史早报</li>';
    } else {
      state.history.slice().reverse().forEach(function (item) {
        var date = item.date || '';
        var week = item.weekday || weekdayCn(date);
        var li = document.createElement('li');
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'drawer-item';
        var isCur = state.report && state.report.meta && state.report.meta.date === date;
        btn.innerHTML = '<span class="d-date">' + esc(date || '—') +
          (isCur ? ' <span class="chip chip-accent" style="font-size:10px">当前</span>' : '') +
          '</span><span class="d-week">' + esc(week) + '</span>';
        btn.addEventListener('click', function () {
          openReport(item);
        });
        li.appendChild(btn);
        list.appendChild(li);
      });
    }
  }

  function closeDrawer() {
    $('#scrim').hidden = true;
    $('#drawer').hidden = true;
  }

  function openReport(item) {
    var file = String(item.file || '').replace(/^.*[\\/]/, '');
    if (!/^[A-Za-z0-9_\-\.]+\.json$/.test(file)) { toast('无效的报告文件'); return; }
    closeDrawer();
    showLoading();
    loadJSON('data/reports/' + file).then(function (r) {
      state.report = r;
      render();
      toast('已打开 ' + (r.meta && r.meta.date ? r.meta.date : file));
    }).catch(function () {
      showError();
    });
  }

  // ---------- Toast ----------
  var toastTimer = null;
  function toast(msg) {
    var t = $('#toast');
    t.textContent = msg;
    t.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, 2400);
  }

  // ---------- 进度条 ----------
  function setProgress(p) {
    var bar = $('#progressBar');
    bar.style.width = p + '%';
    if (p === 0) bar.style.opacity = '0'; else bar.style.opacity = '1';
  }

  // ---------- 事件绑定 ----------
  function bind() {
    $('#refreshBtn').addEventListener('click', function () { loadLatest(true); });
    $('#backLatest').addEventListener('click', function () { loadLatest(true); });
    $('#historyBtn').addEventListener('click', function () {
      loadHistory().then(openDrawer);
    });
    $('#drawerClose').addEventListener('click', closeDrawer);
    $('#scrim').addEventListener('click', closeDrawer);

    // 答案折叠
    $('#app').addEventListener('click', function (e) {
      var btn = e.target.closest ? e.target.closest('.quiz-toggle') : null;
      if (btn) {
        var card = btn.parentNode;
        card.classList.toggle('open');
        btn.querySelector('.arr').textContent = card.classList.contains('open') ? '▾' : '▸';
      }
    });

    // 阅读进度
    window.addEventListener('scroll', function () {
      var doc = document.documentElement;
      var max = doc.scrollHeight - window.innerHeight;
      var p = max > 0 ? (window.scrollY / max) * 100 : 0;
      setProgress(p);
    }, { passive: true });
  }

  // ---------- 启动 ----------
  function init() {
    bind();
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('sw.js').catch(function () {});
    }
    loadLatest(false);
  }

  document.addEventListener('DOMContentLoaded', init);
})();