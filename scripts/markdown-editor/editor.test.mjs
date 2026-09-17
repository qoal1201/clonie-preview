import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {EditorView} from '@codemirror/view';
import {screenHTML,screenScript} from '../../tests/screen-load.mjs';

function setup(source='# 시험 문서\n\n## 결정 이유\n\n**정확한 값**과 [근거](notes/source.md)\n\n- 첫 항목\n- 둘째 항목\n\n`code`\n\n<script>alert(1)</script>\n') {
  const dom=new JSDOM(screenHTML(),{url:'https://clonie.test/',runScripts:'outside-only',pretendToBeVisual:true});
  const w=dom.window;
  w.Range.prototype.getClientRects=()=>[];
  w.Range.prototype.getBoundingClientRect=()=>({left:0,right:0,top:0,bottom:0,width:0,height:0});
  const sent=[];
  w.webkit={messageHandlers:new Proxy({}, {get:(_t,name)=>({postMessage:body=>sent.push({name,body})})})};
  w.eval(screenScript()+`;window.testAPI={ClonieMarkdownEditor,performEditorHistory,openMarkdownLink,receiveDocument,openWorkspaceDocument,editorManualSave,onDocumentSaveFailed,takeEditorDraft,enterFlow,returnFromFlow,clearEditorAutosave,releaseMarkdownEditors,resetMarkdownEditors,canvasGoBack,editorLocation,setPaths:p=>{PATHS=p},state:()=>({save:EDITOR_SAVE_STATE,composing:EDITOR_COMPOSING}),editorAPI:()=>ClonieMarkdownEditor};`);
  const api=w.testAPI;
  const data={schemaVersion:1,questions:[],asked:[],fragments:[{id:'doc',title:'시험 문서',body:source,questionIds:[]}],paths:{doc:'시험 문서.md'}};
  api.receiveDocument(JSON.stringify(data),null,{kind:'load',revision:'r1'});
  api.openWorkspaceDocument('doc');
  const body=()=>w.document.getElementById('bo');
  function close(){api.clearEditorAutosave();api.resetMarkdownEditors();w.close()}
  return {w,api,body,sent,source,close};
}

test('actual bundled editor renders Markdown without changing source or executing HTML',()=>{
  const x=setup();try{
    const bo=x.body();assert.ok(bo.classList.contains('cm-content'));
    assert.equal(bo.value,x.source);
    assert.equal(bo.getAttribute('aria-label'),'문서 내용');
    assert.ok(x.w.document.querySelector('.cm-md-h2'));
    assert.ok(x.w.document.querySelector('.cm-md-strong'));
    assert.equal(bo.querySelector('script'),null);
    assert.equal(x.sent.filter(s=>s.name==='saveDocument').length,0);
  }finally{x.close()}
});

test('GFM tables render aligned cells, preserve empty cells and source without executing HTML',()=>{
  const source='# 표\n\n| 질문 | 답 | 비고 |\n| :--- | ---: | :---: |\n| 시작 \\| 끝 | | <img src=x onerror=alert(1)> |\n\n```md\n| 코드 | 예시 |\n| --- | --- |\n```\n';
  const x=setup(source);try{
    const table=x.w.document.querySelector('.cm-md-table-wrap table');
    assert.ok(table);
    assert.equal(x.w.document.querySelectorAll('.cm-md-table-wrap').length,1);
    assert.deepEqual([...table.querySelectorAll('tbody td')].map(cell=>cell.textContent),['시작 | 끝','','<img src=x onerror=alert(1)>']);
    assert.equal(table.querySelectorAll('th')[1].style.textAlign,'right');
    assert.equal(table.querySelectorAll('th')[2].style.textAlign,'center');
    assert.equal(table.querySelector('img'),null);
    assert.equal(x.body().value,source);
    assert.equal(x.sent.filter(s=>s.name==='saveDocument').length,0);
  }finally{x.close()}
});

