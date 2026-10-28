const authConfirmationPage = `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <meta name="theme-color" content="#0b6b68">
  <title>Correo confirmado | BioMedica</title>
  <style>
    :root { color-scheme: light; font-family: system-ui, sans-serif; color: #173b3b; background: #f2f8f7; }
    body { min-height: 100vh; margin: 0; display: grid; place-items: center; }
    main { box-sizing: border-box; width: min(92vw, 440px); padding: 2rem; border-radius: 1.25rem; background: white; box-shadow: 0 1rem 3rem #173b3b1a; text-align: center; }
    .mark { width: 3.5rem; height: 3.5rem; margin: 0 auto 1rem; border-radius: 50%; display: grid; place-items: center; background: #e2f5ef; color: #0b6b68; font-size: 1.8rem; }
    h1 { margin: 0 0 .75rem; font-size: 1.5rem; }
    p { line-height: 1.55; }
    a { display: inline-block; margin-top: .75rem; padding: .8rem 1.2rem; border-radius: .7rem; background: #0b6b68; color: white; font-weight: 650; text-decoration: none; }
    #status { color: #526969; font-size: .9rem; }
  </style>
</head>
<body>
  <main>
    <div class="mark" aria-hidden="true">✓</div>
    <h1 id="title">Confirmando tu correo</h1>
    <p id="message">Tu correo fue confirmado. Te estamos llevando de regreso a BioMedica.</p>
    <p id="status">Si la app no se abre automáticamente, usa el botón.</p>
    <a id="open-app" href="com.example.biomedica_app://login-callback/">Abrir BioMedica</a>
  </main>
  <script>
    (() => {
      const callbackUrl = 'com.example.biomedica_app://login-callback/' +
        window.location.search + window.location.hash;
      const hasAuthResponse = new URLSearchParams(window.location.search).has('code') ||
        new URLSearchParams(window.location.hash.slice(1)).has('access_token');
      const title = document.getElementById('title');
      const message = document.getElementById('message');
      const status = document.getElementById('status');
      const openApp = document.getElementById('open-app');

      if (!hasAuthResponse) {
        title.textContent = 'No se pudo completar la confirmación';
        message.textContent = 'Abre el enlace de confirmación más reciente que recibiste por correo.';
        status.hidden = true;
        openApp.hidden = true;
        return;
      }

      openApp.href = callbackUrl;
      window.setTimeout(() => window.location.replace(callbackUrl), 500);
    })();
  </script>
</body>
</html>`;

module.exports = { authConfirmationPage };
