# MovieBox Pro 16.5 — offline IPA notes

Source: user-provided `MovieBoxPro_16.5.ipa`. Static inspection only. No login,
service calls, traffic capture, signing keys, or playback tests were performed.

## Package identity

| Field | Observed value |
| --- | --- |
| Bundle ID | `com.xd.mbp31` |
| Version | `16.5` |
| Platforms | `iPhoneOS`; device families 1 and 2 |
| SDK in package | `iphoneos27.1` |
| URL schemes | `movieboxpro`, `MovieBoxPro` |

The supplied package is **not** a tvOS binary. Its origin and signature have
not been independently verified. It cannot be copied into DreamCAST as a tvOS
player.

## Components found in the app package

- `GoogleAdsSDK.framework` contains the MovieBox-specific Swift classes and
  operation names, despite the framework's name.
- `Moya` and `Alamofire` are present for network requests.
- `GoogleSignIn`, `AppAuth`, and `KeychainAccess` are present.
- `MobileVLCKit`, `ffmpegkit`, and FFmpeg libraries are present.
- The app queries whether external players such as Infuse and VLC are installed.
  That is **not** evidence that it embeds the Infuse engine.

## Observed operation names

These strings are labels in the compiled iOS app, **not** proven HTTP paths,
verbs, payload fields, or successful responses.

| Area | Strings found in the binary |
| --- | --- |
| Home/catalog | `Home_list_type_v5`, `MovieList`, `MovieDetail`, `TVShowsDetail` |
| Series | `TV_detail_playlist`, `TVShowsEpisode` |
| Sign-in | `Login_qrcode_v2`, `Scan_login_qrcode_v2`, `Login_google_v2` |
| Stream selection | `Movie_downloadurl_v4`, `TV_downloadurl_v4`, `MovieSource`, `TVSource` |
| Watch progress | `Movie_play_progress`, `TV_play_progress`, `Movie_play_record` |
| Subtitles | `Movie_srt_list_v3`, `TV_srt_delay_list_v2` |

Visible API-related hosts include `mbpssl.shegu.net/api` and
`video-thumbs-web1.shegu.net/api/api_client_ssl`. These differ from the
`/wefeed-mobile-bff/` AOneRoom routes in the user-supplied Android API guide.
Do not assume they speak the same protocol.

## What is still unverified

1. Supported API access and account sign-in for an independent tvOS client.
2. The request methods, parameter names, and response JSON for each operation.
3. Whether stream URLs are granted for the user's account and usable on tvOS.
4. How entitlement, stream expiry, track selection, and watch progress work.

## Safe integration boundary

The `MovieBoxContracts.swift` types describe a possible DreamCAST-side model.
They are not wire decoders. No MovieBox Pro server is contacted. Nothing is
registered in `MediaProviderRegistry`, shown in the app, or used for playback.
Plex and AetherEngine are untouched.

Do not use client-identity spoofing, extracted app secrets, hidden CDN URL
reconstruction, entitlement spoofing, DRM workarounds, or geo-block bypasses.
Only add a live adapter after a supported account and API flow is verified.