test('table cell opens original Markdown for editing, saves only the edit and supports undo',()=>{
  const source='# 표\n\n| 질문 | 근거 |\n| --- | --- |\n| 시작 | 회의 |\n\n다음 문단\n';
  const x=setup(source);try{
    const cell=x.w.document.querySelector('tbody td');
    cell.dispatchEvent(new x.w.MouseEvent('mousedown',{bubbles:true,button:0}));
    const bo=x.body(),view=EditorView.findFromDOM(bo);
    assert.equal(view.state.selection.main.head,source.indexOf('시작'));
    assert.equal(x.w.document.querySelector('.cm-md-table-wrap'),null);
    view.dispatch({changes:{from:source.indexOf('시작'),to:source.indexOf('시작')+2,insert:'종료'}});
    view.dispatch({selection:{anchor:source.indexOf('다음 문단')}});
    assert.equal(x.w.document.querySelector('tbody td').textContent,'종료');
    x.api.editorManualSave();
    const saved=JSON.parse(x.sent.find(s=>s.name==='saveDocument').body.json).fragments[0].body;
    assert.equal(saved,source.replace('시작','종료'));
    assert.equal(x.api.performEditorHistory('undo'),true);
    assert.equal(bo.value,source);
  }finally{x.close()}
});

test('textarea-compatible selection and autosave preserve exact Markdown bytes',async()=>{
  const x=setup();try{
    const bo=x.body();const source=x.source+'\n  끝의 공백도 유지  \n';
    bo.value=source;bo.focus();bo.setSelectionRange(3,7,'backward');
    assert.deepEqual([bo.selectionStart,bo.selectionEnd,bo.selectionDirection],[3,7,'backward']);
    assert.equal(x.api.takeEditorDraft().body,source);
    bo.dispatchEvent(new x.w.InputEvent('input',{bubbles:true}));
    await new Promise(resolve=>setTimeout(resolve,850));
    const request=x.sent.find(s=>s.name==='saveDocument')?.body;assert.ok(request);
    assert.equal(JSON.parse(request.json).fragments[0].body,source);
    x.api.receiveDocument(request.json,null,{kind:'save',requestID:request.requestID,revision:'r2',savedRevision:'r2'});
    assert.equal(x.api.state().save,'saved');
    assert.equal(x.body()===bo,true,'acknowledgement must keep the editor DOM and cursor');
    assert.equal(bo.value,source);
    assert.deepEqual([bo.selectionStart,bo.selectionEnd],[3,7]);
  }finally{x.close()}
});

test('failed autosave keeps the same editor and draft available for retry',async()=>{
  const x=setup();try{
    const bo=x.body();bo.value=x.source+'\n복구할 문장';bo.dispatchEvent(new x.w.InputEvent('input',{bubbles:true}));
    await new Promise(resolve=>setTimeout(resolve,850));
    const request=x.sent.find(s=>s.name==='saveDocument').body;
    x.api.onDocumentSaveFailed(request.requestID);
    assert.equal(x.body()===bo,true);assert.equal(bo.value,x.source+'\n복구할 문장');
    assert.equal(x.api.state().save,'failed');
    x.api.editorManualSave();assert.equal(x.sent.filter(s=>s.name==='saveDocument').length,2);
  }finally{x.close()}
});

test('composition events use the existing autosave guard',()=>{
  const x=setup();try{
    const bo=x.body();bo.dispatchEvent(new x.w.CompositionEvent('compositionstart',{bubbles:true,data:'한'}));
    assert.equal(x.api.state().composing,true);
    bo.value=x.source+'\n한글';bo.dispatchEvent(new x.w.InputEvent('input',{bubbles:true,isComposing:true,data:'글'}));
    assert.equal(x.sent.filter(s=>s.name==='saveDocument').length,0);
    bo.dispatchEvent(new x.w.CompositionEvent('compositionend',{bubbles:true,data:'한글'}));
    assert.equal(x.api.state().composing,false);
    assert.equal(x.api.state().save,'dirty');
    x.api.editorManualSave();
    assert.equal(JSON.parse(x.sent.find(s=>s.name==='saveDocument').body.json).fragments[0].body,x.source+'\n한글');
  }finally{x.close()}
});

