import {
  defaultKeymap,
  history,
  historyKeymap,
  redo as redoCommand,
  undo as undoCommand
} from "@codemirror/commands";
import { markdownKeymap, markdownLanguage } from "@codemirror/lang-markdown";
import { syntaxTree } from "@codemirror/language";
import { EditorSelection, EditorState, StateEffect, StateField, Transaction } from "@codemirror/state";
import {
  Decoration,
  EditorView,
  ViewPlugin,
  WidgetType,
  keymap
} from "@codemirror/view";

const CACHE_LIMIT = 16;
const active = new Set();
const cachedStates = new Map();
const suppressInput = new WeakSet();
const OPEN_LINK_HINT = "⌘클릭 또는 ⌘Enter로 링크 열기";

function linkFromNode(source, node) {
  if (node?.name !== "Link") return null;
  const url = node.getChild("URL");
  if (!url) return null;

  let labelOpen = null;
  let labelClose = null;
  for (let child = node.firstChild; child; child = child.nextSibling) {
    if (child.name !== "LinkMark") continue;
    const mark = source.slice(child.from, child.to);
    if (!labelOpen && mark === "[") labelOpen = child;
    else if (labelOpen && mark === "]") {
      labelClose = child;
      break;
    }
  }
  if (!labelOpen || !labelClose || labelClose.from < labelOpen.to) return null;

  const target = source.slice(url.from, url.to);
  if (!target) return null;
  return {
    from: node.from,
    to: node.to,
    label: source.slice(labelOpen.to, labelClose.from),
    target
  };
}

function extractLinks(source, tree) {
  const result = [];
  tree.iterate({
    enter(cursor) {
      if (cursor.name !== "Link") return;
      const link = linkFromNode(source, cursor.node);
      if (link) result.push(link);
      return false;
    }
  });
  return result;
}

function links(source) {
  const text = String(source ?? "");
  return extractLinks(text, markdownLanguage.parser.parse(text));
}

function stateLinks(state) {
  const source = state.doc.toString();
  return extractLinks(source, syntaxTree(state));
}

function linkAt(state, position, preferredFrom = null) {
  const found = stateLinks(state);
  if (Number.isInteger(preferredFrom)) {
    const preferred = found.find(link => link.from === preferredFrom);
    if (preferred) return preferred;
  }
  const pos = Math.max(0, Math.min(state.doc.length, Number(position) || 0));
  return found.find(link => link.from <= pos && pos < link.to) ||
    found.find(link => link.to === pos && link.from < link.to) || null;
}

function pointerLink(event, view) {
  const target = event.target?.nodeType === 3 ? event.target.parentElement : event.target;
  const marked = target?.closest?.("[data-md-link-from]");
  if (marked && view.contentDOM.contains(marked)) {
    const from = Number(marked.getAttribute("data-md-link-from"));
    if (Number.isInteger(from)) return linkAt(view.state, from, from);
  }
  try {
    const position = view.posAtCoords({ x: event.clientX, y: event.clientY });
    return position == null ? null : linkAt(view.state, position);
  } catch {
    return null;
  }
}

function exactCommandClick(event) {
  return event.button === 0 && event.metaKey &&
    !event.ctrlKey && !event.altKey && !event.shiftKey;
}

function invokeLinkOpener(context, link) {
  const callback = context.current;
  if (typeof callback !== "function" || !link) return false;
  callback({ ...link });
  return true;
}

function linkInteractions(context) {
  return EditorView.domEventHandlers({
    mousedown(event, view) {
      context.pendingPointer = null;
      if (!exactCommandClick(event) || typeof context.current !== "function") return false;
      const link = pointerLink(event, view);
      if (!link) return false;
      context.pendingPointer = link;
      event.preventDefault();
      event.stopPropagation();
      return true;
    },
    click(event, view) {
      if (!exactCommandClick(event) || typeof context.current !== "function") {
        context.pendingPointer = null;
        return false;
      }
      const link = context.pendingPointer || pointerLink(event, view);
      context.pendingPointer = null;
      if (!link) return false;
      event.preventDefault();
      event.stopPropagation();
      return invokeLinkOpener(context, link);
    }
  });
}

