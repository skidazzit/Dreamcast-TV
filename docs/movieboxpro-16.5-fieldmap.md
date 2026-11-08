# MovieBox Pro 16.5 — candidate data fields

These names came from the user-provided IPA's Swift reflection metadata. They
were found in `GoogleAdsSDK.framework/GoogleAdsSDK`, which also contains
`MBAPIManager.swift` paths and the MovieBox-specific app code.

The Swift field metadata was parsed **offline**. It does not establish the
actual API URL, HTTP verb, request body, response wrapper, or account access
rules. Treat every group below as a **candidate model**, not a verified JSON
contract.

| Candidate data | Observed field names |
| --- | --- |
| Movie/series detail | `id`, `mid`, `tid`, `title`, `synopsis`, `released`, `imdb_id`, `mb_id`, `thumbs`, `thumbs_min`, `thumbs_org`, `quality_tag` |
| Episode | `season`, `episode`, `seconds`, `runtime`, `title`, `thumbs` |
| Stream file | `fid`, `fileName`, `format`, `lang`, `m3u8_url`, `quality`, `vip_only`, `hdr`, `is_h265`, `file_size`, `bitrate`, `fps` |
| Download file | `format`, `path`, `path2`, `fileName`, `encode`, `quality`, `bitstream`, `vipOnly`, `hdr` |
| Play progress | `season`, `episode`, `seconds`, `runtime`, `over` |

The `MovieBoxLegacyTitleMapper` uses only candidate movie/series fields to
decode a **supplied JSON record** into DreamCAST's internal catalog shape.
It accepts string or integer IDs and rejects non-HTTPS poster links. Tests use
synthetic examples only. This does not make requests or expose a MovieBox tab.

## Still needed before a live provider

- Verify a service-approved account flow.
- Verify real response schemas and pagination.
- Validate playback URLs with the current account's own rights.
- Confirm tvOS playback format and memory use.

No app identity spoofing, VIP bypass, extracted secrets, hidden CDN URL
reconstruction, or DRM changes are included.