test('settings roundtrip restores Markdown, selection and scroll in the same right pane',()=>{
  const x=setup();try{
    const bo=x.body();bo.focus();bo.setSelectionRange(5,10,'forward');bo.scrollTop=123;
    x.api.enterFlow('settings');x.api.returnFromFlow();
    assert.equal(x.body().value,x.source);
    assert.equal(x.w.document.activeElement===x.body(),true);
    assert.deepEqual([x.body().selectionStart,x.body().selectionEnd],[5,10]);
    assert.equal(x.body().scrollTop,123);
    assert.equal(x.sent.filter(s=>s.name==='saveDocument').length,0);
  }finally{x.close()}
});


test('typing and undo stay in the same Markdown source, including across settings',()=>{
  const x=setup('첫 본문');try{
    let bo=x.body();let view=EditorView.findFromDOM(bo);assert.ok(view);
    bo.focus();view.dispatch({changes:{from:4,insert:' 추가'},selection:{anchor:7}});
    assert.equal(bo.value,'첫 본문 추가');
    assert.equal(x.api.state().save,'dirty','actual CodeMirror changes notify the existing save path');
    x.api.editorManualSave();
    const request=x.sent.find(s=>s.name==='saveDocument').body;
    x.api.receiveDocument(request.json,null,{kind:'save',requestID:request.requestID,revision:'r2',savedRevision:'r2'});
    x.api.enterFlow('settings');x.api.returnFromFlow();
    bo=x.body();bo.focus();
    bo.dispatchEvent(new x.w.KeyboardEvent('keydown',{key:'z',code:'KeyZ',ctrlKey:true,bubbles:true,cancelable:true}));
    assert.equal(bo.value,'첫 본문');
    bo.dispatchEvent(new x.w.KeyboardEvent('keydown',{key:'y',code:'KeyY',ctrlKey:true,bubbles:true,cancelable:true}));
    assert.equal(bo.value,'첫 본문 추가');
  }finally{x.close()}
});

test('the body heading is the single visible title and editing it updates saved title',()=>{
  const x=setup();try{
    const bo=x.body();assert.equal(x.w.document.getElementById('doctitle').hidden,true);
    const view=EditorView.findFromDOM(bo);
    view.dispatch({changes:{from:2,to:7,insert:'바뀐 제목'}});
    assert.equal(x.w.document.getElementById('ti').value,'바뀐 제목');
    assert.equal(bo.value.startsWith('# 바뀐 제목'),true);
    x.api.editorManualSave();
    const doc=JSON.parse(x.sent.find(s=>s.name==='saveDocument').body.json).fragments[0];
    assert.equal(doc.title,'바뀐 제목');assert.equal(doc.body.startsWith('# 바뀐 제목'),true);
  }finally{x.close()}
});

test('links inside code remain literal while Markdown links outside are presented as labels',()=>{
  const source='`[코드](source.md)`\n\n```md\n[블록](code.md)\n```\n\n[실제 근거](notes.md)';
  const x=setup(source);try{
    const bo=x.body();assert.equal(bo.value,source);
    assert.ok(bo.textContent.includes('[코드](source.md)'));
    assert.ok(bo.textContent.includes('[블록](code.md)'));
    assert.ok(bo.textContent.includes('실제 근거'));
    assert.equal(bo.textContent.includes('(notes.md)'),false);
  }finally{x.close()}
});


test('Korean decomposed filenames do not repeat the same document title in the path label',()=>{
  const x=setup();try{
    x.api.setPaths({doc:'시험 문서.md'.normalize('NFD')});
    assert.equal(x.api.editorLocation({id:'doc',title:'시험 문서'}),'');
    x.api.setPaths({doc:'결정/시험 문서.md'.normalize('NFD')});
    assert.equal(x.api.editorLocation({id:'doc',title:'시험 문서'}).normalize('NFC'),'결정');
  }finally{x.close()}
});