function openLinkAtSelection(view, context) {
  if (typeof context.current !== "function") return false;
  const selection = view.state.selection.main;
  const link = linkAt(view.state, selection.head) ||
    (!selection.empty
      ? stateLinks(view.state).find(candidate =>
        candidate.from < selection.to && candidate.to > selection.from)
      : null);
  return invokeLinkOpener(context, link);
}

class ListMarkerWidget extends WidgetType {
  constructor(text) {
    super();
    this.text = text;
  }

  eq(other) {
    return other.text === this.text;
  }

  toDOM(view) {
    const marker = view.dom.ownerDocument.createElement("span");
    marker.className = "cm-md-list-widget";
    marker.textContent = /^\d/.test(this.text) ? this.text : "•";
    marker.setAttribute("aria-hidden", "true");
    return marker;
  }

  ignoreEvent() {
    return true;
  }
}

function lineIsActive(view, position) {
  const state = view.state;
  return view.hasFocus &&
    state.doc.lineAt(position).number === state.doc.lineAt(state.selection.main.head).number;
}

// Block replacements must be supplied by a StateField, not a viewport plugin.
// The Markdown remains the sole editable/saved document; clicking a cell reveals
// its source at the same position, and leaving the table restores the preview.
const tableFocus = StateEffect.define();

function tableCells(state, row) {
  const boundaries = [];
  for (let node = row.firstChild; node; node = node.nextSibling) {
    if (node.name === "TableDelimiter") boundaries.push(node);
  }
  const spans = [];
  let from = row.from;
  for (const delimiter of boundaries) {
    if (delimiter.from > from || from !== row.from) spans.push([from, delimiter.from]);
    from = delimiter.to;
  }
  if (from < row.to) spans.push([from, row.to]);
  return spans.map(([start, end]) => {
    const raw = state.doc.sliceString(start, end);
    return { from: start + raw.length - raw.trimStart().length,
      text: raw.trim().replace(/\\\|/g, "|") };
  });
}

class TableWidget extends WidgetType {
  constructor(rows, alignments) {
    super();
    this.rows = rows;
    this.alignments = alignments;
  }
  eq(other) {
    return JSON.stringify(this.rows) === JSON.stringify(other.rows) &&
      JSON.stringify(this.alignments) === JSON.stringify(other.alignments);
  }
  toDOM(view) {
    const doc = view.dom.ownerDocument;
    const wrap = doc.createElement("div");
    wrap.className = "cm-md-table-wrap";
    const table = wrap.appendChild(doc.createElement("table"));
    const head = table.appendChild(doc.createElement("thead"));
    const body = table.appendChild(doc.createElement("tbody"));
    this.rows.forEach((row, index) => {
      const tr = (index === 0 ? head : body).appendChild(doc.createElement("tr"));
      // Match GFM: missing cells are empty; extra body cells do not add columns.
      this.rows[0].forEach((_, column) => {
        const value = row[column] || { from: row.at(-1)?.from ?? 0, text: "" };
        const cell = tr.appendChild(doc.createElement(index === 0 ? "th" : "td"));
        if (index === 0) cell.scope = "col";
        cell.textContent = value.text;
        cell.style.textAlign = this.alignments[column] || "left";
        cell.tabIndex = 0;
        cell.title = "클릭 또는 Enter로 표 원문 편집";
        const edit = event => {
          event.preventDefault();
          view.dispatch({ effects: tableFocus.of(true), selection: { anchor: value.from }, scrollIntoView: true });
          view.focus();
        };
        cell.addEventListener("mousedown", edit);
        cell.addEventListener("keydown", event => {
          if (event.key === "Enter" || event.key === " ") edit(event);
        });
      });
    });
    return wrap;
  }
  ignoreEvent() { return true; }
}

