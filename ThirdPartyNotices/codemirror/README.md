# CodeMirror editor notices

The generated offline Markdown editor bundle contains the following packages
resolved by `scripts/markdown-editor/package-lock.json`.

| Package | Version | License file |
| --- | --- | --- |
| @codemirror/commands | 6.11.0 | LICENSE-codemirror.txt |
| @codemirror/lang-markdown | 6.5.2 | LICENSE-codemirror.txt |
| @codemirror/language | 6.12.4 | LICENSE-codemirror.txt |
| @codemirror/state | 6.7.4 | LICENSE-codemirror.txt |
| @codemirror/view | 6.43.11 | LICENSE-codemirror.txt |
| @lezer/common | 1.5.2 | LICENSE-lezer.txt |
| @lezer/highlight | 1.2.3 | LICENSE-lezer.txt |
| @lezer/markdown | 1.7.2 | LICENSE-lezer-markdown.txt |
| @marijn/find-cluster-break | 1.0.4 | LICENSE-find-cluster-break.txt |
| style-mod | 4.1.3 | LICENSE-style-mod.txt |
| w3c-keyname | 2.2.8 | LICENSE-w3c-keyname.txt |

The source repositories and non-bundled transitive packages are recorded in the
package lock. Build and test tools such as esbuild and jsdom are not shipped in
the generated runtime bundle.
