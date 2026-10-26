(function () {
  function clean(s) {
    return (s || '').replace(/\s+/g, ' ').trim();
  }

  function text(selectors) {
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el && clean(el.innerText)) return clean(el.innerText);
    }
    return '';
  }

  function meta(name) {
    var el = document.querySelector('meta[property="' + name + '"], meta[name="' + name + '"]');
    return el ? clean(el.getAttribute('content')) : '';
  }

  function jobPosting() {
    var nodes = document.querySelectorAll('script[type="application/ld+json"]');
    for (var i = 0; i < nodes.length; i++) {
      try {
        var data = JSON.parse(nodes[i].textContent);
        var list = Array.isArray(data) ? data.slice() : [data];
        if (data && data['@graph']) list = list.concat(data['@graph']);
        for (var j = 0; j < list.length; j++) {
          if (list[j] && list[j]['@type'] === 'JobPosting') return list[j];
        }
      } catch (e) {}
    }
    return null;
  }

  window.__jobitCapture = function () {
    var title = '';
    var company = '';
    var place = '';

    var p = jobPosting();
    if (p) {
      title = clean(p.title);
      if (p.hiringOrganization && p.hiringOrganization.name) company = clean(p.hiringOrganization.name);
      var loc = p.jobLocation;
      if (Array.isArray(loc)) loc = loc[0];
      if (loc && loc.address) {
        place = [loc.address.addressLocality, loc.address.addressRegion].filter(Boolean).join(', ');
      }
    }

    if (!title) {
      title = text([
        '.job-details-jobs-unified-top-card__job-title h1',
        '.job-details-jobs-unified-top-card__job-title',
        '.jobs-unified-top-card__job-title',
        'h1.jobsearch-JobInfoHeader-title',
        '[data-testid="jobsearch-JobInfoHeader-title"]',
        'h1'
      ]);
    }
    if (!company) {
      company = text([
        '.job-details-jobs-unified-top-card__company-name',
        '.jobs-unified-top-card__company-name',
        '[data-company-name="true"]',
        '[data-testid="inlineHeader-companyName"]'
      ]);
    }
    if (!place) {
      place = text([
        '[data-testid="inlineHeader-companyLocation"]',
        '[data-testid="job-location"]',
        '.job-details-jobs-unified-top-card__primary-description-container .tvm__text',
        '.jobs-unified-top-card__bullet'
      ]);
    }
    if (!title) title = meta('og:title') || clean(document.title);

    return JSON.stringify({
      title: title,
      company: company,
      location: place,
      url: window.location.href
    });
  };
})();