function tableDecorations(state, focused) {
  const ranges = [];
  markdownLanguage.parser.parse(state.doc.toString()).iterate({ enter(cursor) {
    if (cursor.name !== "Table") return;
    if (focused && state.selection.ranges.some(range => range.from <= cursor.to && range.to >= cursor.from)) return false;
    const rows = [];
    let alignments = [];
    for (let node = cursor.node.firstChild; node; node = node.nextSibling) {
      if (node.name === "TableHeader" || node.name === "TableRow") rows.push(tableCells(state, node));
      if (node.name === "TableDelimiter") {
        alignments = state.doc.sliceString(node.from, node.to).trim().replace(/^\||\|$/g, "").split("|")
          .map(cell => /^\s*:.*:\s*$/.test(cell) ? "center" : /:\s*$/.test(cell) ? "right" : "left");
      }
    }
    ranges.push(Decoration.replace({ block: true, widget: new TableWidget(rows, alignments) }).range(cursor.from, cursor.to));
    return false;
  }});
  return Decoration.set(ranges, true);
}

const tablePreview = StateField.define({
  create(state) { return { focused: false, decorations: tableDecorations(state, false) }; },
  update(value, transaction) {
    let focused = value.focused;
    for (const effect of transaction.effects) if (effect.is(tableFocus)) focused = effect.value;
    if (!transaction.docChanged && !transaction.selection && focused === value.focused) return value;
    return { focused, decorations: tableDecorations(transaction.state, focused) };
  },
  provide: field => EditorView.decorations.from(field, value => value.decorations)
});

function addLineClasses(ranges, state, from, to, className) {
  let line = state.doc.lineAt(from);
  const last = state.doc.lineAt(Math.max(from, to - 1)).number;
  while (line.number <= last) {
    ranges.push(Decoration.line({ class: className }).range(line.from));
    if (line.number === last) break;
    line = state.doc.line(line.number + 1);
  }
}

