(function () {
  function clean(s) {
    return (s || '').replace(/\s+/g, ' ').trim();
  }

  function pick(root, selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var el = root.querySelector(selectors[i]);
      if (el) {
        var t = clean(el.innerText || el.textContent);
        if (t) return t;
      }
    }
    return '';
  }

  function jobKey(card) {
    var link = card.querySelector('a[data-jk], a.jcs-JobTitle, h2.jobTitle a, a[href*="jk="], a[href*="vjk="]');
    if (!link) return '';
    var jk = link.getAttribute('data-jk') || '';
    if (!jk) {
      var href = link.getAttribute('href') || '';
      var m = href.match(/[?&](?:jk|vjk)=([0-9a-f]+)/i);
      if (m) jk = m[1];
    }
    return jk;
  }

  function findCards() {
    var cards = Array.prototype.slice.call(document.querySelectorAll('div.job_seen_beacon, div.cardOutline, div[data-testid="slider_item"]'));
    if (cards.length) return cards;
    // Fallback: walk up from each job link to its list item.
    var links = document.querySelectorAll('a[data-jk]');
    var out = [];
    for (var i = 0; i < links.length; i++) {
      out.push(links[i].closest('li') || links[i].parentElement);
    }
    return out;
  }

  window.__jobitIndeed = function () {
    var cards = findCards();
    var seen = {};
    var out = [];
    for (var i = 0; i < cards.length; i++) {
      var card = cards[i];
      if (!card) continue;
      var jk = jobKey(card);
      if (!jk || seen[jk]) continue;
      seen[jk] = true;

      var title = pick(card, [
        'h2.jobTitle span[title]',
        'h2.jobTitle a span',
        'h2.jobTitle',
        'a.jcs-JobTitle'
      ]);
      var titleEl = card.querySelector('h2.jobTitle span[title]');
      if (titleEl && titleEl.getAttribute('title')) title = clean(titleEl.getAttribute('title'));

      var company = pick(card, ['[data-testid="company-name"]', 'span.companyName']);
      var place = pick(card, ['[data-testid="text-layout"]', '[data-testid="company-location"]', 'div.companyLocation']);
      var snippet = pick(card, ['.job-snippet', '[data-testid="jobsnippet_footer"]', 'ul']);

      var text = clean(card.innerText);
      var pay = text.match(/\$[0-9][0-9,]*(?:\.[0-9]+)?(?:\s*[kK])?(?:\s*-\s*\$[0-9][0-9,]*(?:\.[0-9]+)?(?:\s*[kK])?)?(?:\s+an? (?:hour|year|month|week|day))?/);

      out.push({
        jk: jk,
        title: title,
        company: company,
        location: place,
        snippet: snippet,
        salary: pay ? pay[0] : '',
        easy: /easily apply/i.test(text)
      });
    }
    return JSON.stringify(out);
  };
})();
