(function () {
  function norm(s) {
    return (s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  }

  function labelText(el) {
    var t = '';
    if (el.id) {
      var l = document.querySelector('label[for="' + String(el.id).replace(/"/g, '\\"') + '"]');
      if (l) t = l.innerText;
    }
    if (!t) {
      var p = el.closest('label');
      if (p) t = p.innerText;
    }
    if (!t && el.getAttribute('aria-labelledby')) {
      var ids = el.getAttribute('aria-labelledby').split(' ');
      t = ids.map(function (i) {
        var n = document.getElementById(i);
        return n ? n.innerText : '';
      }).join(' ');
    }
    if (!t) t = el.getAttribute('aria-label') || el.placeholder || el.name || '';
    return String(t).replace(/\s+/g, ' ').replace(/\*/g, '').trim();
  }

  function setValue(el, v) {
    var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
    setter.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function setSelect(el, v) {
    var want = norm(v);
    for (var i = 0; i < el.options.length; i++) {
      var o = norm(el.options[i].text);
      if (o === want || (want.length > 2 && o.indexOf(want) !== -1)) {
        el.selectedIndex = i;
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      }
    }
    return false;
  }

  function find(lab, entries) {
    var best = null;
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i];
      if (!e.k) continue;
      if (lab === e.k) return e;
      if (e.k.length >= 4 && (lab.indexOf(e.k) !== -1 || (lab.length >= 4 && e.k.indexOf(lab) !== -1))) {
        if (!best || e.k.length > best.k.length) best = e;
      }
    }
    return best;
  }

  function mark(el, color) {
    el.style.outline = '2px solid ' + color;
  }

  window.__jobitFill = function (entries) {
    entries.forEach(function (e) { e.k = norm(e.k); });
    var filled = 0;
    var unknown = [];
    var individual = [];
    var seen = {};
    var skipTypes = ['hidden', 'file', 'submit', 'button', 'checkbox', 'radio', 'password', 'image', 'reset'];
    var els = document.querySelectorAll('input, textarea, select');

    for (var n = 0; n < els.length; n++) {
      var el = els[n];
      var type = (el.type || '').toLowerCase();
      if (skipTypes.indexOf(type) !== -1) continue;
      if (el.disabled || el.readOnly) continue;
      if (el.offsetParent === null) continue;
      if (el.tagName !== 'SELECT' && el.value) continue;
      if (el.tagName === 'SELECT' && el.selectedIndex > 0) continue;

      var raw = labelText(el);
      var lab = norm(raw);
      if (lab.length < 2 || raw.length > 160) continue;

      var hit = find(lab, entries);
      if (hit && hit.i) {
        mark(el, '#f5a623');
        if (!seen[lab]) { seen[lab] = true; individual.push(raw); }
        continue;
      }
      if (hit && hit.a) {
        var ok = true;
        if (el.tagName === 'SELECT') ok = setSelect(el, hit.a);
        else setValue(el, hit.a);
        if (ok) { filled++; mark(el, '#34c759'); continue; }
      }
      mark(el, '#ff3b30');
      if (!seen[lab]) { seen[lab] = true; unknown.push(raw); }
    }
    return JSON.stringify({ filled: filled, unknown: unknown, individual: individual });
  };
})();