function markdownDecorations(view, title, linkContext) {
  const ranges = [];
  const state = view.state;
  const tree = syntaxTree(state);

  for (const visible of view.visibleRanges) {
    tree.iterate({
      from: visible.from,
      to: visible.to,
      enter(node) {
        const name = node.name;
        const activeLine = lineIsActive(view, node.from);

        if (/^ATXHeading[1-6]$/.test(name)) {
          const level = name.slice(-1);
          const text = state.doc.sliceString(node.from, node.to)
            .replace(/^\s*#{1,6}\s*/, "")
            .replace(/\s+#+\s*$/, "")
            .trim();
          const duplicate = level === "1" && title && text === title.trim();
          addLineClasses(
            ranges,
            state,
            node.from,
            node.to,
            `cm-md-heading cm-md-h${level}${duplicate ? " cm-md-duplicate-title" : ""}`
          );
        } else if (name === "SetextHeading1") {
          addLineClasses(ranges, state, node.from, node.to, "cm-md-heading cm-md-h1");
        } else if (name === "SetextHeading2") {
          addLineClasses(ranges, state, node.from, node.to, "cm-md-heading cm-md-h2");
        } else if (name === "Blockquote") {
          addLineClasses(ranges, state, node.from, node.to, "cm-md-blockquote");
        } else if (name === "FencedCode") {
          addLineClasses(ranges, state, node.from, node.to, "cm-md-code-block");
        } else if (name === "Emphasis") {
          ranges.push(Decoration.mark({ class: "cm-md-emphasis" }).range(node.from, node.to));
        } else if (name === "StrongEmphasis") {
          ranges.push(Decoration.mark({ class: "cm-md-strong" }).range(node.from, node.to));
        } else if (name === "InlineCode") {
          ranges.push(Decoration.mark({ class: "cm-md-inline-code" }).range(node.from, node.to));
        } else if (name === "Link" && node.node.getChild("URL")) {
          const attributes = { "data-md-link-from": String(node.from) };
          if (typeof linkContext.current === "function") {
            attributes.title = OPEN_LINK_HINT;
            attributes["aria-keyshortcuts"] = "Meta+Enter";
          }
          ranges.push(Decoration.mark({ class: "cm-md-link", attributes }).range(node.from, node.to));
        }

        if (!activeLine && ["HeaderMark", "EmphasisMark", "CodeMark"].includes(name)) {
          ranges.push(Decoration.replace({}).range(node.from, node.to));
        } else if (
          !activeLine && name === "LinkMark" &&
          node.node.parent?.name === "Link" &&
          node.node.parent.getChild("URL")
        ) {
          ranges.push(Decoration.replace({}).range(node.from, node.to));
        } else if (!activeLine && name === "URL" && node.node.parent?.name === "Link") {
          ranges.push(Decoration.replace({}).range(node.from, node.to));
        } else if (!activeLine && name === "LinkTitle" && node.node.parent?.name === "Link") {
          ranges.push(Decoration.replace({}).range(node.from, node.to));
        } else if (!activeLine && name === "ListMark") {
          const source = state.doc.sliceString(node.from, node.to);
          ranges.push(Decoration.replace({ widget: new ListMarkerWidget(source) }).range(node.from, node.to));
        } else if (["HeaderMark", "EmphasisMark", "CodeMark", "ListMark", "QuoteMark", "LinkMark"].includes(name)) {
          ranges.push(Decoration.mark({ class: "cm-md-punctuation" }).range(node.from, node.to));
        }
      }
    });
  }

  return Decoration.set(ranges, true);
}

function livePreview(title, linkContext) {
  return ViewPlugin.fromClass(class {
    constructor(view) {
      this.decorations = markdownDecorations(view, title, linkContext);
    }

    update(update) {
      if (update.docChanged || update.selectionSet || update.viewportChanged || update.focusChanged) {
        this.decorations = markdownDecorations(update.view, title, linkContext);
      }
    }
  }, {
    decorations: plugin => plugin.decorations
  });
}

const forwardedInput = EditorView.updateListener.of(update => {
  if (!update.docChanged || suppressInput.has(update.view)) return;
  const target = update.view.contentDOM;
  const EventConstructor = target.ownerDocument.defaultView?.Event;
  if (typeof EventConstructor === "function") {
    target.dispatchEvent(new EventConstructor("input", { bubbles: true }));
  }
});

const theme = EditorView.theme({
  "&": {
    height: "100%",
    minHeight: "0",
    background: "transparent",
    color: "inherit",
    font: "inherit"
  },
  ".cm-scroller": {
    overflow: "auto",
    fontFamily: "inherit",
    lineHeight: "1.68"
  },
  ".cm-content": {
    padding: "8px 2px 24px",
    caretColor: "currentColor"
  },
  ".cm-line": {
    padding: "0 2px"
  },
  ".cm-focused": {
    outline: "none"
  },
  ".cm-selectionBackground, &.cm-focused .cm-selectionBackground": {
    backgroundColor: "rgba(114, 140, 168, .24)"
  },
  ".cm-cursor": {
    borderLeftColor: "currentColor"
  },
  ".cm-md-heading": {
    color: "var(--t1, currentColor)",
    fontWeight: "700",
    lineHeight: "1.28"
  },
  ".cm-md-h1": { fontSize: "1.72em", paddingTop: ".38em", paddingBottom: ".18em" },
  ".cm-md-h2": { fontSize: "1.42em", paddingTop: ".32em", paddingBottom: ".14em" },
  ".cm-md-h3": { fontSize: "1.22em", paddingTop: ".24em" },
  ".cm-md-h4, .cm-md-h5, .cm-md-h6": { fontSize: "1.06em", paddingTop: ".18em" },
  ".cm-md-duplicate-title": { color: "var(--t2, #aab3bc)", fontSize: "1.18em" },
  ".cm-md-emphasis": { fontStyle: "italic" },
  ".cm-md-strong": { fontWeight: "700" },
  ".cm-md-inline-code": {
    background: "rgba(117, 126, 138, .12)",
    borderRadius: "4px",
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
    fontSize: ".9em"
  },
  ".cm-md-code-block": {
    background: "rgba(117, 126, 138, .09)",
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
    fontSize: ".9em"
  },
  ".cm-md-blockquote": {
    borderLeft: "2px solid rgba(116, 134, 154, .45)",
    color: "var(--t2, #aab3bc)",
    paddingLeft: ".75em"
  },
  ".cm-md-link": {
    color: "var(--me, #7dd3fc)",
    textDecoration: "underline",
    textDecorationThickness: ".06em",
    textUnderlineOffset: ".14em"
  },
  ".cm-md-punctuation": {
    color: "var(--t3, #7f8993)",
    fontWeight: "400",
    opacity: ".7"
  },
  ".cm-md-list-widget": {
    boxSizing: "border-box",
    color: "var(--t2, #aab3bc)",
    display: "inline-block",
    minWidth: "1.15em",
    paddingRight: ".28em",
    textAlign: "center"
  },
  ".cm-md-table-wrap": { margin: ".6em 0", overflowX: "auto" },
  ".cm-md-table-wrap table": { borderCollapse: "collapse", width: "100%", tableLayout: "fixed", fontSize: ".92em" },
  ".cm-md-table-wrap th, .cm-md-table-wrap td": {
    border: "1px solid rgba(117, 126, 138, .28)", padding: ".55em .65em",
    verticalAlign: "top", overflowWrap: "anywhere", cursor: "text"
  },
  ".cm-md-table-wrap th": { background: "rgba(117, 126, 138, .12)", fontWeight: "650" },
  ".cm-md-table-wrap :focus-visible": { outline: "2px solid var(--me, #7dd3fc)", outlineOffset: "-2px" }
});

function extensions(title, linkContext) {
  const keys = defaultKeymap.filter(binding =>
    binding.key !== "Escape" && binding.mac !== "Escape" &&
    binding.key !== "Mod-s" && binding.mac !== "Mod-s"
  );
  return [
    history(),
    keymap.of([
      ...historyKeymap,
      { key: "Mod-Enter", run: view => openLinkAtSelection(view, linkContext) },
      ...markdownKeymap,
      ...keys
    ]),
    markdownLanguage,
    EditorView.lineWrapping,
    tablePreview,
    EditorView.focusChangeEffect.of((_state, focused) => tableFocus.of(focused)),
    livePreview(title, linkContext),
    linkInteractions(linkContext),
    forwardedInput,
    theme
  ];
}

function remember(record) {
  if (!record.documentID) return;
  cachedStates.delete(record.documentID);
  cachedStates.set(record.documentID, {
    state: record.view.state,
    source: record.view.state.doc.toString(),
    title: record.title,
    linkContext: record.linkContext
  });
  while (cachedStates.size > CACHE_LIMIT) {
    cachedStates.delete(cachedStates.keys().next().value);
  }
}

function destroyRecord(record, preserveState = true) {
  if (!active.has(record)) return;
  if (preserveState) remember(record);
  active.delete(record);
  record.view.destroy();
}

function installTextareaAPI(view) {
  const element = view.contentDOM;
  const clamp = value => Math.max(0, Math.min(view.state.doc.length, Number(value) || 0));
  let requestedDirection = null;
  const direction = () => {
    const selection = view.state.selection.main;
    if (selection.empty) return "none";
    if (
      requestedDirection &&
      requestedDirection.anchor === selection.anchor &&
      requestedDirection.head === selection.head
    ) return requestedDirection.value;
    return selection.anchor <= selection.head ? "forward" : "backward";
  };
  const setRange = (start, end = start, nextDirection = "none", scrollIntoView = true) => {
    let from = clamp(start);
    let to = clamp(end);
    if (to < from) from = to;
    const value = ["forward", "backward"].includes(nextDirection) ? nextDirection : "none";
    const anchor = value === "backward" ? to : from;
    const head = value === "backward" ? from : to;
    requestedDirection = { anchor, head, value };
    view.dispatch({
      selection: EditorSelection.single(anchor, head),
      scrollIntoView
    });
  };

  Object.defineProperties(element, {
    value: {
      configurable: true,
      get: () => view.state.doc.toString(),
      set: value => {
        const text = String(value ?? "");
        if (text === view.state.doc.toString()) return;
        const selection = view.state.selection.main;
        const oldDirection = direction();
        const anchor = Math.min(selection.anchor, text.length);
        const head = Math.min(selection.head, text.length);
        requestedDirection = { anchor, head, value: oldDirection };
        suppressInput.add(view);
        try {
          view.dispatch({
            changes: { from: 0, to: view.state.doc.length, insert: text },
            selection: { anchor, head },
            annotations: Transaction.addToHistory.of(false)
          });
        } finally {
          suppressInput.delete(view);
        }
      }
    },
    selectionStart: {
      configurable: true,
      get: () => Math.min(view.state.selection.main.anchor, view.state.selection.main.head),
      set: value => {
        const start = clamp(value);
        const end = Math.max(start, element.selectionEnd);
        setRange(start, end, direction(), false);
      }
    },
    selectionEnd: {
      configurable: true,
      get: () => Math.max(view.state.selection.main.anchor, view.state.selection.main.head),
      set: value => {
        const end = clamp(value);
        const start = Math.min(element.selectionStart, end);
        setRange(start, end, direction(), false);
      }
    },
    selectionDirection: {
      configurable: true,
      get: direction,
      set: value => setRange(element.selectionStart, element.selectionEnd, value, false)
    },
    scrollTop: {
      configurable: true,
      get: () => view.scrollDOM.scrollTop,
      set: value => { view.scrollDOM.scrollTop = Number(value) || 0; }
    },
    scrollLeft: {
      configurable: true,
      get: () => view.scrollDOM.scrollLeft,
      set: value => { view.scrollDOM.scrollLeft = Number(value) || 0; }
    }
  });

  element.setSelectionRange = setRange;

  element.id = "bo";
  element.setAttribute("role", "textbox");
  element.setAttribute("aria-multiline", "true");
  element.setAttribute("aria-label", "문서 내용");
  element.classList.add("clonie-markdown-editor-input");
  return element;
}

function canMount(textarea) {
  const doc = textarea?.ownerDocument;
  return Boolean(
    textarea && textarea.parentNode && doc &&
    typeof doc.createElement === "function" && doc.defaultView
  );
}

function mount(textarea, options = {}) {
  if (!canMount(textarea)) return textarea;

  destroyDetached();
  const documentID = String(options.documentID ?? "");
  const title = String(options.title ?? "");
  const source = String(textarea.value ?? "");
  const onOpenLink = typeof options.onOpenLink === "function" ? options.onOpenLink : null;

  for (const record of [...active]) {
    if (documentID && record.documentID === documentID) destroyRecord(record);
  }

  const cached = documentID ? cachedStates.get(documentID) : null;
  const reusable = cached && cached.source === source && cached.title === title;
  const linkContext = reusable && cached.linkContext
    ? cached.linkContext
    : { current: null, pendingPointer: null };
  linkContext.current = onOpenLink;
  linkContext.pendingPointer = null;
  const state = reusable
    ? cached.state
    : EditorState.create({ doc: source, extensions: extensions(title, linkContext) });
  if (cached) cachedStates.delete(documentID);

  const parent = textarea.parentNode;
  const mountPoint = textarea.ownerDocument.createElement("div");
  parent.replaceChild(mountPoint, textarea);
  const view = new EditorView({ state, parent: mountPoint });
  parent.replaceChild(view.dom, mountPoint);

  const record = { view, documentID, title, linkContext };
  active.add(record);
  return installTextareaAPI(view);
}

function destroyDetached() {
  for (const record of [...active]) {
    if (!record.view.dom.isConnected) destroyRecord(record);
  }
}

function destroyAll() {
  for (const record of [...active]) destroyRecord(record);
}

function reset() {
  for (const record of [...active]) destroyRecord(record, false);
  cachedStates.clear();
}

function performHistory(direction) {
  const command = direction === "undo" ? undoCommand : direction === "redo" ? redoCommand : null;
  if (!command) return false;
  for (const record of active) {
    const content = record.view.contentDOM;
    const focused = content.ownerDocument.activeElement;
    if (focused !== content && !content.contains(focused)) continue;
    command(record.view);
    return true;
  }
  return false;
}

export { destroyAll, destroyDetached, links, mount, performHistory, reset };
