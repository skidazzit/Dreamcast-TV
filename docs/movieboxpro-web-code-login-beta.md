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

## Limits and test notes

- The website may reject automated requests or change its HTML. This has not
  been tested against the live service in this environment.
- Approval is **not** proof that DreamCAST's MovieBox catalog is ready.
  Catalog access, durable session storage, session validation, and sign-out
  still need separate work.
- The pilot does not fetch or play MovieBox media.
- Live tests should use the user's own account. Never send login codes,
  cookies, tokens, or full unsanitized network captures in bug reports.
