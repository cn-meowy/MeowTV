(function () {
  'use strict';

  var STORAGE_KEY = 'meowtv.lang';
  var DEFAULT_LANG = 'zh';

  function safeGet(key) {
    try {
      return window.localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  function safeSet(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch (e) {
      /* file:// may throw — silently ignore */
    }
  }

  function detectInitialLang() {
    var saved = safeGet(STORAGE_KEY);
    if (saved === 'zh' || saved === 'en') return saved;
    var nav = (navigator && navigator.language) || '';
    if (nav.toLowerCase().indexOf('zh') === 0) return 'zh';
    return 'en';
  }

  function setLang(lang) {
    document.documentElement.setAttribute('lang', lang);
    safeSet(STORAGE_KEY, lang);

    var titleEl = document.querySelector('[data-title-zh]');
    if (titleEl) {
      document.title = lang === 'zh' ? titleEl.getAttribute('data-title-zh') : titleEl.getAttribute('data-title-en');
    }

    var btns = document.querySelectorAll('.lang-toggle');
    for (var i = 0; i < btns.length; i++) {
      btns[i].textContent = lang === 'zh' ? 'English' : '中文';
      btns[i].setAttribute('aria-label', lang === 'zh' ? 'Switch to English' : '切换到中文');
    }
  }

  function toggleLang() {
    var current = document.documentElement.getAttribute('lang') || DEFAULT_LANG;
    setLang(current === 'zh' ? 'en' : 'zh');
  }

  document.addEventListener('DOMContentLoaded', function () {
    setLang(detectInitialLang());

    var btns = document.querySelectorAll('.lang-toggle');
    for (var i = 0; i < btns.length; i++) {
      btns[i].addEventListener('click', toggleLang);
    }
  });
})();