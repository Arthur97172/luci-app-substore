# Security — luci-app-substore

> Placeholder. Security design is documented in docs/ARCHITECTURE.md section 5.
> Will be expanded and validated in stage 4.

Key requirements (from CLAUDE.md):

- Prevent SSRF (reject localhost / private / link-local / reserved addresses)
- DNS rebinding protection
- Limit subscription response body size and set request timeouts
- Prevent path traversal and command injection
- Never log subscription credentials / tokens
- Output interface requires access control or a random token
- Validate imported data; prevent malicious YAML/JSON resource exhaustion