for(const modifier of ['metaKey','ctrlKey']) test(`${modifier}+S saves immediately without moving the editor or selection`,()=>{
  const x=setup();try{
    const bo=x.body(),view=EditorView.findFromDOM(bo);
    bo.focus();view.dispatch({changes:{from:x.source.length,insert:'저장 확인'},selection:{anchor:2,head:7}});
    const event=new x.w.KeyboardEvent('keydown',{key:'s',code:'KeyS',[modifier]:true,bubbles:true,cancelable:true});
    bo.dispatchEvent(event);assert.equal(event.defaultPrevented,true);
    const request=x.sent.find(s=>s.name==='saveDocument')?.body;assert.ok(request);
    assert.equal(x.body(),bo);assert.equal(x.w.document.activeElement,bo);
    x.api.receiveDocument(request.json,null,{kind:'save',requestID:request.requestID,revision:'r2',savedRevision:'r2'});
    assert.equal(x.body(),bo);assert.deepEqual([bo.selectionStart,bo.selectionEnd],[2,7]);
    assert.equal(JSON.parse(request.json).fragments[0].body,x.source+'저장 확인');
  }finally{x.close()}
});

test('save shortcut during composition waits for composed input without remounting',async()=>{
  const x=setup();try{
    const bo=x.body();bo.focus();
    bo.dispatchEvent(new x.w.CompositionEvent('compositionstart',{bubbles:true,data:'ㅎ'}));
    bo.dispatchEvent(new x.w.KeyboardEvent('keydown',{key:'s',metaKey:true,bubbles:true,cancelable:true}));
    assert.equal(x.body(),bo);assert.equal(x.sent.filter(s=>s.name==='saveDocument').length,0);
    bo.value=x.source+'한';bo.dispatchEvent(new x.w.CompositionEvent('compositionend',{bubbles:true,data:'한'}));
    await new Promise(resolve=>setTimeout(resolve,850));
    assert.equal(JSON.parse(x.sent.find(s=>s.name==='saveDocument').body.json).fragments[0].body,x.source+'한');
  }finally{x.close()}
});


test('native menu history command uses the editor history and keeps focus',()=>{
  const x=setup('첫 본문');try{
    const bo=x.body();bo.focus();const view=EditorView.findFromDOM(bo);
    view.dispatch({changes:{from:4,insert:' 추가'}});
    assert.equal(x.api.performEditorHistory('undo'),true);assert.equal(bo.value,'첫 본문');
    assert.equal(x.api.performEditorHistory('redo'),true);assert.equal(bo.value,'첫 본문 추가');
    assert.equal(x.w.document.activeElement,bo);
    assert.equal(x.api.performEditorHistory('delete'),false);
  }finally{x.close()}
});

test('body links have no repeated footer and Cmd+Enter opens the selected relative document link',()=>{
  const x=setup('[근거](proof.pdf)');try{
    assert.equal(x.w.document.querySelector('.srefs'),null);
    const bo=x.body();bo.focus();bo.setSelectionRange(2,2);
    bo.dispatchEvent(new x.w.KeyboardEvent('keydown',{key:'Enter',code:'Enter',ctrlKey:true,bubbles:true,cancelable:true}));
    const request=x.sent.find(s=>s.name==='openSystem')?.body;
    assert.deepEqual(JSON.parse(JSON.stringify(request)),{what:'source',fromPath:'시험 문서.md',reference:'proof.pdf'});
    assert.equal(bo.value,'[근거](proof.pdf)');
  }finally{x.close()}
});

test('only Command-click opens a body link and code examples never become links',()=>{
  const x=setup('[근거](proof.pdf)\n\n`[코드](not-a-link.md)`\n\n[참조][id]\n\n[id]: hidden.md');try{
    const bo=x.body();
    const marked=bo.querySelector('[data-md-link-from]');assert.ok(marked);
    for(const options of [{},{ctrlKey:true},{metaKey:true,shiftKey:true}]){
      marked.dispatchEvent(new x.w.MouseEvent('click',{button:0,bubbles:true,cancelable:true,...options}));
    }
    assert.equal(x.sent.filter(s=>s.name==='openSystem').length,0);
    marked.dispatchEvent(new x.w.MouseEvent('mousedown',{button:0,metaKey:true,bubbles:true,cancelable:true}));
    marked.dispatchEvent(new x.w.MouseEvent('click',{button:0,metaKey:true,bubbles:true,cancelable:true}));
    assert.equal(x.sent.filter(s=>s.name==='openSystem').length,1);
    assert.deepEqual(JSON.parse(JSON.stringify(x.api.editorAPI().links(bo.value))).map(x=>x.target),['proof.pdf']);
    assert.equal(bo.value,x.source);
  }finally{x.close()}
});
