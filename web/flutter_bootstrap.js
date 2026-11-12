{{flutter_js}}
{{flutter_build_config}}

(async () => {
  // Retire only the Flutter worker for this App's scope before loading a release
  // that no longer uses the deprecated offline cache.
  if ('serviceWorker' in navigator) {
    try {
      const scope = new URL('.', document.baseURI).href;
      const worker = new URL('flutter_service_worker.js', scope).href;
      const registrations = await navigator.serviceWorker.getRegistrations();
      const obsolete = registrations.filter(registration =>
        registration.scope === scope &&
        [registration.active, registration.waiting, registration.installing]
          .some(candidate => candidate?.scriptURL === worker));
      const controlled = obsolete.length > 0 &&
        navigator.serviceWorker.controller?.scriptURL === worker;
      await Promise.all(obsolete.map(registration => registration.unregister()));
      if (controlled) {
        location.reload();
        return;
      }
    } catch (_) {
      // Worker cleanup must not prevent the App from starting.
    }
  }
  _flutter.loader.load();
})();
