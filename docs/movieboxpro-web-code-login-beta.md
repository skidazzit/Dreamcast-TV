# MovieBox Pro web Code Login: DreamCAST beta

Source: user-supplied `code_login` HTML and `device_bind.js` from their own
browser. No real code, account cookie, or session value is stored here.

## Confirmed browser flow

1. The `code_login` page displays an eight-digit code in the `qrcode` element.
2. An inline script polls `POST /index/login/captcha_query` with an HTML form
   field named `qr_code` every 1,500 milliseconds.
3. The local timer expires after 120,000 milliseconds and asks the user to
   reload the page for a new code.
4. The script treats JSON `code == 1` as approval. The reply can contain
   account session fields, and the website redirects to its home page.

The site's `device_bind.js` creates browser IDs in `ci` and `cl` cookies and
contains browser-specific session restore logic. It does not make the
code-approval request itself.

## Beta implementation

The DreamCAST beta uses an HTTPS `URLSession` with an **in-memory** cookie
store. A fresh local ID is created for the pairing session. It loads the
code-login page, extracts only the numeric code, and checks its status until
approval, expiry, error, or cancellation. The UI never logs the code.

This path uses the public website's browser flow. It does not copy app-held
Android keys or use the Android encrypted API.

## Approved session storage

After the phone approves a code, DreamCAST checks for the website's `ui` and
optional `ci` account values. It accepts values from the approval response or
provider-owned cookies. If an account value exists, it saves these fields in
the Apple TV Keychain under a MovieBox-only service name. Storage is restricted
to the current device. No account values are written to logs or ordinary app
preferences. On the next launch, DreamCAST restores these fields as web
cookies for the provider's HTTPS host.

The Account page distinguishes **code approved** from **session saved**. A
**Forget session** button removes the local Keychain record and clears the
provider's cookies in the active URL session. This is not server-side revocation.

## Read-only Movies pilot

The user supplied an HTML response from `GET /movie` (`200 OK`, `text/html`).
It contains movie cards with numeric `/movie/<id>` links, title attributes, and
HTTPS poster URLs in CSS backgrounds. The sample page had 20 such cards. The
response itself is **not** committed to the repository because it contains
private account content.

The beta Movies tab requests that page using the saved web session, parses
only movie links, titles, and HTTPS posters, and displays focusable cards.
The parser does not execute website scripts or extract profile data. Cards
show a placeholder when opened because detail and playback APIs are not yet
verified. It only loads the first page and does not paginate yet.

## Read-only TV Shows pilot

The user also supplied HTML from the site's TV Shows page. It has 20 numeric
`/tvshow/<id>` links with title attributes and CSS poster images. The response
is not stored in the repository, as it may contain private account content.

The TV Shows tab requests `GET /tvshow` with the saved session, then shows
focusable cards. It shares the movie poster layout and loading controls.
Selecting a show shows a placeholder. There is no season or episode access,
pagination, playback, or download support in this pilot.

## Limits and test notes

- The website may reject automated requests or change its HTML. This has not
  been tested against the live service in this environment.
- Approval or Keychain storage is **not** proof the account session is valid.
  The movie grid has been tested in the user's simulator. The new TV Shows
  grid still needs a live simulator test. We need session validation,
  pagination, account-level sign-out or device revocation, detail and playback
  checks.
- The pilot does not fetch playable video or launch playback.
- Live tests should use the user's own account. Never send login codes,
  cookies, tokens, or full unsanitized network captures in bug reports.
