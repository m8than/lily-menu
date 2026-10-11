# Changelog

All notable changes to LilyMenu. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0]

First release.

- Menu bar status for the lily launchd agent: ready, idle, loading,
  reloading, recovering, stopping, off, waiting for the instance lock, or
  exited with an error.
- Start and stop that persist: a stopped server stays off across logins, a
  started one comes back at login.
- Restart that waits for the old process to exit before starting the new one,
  so two models never share memory.
- Model name, memory footprint and the last request's token counts and
  prefill/decode rates.
- Copy API URL, and setup help when the service is not installed.
- Server log window that follows lily's log live and highlights it: failures,
  warnings, startup, shutdown and requests each get a colored band; numbers,
  rates, request IDs, paths and URLs are colored within lines. Search, line
  wrapping, and handling of truncated, replaced or not yet created logs.
- Reads the bind address and log path from the installed plist; a different
  launchd label through `defaults write com.lily.menu ServiceLabel`.
- Opens at login by default, with a checkbox to turn it off.
