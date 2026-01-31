* `zmeventnotification.pl` is the main Event Server that works with ZoneMinder
* To test it, run it as `sudo -u www-data ./zmeventnotification.pl <options>`
* If you need to access DB, configs etc, access it as `www-data`
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

