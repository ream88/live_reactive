# Changelog

## Unreleased

- `<.reactive>` takes `as` (`div`, `span` or `tr`) and passes global attributes
  through, so a block can be a table row or sit inside a paragraph.
- The registry of what each block shows moved from an assign to the process
  dictionary. As an assign it re-rendered the whole LiveView once per block on
  every mount.
- No JavaScript. A block renders a `template` keyed by its revision, and
  `phx-mounted` runs the block's `on_update` when a change lands. Installing is
  one dependency: nothing to import, register or bundle.

## 0.1.0

First release.
