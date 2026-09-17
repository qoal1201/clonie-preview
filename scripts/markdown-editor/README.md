# Clonie Markdown editor bundle

This directory builds the offline CodeMirror 6 editor embedded in `ChatHTML.swift`.
Runtime code never loads a CDN, local file, or network resource.

```sh
cd scripts/markdown-editor
npm ci
npm run build
npm test
```

The build pins every npm package through `package-lock.json`, bundles an IIFE named
`ClonieMarkdownEditor`, verifies that evaluating the bundle does not require browser
globals, rejects a raw closing `script` tag, and regenerates
`Sources/Clonie/Resources/MarkdownEditor.swift`.

`mount(textarea, {documentID, title})` replaces a real textarea with CodeMirror and
returns its content DOM element with the textarea-compatible properties used by the
Clonie screen. `destroyDetached()` and `destroyAll()` release views; `reset()` also
clears the bounded per-document undo-state cache.
