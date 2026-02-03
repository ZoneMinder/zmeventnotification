* `zmeventnotification.pl` is the main Event Server that works with ZoneMinder
* To test it, run it as `sudo -u www-data ./zmeventnotification.pl <options>`
* If you need to access DB, configs etc, access it as `sudo -u www-data`
* Follow DRY principles for coding
* Always write simple code
* Use conventional commit format for all commits:
  * `feat:` new features
  * `fix:` bug fixes
  * `refactor:` code restructuring without behavior change
  * `docs:` documentation only
  * `chore:` maintenance, config, tooling
  * `test:` adding or updating tests
  * Scope is optional: `feat(install):`, `refactor(config):`, etc.
* NEVER create issues, PRs, or push to the upstream repo (`ZoneMinder/zmeventnotification`). ALL issues, PRs, and pushes MUST go to `pliablepixels/zmeventnotification` (origin).
* If you are fixing bugs or creating new features, the process MUST be:
    - Create a GH issue on `pliablepixels/zmeventnotification` (label it)
    - If developing a feature, create a branch
    - Commit changes referring the issue
    - Wait for the user to confirm before you close the issue

