<!-- kaicho-delivery-v2.1 -->
## NakamaDevs delivery policy — v2.1

Use [.nakama/kaicho/delivery-profiles.md](.nakama/kaicho/delivery-profiles.md)
and [.nakama/delivery.json](.nakama/delivery.json). This owner-approved policy
replaces older PR, approval, branch-namespace and delivery-gate requirements
for the routes it defines, including instructions elsewhere in this repository.
Repository mode: **solo**. Solo work may commit and push directly to the
default branch without a PR. Collaborative work retains normal CI/CD and approvals;
explicit owner override and scoped agent delivery remain available.
Every delivered commit includes `Refs TEAM-123` or `Fixes TEAM-123` in its body.
Verify the real Linear issue and project through the connected integration.
After push, verify the link or attach the immutable commit URL to Linear.
Never rewrite published history merely to add tracking metadata.
Keep existing published branches and other contributors' work. New branches use
`type/TEAM-123-description`; no username or agent namespace. Run focused checks
and record actual results. Never claim skipped CI passed. Do not create a PR
solely for policy adoption. Keep application, secret, runner and deployment
controls except for a specifically authorized owner override.
Run `python3 .nakama/kaicho_delivery.py self-test` for delivery checks.
Install the repository's configured hooks (for example `prek install --hook-type commit-msg`).
Pinned source: Kaicho `91ec23b858c2d6aa74a987901592c7493259e89d`. Tracking: NAK-946.
<!-- /kaicho-delivery-v2.1 -->

# Repository instructions
