# MovieBox Pro TV 13.4 (126): code-login contract notes

Source: user-provided Android TV APK
`MovieBoxProtv_2026-10-29-19-47_13.4_126_movie_tvRelease.apk`.

These notes come from read-only inspection of `classes5.dex`. They describe
observable client call sites and Retrofit annotations. They are **not** a
working or approved API, and no requests were sent to MovieBox Pro.

## Observed app flow

1. `CodeLoginFragmentPresenter.getCode()` calls
   `APIService.Add_captcha("Add_captcha")`.
2. Its success handler reads a JSON field named `code` and calls the view's
   `showCode` method.
3. `CodeLoginFragmentPresenter.checkCode()` calls
   `APIService.checkCodeLogin("Login_captcha_v2", openudid, code)` while the
   account is awaiting approval.
4. The response passes through `LoginResponseParser.rxTranslate2LoginUserData`.
   The success handler then starts `beginDeviceBinding()`.
5. The binding flow calls `APIService.Device("Device_v3", ...)` and, after
   saving the account, signals `loginSuccess()`.

## Retrofit method details

| Client method | Declared route | Request fields |
| --- | --- | --- |
| `Add_captcha` | `POST api/{module}` | Path `module` = `Add_captcha`; no declared form fields |
| `checkCodeLogin` | `POST api/{module}` | Path `module` = `Login_captcha_v2`; form fields `openudid`, `code` |
| `Device` | `POST api/{module}` | Path `module` = `Device_v3`; device binding and session fields |

**Important:** These Retrofit declarations are not necessarily the final wire
URLs. The TV app builds a custom HTTP v2 client using
`ApiV2RequestInterceptor` and `ApiEncryptV2`. Its endpoint configuration refers
to `api_client_ssl_encrypt`. Therefore a plain `URLSession` request to
`api/Add_captcha` has **not** been shown to work.

## Remaining checks before enabling sign-in

- Confirm the legitimate TV-code request and polling exchange on the user's
  own account, including final URL and safe non-secret request fields.
- Confirm response status values, code expiry, and retry pace.
- Confirm how approval produces a valid account session and how the session
  is stored or revoked.
- Confirm that server rules allow the separate tvOS client to use this flow.
- Test error handling: no connection, expired code, duplicate account, failed
  device binding, and canceled sign-in.

The DreamCAST beta keeps its code state as `Not issued` until these checks are
complete. No codes are made up, and this work does not copy app secrets,
forge device identity, skip account approval, or bypass media rights.
