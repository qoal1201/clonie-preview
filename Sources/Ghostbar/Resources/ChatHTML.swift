import Foundation

func jsonString(_ arr: [String]) -> String {
    (try? String(data: JSONSerialization.data(withJSONObject: arr), encoding: .utf8)) ?? "[]"
}

func chatHTML() -> String { return #"""
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<style>
:root{
  /* ★ 판 색을 **성분으로도** 든다 (#61 B) — 불투명도 슬라이더가 알파만 갈아끼운다.
     `--opa` 는 Swift 가 저장해 두고 창이 뜰 때 `setWindowStyleValues` 로 되돌려 준다.
     ⚠ 창 **뒤**의 블러는 여기서 못 만든다 — `backdrop-filter` 는 같은 문서 안만 본다.
       그 층은 AppKit 것이다(`ChatWindow.backdrop`), 그리고 **이 알파를 내려야 보인다.** */
  --panelrgb:23,23,26; --opa:1;
  --panel:rgb(23,23,26); --glass:rgba(16,16,18,.62);
  --t1:#f2f1ec; --t2:#a3a29c; --t3:#6b6a65; --t4:#4d4c48;
  --line:rgba(255,255,255,.09); --line2:rgba(255,255,255,.16);
  --acc:#4ade80; --acc-d:rgba(74,222,128,.14); --acc-b:rgba(74,222,128,.45);
  --me:#7dd3fc; --me-d:rgba(125,211,252,.12); --warn:#e0b25a; --risk:#e0705c;
  /* ★ 신호등 둘을 **성분으로도** 든다 — `--panelrgb` 와 같은 모양·같은 이유다 (#67).
     알파를 그 자리에서 정해야 하는 곳(발광의 `drop-shadow`)이 색 리터럴을 베끼지 않게.
     ⚠ 이 파일이 이미 쓰는 길(`rgba(var(--…rgb),알파)`)을 그대로 쓴다 — 새 CSS 함수를 안 들인다. */
  --accrgb:74,222,128; --warnrgb:224,178,90;
  /* ★ 글자 최상위 색도 성분으로 든다 (#67 재편) — **흰 발광이 「내가 고른 것」의 어휘**라
     (#70 확정 ③) 그 알파를 그 자리에서 정해야 한다. 위 둘과 같은 이유·같은 모양이다. */
  --t1rgb:242,241,236;
  --sans:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Helvetica Neue",sans-serif;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:transparent;color:var(--t1);font-family:var(--sans);
  font-size:13px;line-height:1.6;letter-spacing:-.01em;overflow:hidden;-webkit-font-smoothing:antialiased}
button{font:inherit;font-family:var(--sans);cursor:pointer;border:none;background:none;color:inherit}
/* ⚠ **`select` 도 여기 든다** (#65 ⑥). 빠져 있어서 제공자 드롭다운만 **시스템 기본 글꼴·
   기본 글자색**으로 떴다 — 어두운 판 위에서 그 칸 하나가 다른 앱처럼 보였다. */
input,textarea,select{font:inherit;font-family:var(--sans);color:var(--t1)}
input:focus,textarea:focus,select:focus{outline:none}
@keyframes breathe{0%,100%{opacity:.95}50%{opacity:.3}}
.ld{width:5px;height:5px;border-radius:50%;background:var(--acc);animation:breathe 3s ease-in-out infinite;flex:0 0 auto}
#app{height:100vh;display:flex;flex-direction:column;overflow:hidden;border-radius:11px;
  position:relative;transition:opacity .2s ease}
#app.morph{opacity:0}
#app.live{background:var(--glass);border:1px solid var(--line2)}
#app.stack{background:rgba(var(--panelrgb),var(--opa));border:1px solid var(--line)}
.drag{-webkit-app-region:drag;user-select:none}
.nodrag{-webkit-app-region:no-drag}

/* 전사 — 높이를 **미리 잡는다.** 글이 차도 상자가 안 커져서 읽던 글자가 안 밀린다 (라운드 8) */
#hist{padding:10px 15px 0;height:38px;display:flex;flex-direction:column;justify-content:flex-end;gap:2px;overflow:hidden}
.hl{font-size:10.5px;line-height:1.45;color:var(--t3);text-shadow:0 1px 4px rgba(0,0,0,.85);
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex:0 0 auto}
.hl .w{color:var(--t4);margin-right:6px}
#cur{padding:5px 15px 10px;display:flex;gap:9px;align-items:flex-start}
#curw{flex:0 0 auto;font-size:10px;padding:2px 7px;border-radius:4px;margin-top:3px;user-select:none;
  background:rgba(255,255,255,.06);color:var(--t2);cursor:pointer;transition:background .3s,color .3s}
#cur.me #curw{background:var(--me-d);color:var(--me)}
#curbox{flex:1;min-width:0;height:44px;overflow:hidden}
#curtx{font-size:13px;line-height:1.55;text-shadow:0 1px 4px rgba(0,0,0,.9);outline:none;white-space:pre-wrap}
#curtx:empty:before{content:attr(data-ph);color:var(--t3)}
/* 미확정 꼬리 — 전사기가 아직 안 굳힌 자리. **확정된 글자는 다시 안 바뀐다** */
#curtx .vol{opacity:.5;color:var(--t2)}
.hsep{height:1px;background:var(--line)}
#recs{flex:1;overflow-y:auto}
#recs::-webkit-scrollbar{width:3px}
#recs::-webkit-scrollbar-thumb{background:var(--line2);border-radius:2px}
/* 줄 높이 고정 + 본문은 max-height 로 편다 — 펼침이 아래 줄을 안 밀어낸다 */
.rec{padding:10px 15px;display:flex;gap:12px;align-items:flex-start;cursor:pointer;min-height:54px;
  box-shadow:inset 0 1px 0 rgba(255,255,255,.055);transition:background .4s,opacity .4s,box-shadow .4s}
.rec:hover{background:rgba(255,255,255,.03)}
.rec.open{background:rgba(74,222,128,.07);box-shadow:inset 2px 0 0 var(--acc)}
.rec.dim{opacity:.42}
.rec .in{flex:1;min-width:0;transition:opacity .24s}
.rec.fade .in{opacity:0}
.rt{font-size:12.5px;line-height:1.45;text-shadow:0 1px 4px rgba(0,0,0,.9)}
.rec.open .rt{font-size:13px}
.rs{font-size:10.5px;line-height:1.4;color:var(--t2);text-shadow:0 1px 4px rgba(0,0,0,.85);margin-top:3px}
/* 신호등 — 순위가 아니라 **절대 유사도**가 근거다. 빨강이어도 안 숨긴다(#20) */
.dot{display:inline-block;width:6px;height:6px;border-radius:50%;margin-right:5px;
  vertical-align:middle;transition:background .3s}
.dot.g{background:var(--acc)}
.dot.a{background:var(--warn)}
.dot.r{background:var(--risk)}
.rb{font-size:12px;line-height:1.72;color:#d9d8d3;text-shadow:0 1px 4px rgba(0,0,0,.9);
  max-height:0;overflow:hidden;margin-top:0;transition:max-height .45s ease,margin .45s ease}
.rec.open .rb{max-height:132px;margin-top:7px}
.rn{font-size:10px;color:var(--t4);flex:0 0 auto;padding-top:3px;width:12px;transition:color .4s}
.rec.open .rn,.rec.lead .rn{color:var(--acc)}
.empty{padding:14px 15px;font-size:11.5px;color:var(--t3)}
.trouble{padding:8px 15px;font-size:11px;line-height:1.5;color:var(--warn);
  border-top:1px solid var(--line);background:rgba(224,178,90,.07)}
.bottom{display:flex;gap:9px;align-items:center;padding:8px 15px;border-top:1px solid var(--line)}
.foot{font-size:10.5px;color:var(--t4)}
/* ⚠ `white-space:nowrap` — 받기 화면 윗줄에 버튼이 셋이 되면서(#40) 좁은 창에서
   「파일 고 / 르기」로 접혔다. 글자가 접히면 버튼이 두 개로 보인다.
   ⚠ #46 이 「파일 고르기」를 윗줄에서 카드 안으로 옮겨 윗줄은 둘이 됐다 — **그래도 안 걷는다.**
     걷으면 다음에 버튼이 하나 늘 때 같은 자리가 조용히 다시 접힌다. */
.gbtn{font-size:11.5px;padding:6px 12px;border-radius:5px;border:1px solid var(--line2);color:var(--t2);transition:.12s;white-space:nowrap}
.gbtn:hover{border-color:var(--t3);color:var(--t1)}
.gbtn.p{background:var(--acc);border-color:var(--acc);color:#0f2417}
.gbtn.p:hover{background:#6ee79b}
.ibtn{font-size:12px;color:var(--t4);padding:4px 7px;border-radius:4px}
.ibtn:hover{color:var(--t1);background:rgba(255,255,255,.06)}

#top{display:flex;align-items:center;gap:12px;padding:14px 20px 13px;border-bottom:1px solid var(--line)}
/* ★ **창 단추가 켜진 모드에서는 머리를 오른쪽으로 민다** (#67 재편, `실측 2026-09-02` 실앱).
   창이 `.fullSizeContentView` 라 **웹 화면이 타이틀바 자리까지 덮는다**(잰 것: 창 높이 760 =
   `innerHeight` 760). 그래서 되살린 창 단추와 이 머리가 **같은 좌표에 겹친다**:
   단추 셋 = 창 좌표 x 8–70 · y 8–24 (AX `AXCloseButton` (253,149) 16×16 등, 창 원점 (245,141)),
   `#brand` = x 21–63 · y 19–43 → **x 21–63, y 19–24 가 실제로 포개졌다.**
   단추 오른쪽 끝(70)에 6px 을 더해 76px 로 민다.
   ⚠ **면접(`live`)은 그대로 20px** — 거기엔 단추가 없다(`applyMode`). 새 축을 안 만들고
     Swift 가 이미 쓰는 그 갈림(`live` 냐 아니냐)을 화면에서도 그대로 쓴다. */
#app:not(.live) #top{padding-left:76px}
#brand{font-size:15px}
#stat{font-size:11.5px;color:var(--t3);min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
/* ⚠ **준비도 한 줄(`#ready`)의 CSS 가 걷혔다** (#74 C4) — 머리글은 이제 아이콘 넷뿐이다. */
/* ★ 머리글 아이콘 (#74 C4) — **인라인 SVG 만** 쓴다(바깥 자산 0, 채팅 UI 제약 ②).
   ⚠ 크기·색을 여기 한 곳에서 정한다: `currentColor` 라 버튼 색만 바꾸면 그림이 따라온다. */
.ico{display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;
  padding:0;border-radius:6px;color:var(--t3);transition:color .12s,background .12s}
.ico:hover{color:var(--t1);background:rgba(var(--t1rgb),.06)}
.ico svg{width:15px;height:15px;display:block}
/* 면접이 **이 앱의 동사 하나**다 — 그것을 말하는 것은 채움이 아니라 **색**이다(크기는 같다) */
.ico.act{color:var(--acc)}
.ico.act:hover{color:var(--acc);background:var(--acc-d)}
/* ★ 3단이다 — 왼쪽 목록 · **가운데 뜻 지도** · 오른쪽 상세 (#67 재편, 레퍼런스 = 옵시디언).
   ⚠ **grid 에서 flex 로 갈아탔다.** 경계면을 끌어 폭을 바꾸므로 칸 폭이 인라인 스타일로
     흐르고, `grid-template-columns` 는 그 값을 부모가 들어야 해서 칸마다 따로 못 준다. */
#cols{flex:1;display:flex;min-height:0}
/* 흐름을 막는 안내는 접힌 본문 패널과 무관하게 보인다. */
#stacknotices:empty{display:none}
#stacknotices{flex:0 0 auto;max-height:28vh;overflow:auto;padding:8px 20px}
#stacknotices .wb + .wb{margin-top:6px}
/* ★ 왼쪽 칸은 **세 층**이다 — 위 고정(새 조각) · 목록 스크롤 · 아래 고정(파일 올리기).
   위아래를 고정하는 이유는 QA 블로커 F4 그대로다: 칸 하나가 통째로 스크롤이면
   `실측 2026-08-30` 처럼 문이 스크롤 아래로 숨는다.
   ★ **이 칸이 곧 던져넣기의 문이다** (박선호 2026-08-31, 그릴 Q5). 헤더에 있던 「넣기」를
     걷고 그 일을 이 칸이 든다 — 위에서 새로 쓰고, 아래에서 파일을 올리고, **끌어다 놓으면**
     받기 화면이 뜬다. 넣는 길이 목록 옆에 있어야 「무엇이 쌓였나」와 한눈에 붙는다.
   ⚠ `min-height:0` 이 셋 다에 필요하다. 없으면 flex 자식이 내용 높이로 부풀어
     `overflow-y` 가 안 걸린다(스크롤이 아니라 칸이 늘어난다). */
#left{display:flex;flex-direction:column;min-height:0;overflow:hidden;flex:0 0 auto;
  transition:background .12s}
/* 접히면 폭이 0 이다 — `display:none` 을 안 쓴다. 그러면 안에 앉은 칸들이 **다시 지어져**
   스크롤 자리와 포커스가 날아간다(경계면을 되돌리는 것이 「복귀」가 아니라 「새로 열기」가 된다). */
#left.zip,#right.zip{flex-basis:0!important;width:0!important;border:none!important;padding:0!important}
/* 끌어다 놓는 중 — **테두리가 아니라 배경**으로 말한다. 테두리를 굵히면 1px 만큼 칸이 밀린다.
   ⚠ 받기 화면(`#ingest`)도 같은 과녁이다 (#66-9) — 어휘를 새로 안 만들고 이 한 줄을 나눠 쓴다 */
#left.drop,#ingest.drop{background:rgba(74,222,128,.07)}
#lefttop{flex:0 0 auto;padding:11px 12px 9px;display:flex;flex-direction:column;gap:8px}
/* ★ 목록 거르개 (#67 스펙 2) — **자가 아니다.** 글자가 들어 있나만 본다.
   ⚠ 가운데 지도의 질문 칸과 **다른 것**이다: 저건 뜻으로 재고 이건 목록을 좁힌다.
     한 칸으로 합치면 「좁히기」와 「재기」가 같은 동작이 되고, 재는 것은 비싼 쪽(임베딩)이다. */
#lfind{width:100%;background:rgba(0,0,0,.22);border:1px solid var(--line);border-radius:6px;
  font-size:12px;color:var(--t1);padding:6px 9px}
#lfind::placeholder{color:var(--t4)}
#lfind:focus{border-color:var(--line2)}
.lhits{font-size:10.5px;color:var(--t4);letter-spacing:.02em}
#leftlist{flex:1;min-height:0;overflow-y:auto;padding:2px 10px 14px}
#leftpin{flex:0 0 auto;padding:10px 12px 12px;border-top:1px solid var(--line);background:rgba(var(--panelrgb),var(--opa));
  display:flex;flex-direction:column;gap:8px}
#leftlist::-webkit-scrollbar,#right::-webkit-scrollbar{width:3px}
#leftlist::-webkit-scrollbar-thumb,#right::-webkit-scrollbar-thumb{background:var(--line2);border-radius:2px}
/* 씨앗 표식이 **눈에 보이는 자리** — 이 한 장은 면접·연습 순위에서 빠진다(블로커 F2).
   빼기만 하고 안 말하면 「왜 안 뜨지」가 코드에서 찾을 일이 된다. */
.seedtag{font-size:9.5px;color:var(--t4);border:1px solid var(--line2);border-radius:3px;
  padding:1px 5px;margin-left:6px;vertical-align:middle;flex:0 0 auto}
#right{padding:20px 22px 18px;display:flex;flex-direction:column;gap:19px;overflow-y:auto;
  flex:0 0 auto;min-height:0}
/* ★ 경계면 (#67 스펙 3) — **접기 버튼이 아니다.** 옵시디언처럼 잡고 끌고, 임계 아래로
   좁히면 스냅으로 접힌다. 접힌 자리엔 얇은 손잡이가 남아 그게 복귀 문이다.
   ⚠ `<button>` 이라 키보드로도 닿는다 — 화살표로 옮기고 Enter 로 접었다 편다.
   ⚠ **접기 = 캔버스 확대**다. 가운데가 `flex:1` 이라 양쪽이 0 이 되면 저절로 커진다 —
     「지도 화면」이라는 별도 모드를 폐지한 것이 이 한 줄로 성립한다. */
.rzr{flex:0 0 5px;position:relative;cursor:col-resize;background:none;border:0;padding:0;
  touch-action:none;z-index:4;align-self:stretch}
.rzr::before{content:"";position:absolute;top:0;bottom:0;left:2px;width:1px;
  background:var(--line);transition:background .15s,width .15s,left .15s}
.rzr:hover::before,.rzr.on::before{left:1px;width:3px;background:var(--line2)}
/* 접힌 자리의 손잡이 — **폭이 넓어지고 알약이 뜬다.** 없으면 되돌릴 길이 안 보인다 */
.rzr[data-zip="1"]{flex-basis:9px}
.rzr[data-zip="1"]::after{content:"";position:absolute;top:50%;left:3px;width:3px;height:34px;
  margin-top:-17px;border-radius:3px;background:var(--line2);transition:height .15s,margin-top .15s}
.rzr[data-zip="1"]:hover::after{height:52px;margin-top:-26px}
body.rzing{cursor:col-resize;user-select:none}
/* 접힘·펴짐은 미끄러진다(목업 .pane) — 끄는 동안(`rzing`)은 손을 그대로 따라간다 */
body:not(.rzing) #left,body:not(.rzing) #right{transition:width .28s cubic-bezier(.4,0,.2,1)}
:where(button,[tabindex]):focus-visible{outline:2px solid var(--t3);outline-offset:2px}
.fl{font-size:10.5px;color:var(--t4);display:block;margin-bottom:7px}
#ti{width:100%;background:none;border:none;border-bottom:1px solid var(--line);font-size:15px;line-height:1.5;padding-bottom:9px}
#ti:focus{border-bottom-color:var(--line2)}
#bo{width:100%;background:none;border:none;border-bottom:1px solid var(--line);font-size:12.5px;
  line-height:1.75;color:var(--t2);padding-bottom:9px;min-height:80px;resize:none}
#bo:focus{border-bottom-color:var(--line2)}
.srefs{display:flex;gap:6px;flex-wrap:wrap;padding-top:8px}
.sref{max-width:100%;overflow:hidden;text-overflow:ellipsis;font-size:10.5px;color:var(--t3);
  border:1px solid var(--line);border-radius:999px;padding:3px 8px;white-space:nowrap}
.sref:hover{color:var(--t1);border-color:var(--line2)}
/* ⚠ **칩 규칙은 통째로 걷혔다** (#53 경계표 ②). `.chips`/`.chip`/`.chip.on`/`.chip.new`/
   `.chip.sg`/`.lnkedit`/`#sug` — 누를 칩이 화면에 하나도 안 남았다. 다시 생기면
   `tests/screen-load.mjs` 를 쓰는 자물쇠가 아니라 **눈**이 먼저 본다. */
/* ⚠ **연결된 질문을 읽던 초록 태그(`#linked`·`.ltag`·`.lnone`)도 같이 걷혔다** (v3 정식화).
   장부(`questionIds`)를 이 화면에서 통째로 걷은 결정([ADR 0005](docs/adr/0005-content-direct-only-drop-the-chip-index.md)
   의 화면 층 연장)이 여기까지 온 것이다 — 「연결됨/미연결」 이분이 없는 화면에 그 태그만
   남으면 화면이 두 말을 한다. 그 자리를 가운데 우주의 별 이웃 점등(`canvasPaintFrom`)이 든다. */
.wb{font-size:11.5px;line-height:1.6;color:var(--warn);border-left:2px solid var(--warn);padding-left:11px}
.row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}

/* ⚠ **왼쪽 칸 아래의 큰 [면접 시작]·[연습하기] 두 장은 걷혔다** (v3 정식화).
   면접·연습은 이제 **헤더 가운데**에 산다(`.hmmid`) — 이 앱의 동사가 하나라는 것을
   자리가 말한다. 그 자리를 왼쪽 칸에서는 넣는 문(새 조각·파일 올리기)이 이어받았다.
   설명 문구를 안 다는 규율은 그대로다 (박선호 2026-08-28:
   *"애니매이션이랑 효과로 충분히 시각화로 보여주면 됨"*). */
/* 나가는 길도 하나 — 투명 확인창. 확인창도 투명이라 공유에 안 잡히는 것은 같다 */
#confirm{position:absolute;inset:0;display:none;align-items:center;justify-content:center;z-index:5;
  background:rgba(0,0,0,.25)}
#confirm.on{display:flex}
#cbox{background:rgba(16,16,18,.78);border:1px solid var(--line2);border-radius:10px;padding:16px 20px;text-align:center}
#cbox p{font-size:12.5px;margin-bottom:12px;text-shadow:0 1px 4px rgba(0,0,0,.9)}
#cbox .crow{display:flex;gap:10px;justify-content:center}

/* ── 던져 넣기 (#14). 쌓기 모드 안이라 불투명 위에 얹힌다 ── */
/* ★ 한 칸짜리 화면이라 **글줄을 재운다** (#46, 목업 ①은 640px 열이다). 창은 980px 인데
   글이 그 폭을 다 쓰면 큰 안내 문장이 한 줄에 안 앉고 카드가 종이처럼 넓어진다.
   ⚠ `justify-content:center` 로 세로 가운데를 안 잡는다 — 덩이 카드가 붙어 넘치기 시작하면
     가운데 정렬이 **위를 잘라먹어** 스크롤로 못 되돌린다. 위 여백으로 대신한다. */
#ingest{flex:1;padding:34px 24px 24px;display:flex;flex-direction:column;align-items:center;
  gap:18px;overflow-y:auto;transition:background .12s}
#ingest>*{width:100%;max-width:680px;flex:0 0 auto}
#ingest::-webkit-scrollbar{width:3px}
#ingest::-webkit-scrollbar-thumb{background:var(--line2);border-radius:2px}
/* ★ 큰 안내 한 문장 (#46, 목업 ①) — 첫 실행에 열리는 화면이라 **여기가 제품의 첫 문장**이다.
   ⚠ 무엇을 하는지만 말한다. 라벨·버튼이 다시 말하면 같은 말이 세 곳이 된다. */
.ihx{font-size:21px;line-height:1.45;font-weight:600;color:var(--t1)}
.ihs{font-size:12.5px;line-height:1.6;color:var(--t2);margin-top:9px}
/* 넣는 일 셋(파일·붙여넣기·갈라보기)이 **한 카드 안**에 산다 — 흐름이 하나라는 것을 상자가 말한다 */
.icard{border:1px solid var(--line);border-radius:8px;padding:20px 22px;background:rgba(255,255,255,.02);
  display:flex;flex-direction:column;gap:16px}
#doc{width:100%;min-height:150px;background:rgba(0,0,0,.22);border:1px solid var(--line);
  border-radius:7px;padding:11px 13px;font-size:12.5px;line-height:1.7;color:var(--t2);resize:vertical}
#doc:focus{border-color:var(--line2)}
/* ★ 공통 지능 한 줄 (#51 → #55) — **조용한 한 줄**이다. 기본이 뒤집혀 이제 켜진 채로
   시작하지만(#55) **줄의 무게는 그대로 둔다**: 눈에 띄게 만들면 그건 자랑이지 고지가 아니다.
   ⚠ 대신 바로 위 「이 맥 밖으로 나가지 않아요」가 **켜짐/꺼짐을 따라 같이 바뀐다** —
     기본이 켬이 된 지금 그 한 줄이 화면의 유일한 정직성이다. */
#cloud:empty{display:none}
#cloud{display:flex;flex-direction:column;gap:4px;border-top:1px solid var(--line);padding-top:13px}
.ctog{display:flex;gap:7px;align-items:center;font-size:11.5px;color:var(--t2);cursor:pointer}
/* ⚠ **초록(`--acc`)을 안 칠한다** — 이 화면에서 초록은 신호등의 「준비됨」이다(`.dbox` 주석과 같은 규율) */
.ctog input{margin:0}
/* ── 시스템 상태 어휘 (`mk*`) ──────────────────────────────────────────────────
   ★ 이 이름들은 **목업 A(구독 연결 카드, #57)에서 태어났다.** 승격 라운드가 그 목업을
     걷고 같은 어휘를 **프론트 설정 화면**으로 옮겼다 — 카드·작은 글씨·중립 점·코드 한 줄.
   ⚠ **신호등(`.dot.g/.a/.r`)을 여기서 안 쓴다** — `CONTEXT.md` 신호등 조항: 점의 초록/주황/빨강은
     **준비도 전용**이고 시스템 상태(연결됨·로그인·설치)에는 안 쓴다. 연결 카드가 말하는 것은
     전부 시스템 상태라, 그 자리는 아래 **중립 점(`.mkdot`)** 이 든다. */
.mkcard{border:1px solid var(--line2);border-radius:8px;padding:14px 15px;
  background:rgba(255,255,255,.03);display:flex;flex-direction:column;gap:11px}
.mkbig{display:block;width:100%;padding:12px;border-radius:8px;text-align:center;
  background:var(--acc-d);border:1px solid var(--acc-b);color:var(--acc);font-size:13px;font-weight:600;
  transition:background .15s}
.mkbig:hover{background:rgba(74,222,128,.22)}
.mkfine{font-size:10.5px;line-height:1.6;color:var(--t3)}
.mkstat{display:flex;gap:6px;align-items:center;font-size:11.5px;color:var(--t2)}
.mkrow{display:flex;gap:9px;align-items:center;flex-wrap:wrap;font-size:11.5px;color:var(--t2)}
.mkcode{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px;color:var(--t1);
  background:rgba(0,0,0,.3);border:1px solid var(--line);border-radius:4px;padding:2px 7px}
.mklink{font-size:11.5px;color:var(--me);text-decoration:underline;text-underline-offset:3px}
/* 중립 점 — **신호등이 아니다.** 색을 뜻으로 안 쓰고 **채움과 굵기**로만 가른다:
   빈 점(가는 테두리) = 안 잡힘 · 굵은 테두리 = 중간 층 · 채움 = 잡힘.
   ⚠ 주황을 새로 안 만든다(#46) — 여기 쓰는 색은 이미 있는 글자색뿐이다. */
.mkdot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:5px;box-sizing:border-box;
  vertical-align:middle;border:1px solid var(--t3);background:transparent}
.mkdot.mid{border-width:2.5px;border-color:var(--t2)}
.mkdot.on{border-color:var(--t1);background:var(--t1)}
/* ── 점 어휘 (왼쪽 트리·순위 상자가 쓴다) ──
   ⚠ SVG 는 **인라인**이다 — 자산을 하나도 안 부른다(채팅 UI 제약 ②). `url(…)` 도 0건. */
.mtx{font-size:11.5px;fill:var(--t2)}
.mhd{font-size:10px;fill:var(--t4)}
/* 신호등은 **점이 든다** (`CONTEXT.md` 불변식 ②) — 선·글자는 색으로 뜻을 안 만든다 */
.mg{fill:var(--acc)}
.ma{fill:var(--warn)}
.mr{fill:var(--risk)}
/* 잴 수 없을 때 — 벡터가 없으면 **색을 안 낸다.** 두 번째 자로 물러서지 않는다(`eris` 머리글) */
.mn{fill:var(--t3)}
/* ── 쌓기 홈 v3 (`hm*`) — **정식 화면이다** (박선호 확정 설계 2026-08-31, #61) ──
   ⚠ 이름의 `hm` 은 home 이다. 전 판은 `s2`(목업 C)였고, 승격 라운드가 게이트를 걷으면서
     목업 표식을 이름에서도 걷었다 — 목업 접두사가 남아 있으면 다음 사람이 이 화면을
     「아직 그림」으로 읽는다.
   ⚠ **신호등은 점에만 산다** (`CONTEXT.md` 불변식 ②). 이 화면에서 초록/주황/빨강이 앉는 자리는
     ① 왼쪽 목록의 점 ② 그래프 안쪽(질문) 노드 **둘뿐**이고, 둘 다 `eris` 하나가 칠한다.
   ⚠ **강조 1색(`--acc`)을 그래프에 안 쓴다.** 그래프에서 초록은 「준비됨」이라, 가운데 노드나
     선을 초록으로 칠하면 같은 화면의 초록이 두 뜻이 된다 — 가운데는 중립 밝은색(`--t1`)이다. */
.hmtop{position:relative}
/* 가운데 고정 — 좌우 묶음의 너비가 달라서 `flex:1` 두 개로는 **가운데가 아니다**(창 폭 따라 흐른다) */
.hmmid{position:absolute;left:50%;transform:translateX(-50%);display:flex;gap:10px;align-items:center}
/* ★ 버튼 위계 — **[면접]이 이 앱의 동사 하나**다. 그것을 말하는 것은 **채움**이지 크기가 아니다.
   ⚠ **크기로 이단을 만들지 않는다** (박선호 2026-08-31 지적, #61 E). v3 1차안은 [면접]을
     키우고 [연습]을 줄였는데, 크기가 둘이면 「하나는 큰 버튼 하나는 작은 버튼」이라는
     **세 번째 정보**가 생긴다 — 위계는 이미 색이 말하고 있었다. 그래서 **같은 높이**로 두고
     면접은 채움(강조 1색 `--acc`), 연습은 고스트(테두리만)다.
   ⚠ **높이가 `#top` 을 안 밀어야 한다** — `.hmmid` 는 `position:absolute` 라 흐름 밖이고,
     버튼이 헤더보다 크면 아래 줄을 덮는 게 아니라 **헤더 밖으로 삐져나온다.**
     `실측 2026-08-31`(창 800×620): `#top` 높이 60.4 · 이 버튼 36.0(둘이 같다) — 위아래 12.2 씩 남는다.
     `#top` 의 높이를 정하는 것은 브랜드가 아니라 **오른쪽 `.gbtn`** 이다.
     글자·패딩을 키우거나 오른쪽 버튼을 줄이면 **이 수를 다시 재라.** */
.gbtn.hmact{font-size:12.5px;padding:7px 20px;border-radius:6px}
/* 미니멀 행 — **한 줄 제목 + 점 하나**가 전부다. 부연 문장(「…질문에 연결됨」)은 안 앉는다 */
.hmit{display:flex;gap:9px;align-items:center;padding:8px 10px;border-radius:6px;cursor:pointer;
  font-size:12px;line-height:1.45;color:var(--t2);transition:background .12s}
.hmit:hover{background:rgba(255,255,255,.035)}
.hmit.sel{background:rgba(255,255,255,.06);color:var(--t1)}
/* ★ 폴더 행 — 접었다 편다 (#74 C2). **점이 없다**: 폴더는 파일이 아니라 잴 것이 없다 */
.hmit.fold{color:var(--t3)}
.hmit.fold:hover{color:var(--t1)}
/* ★ 지금 범위인 항성 줄 (#75 4) — 우주의 `.ksun.scoped` 와 **같은 사실**을 트리에서 말한다.
   ⚠ 신호등 색을 안 쓴다: 범위는 측정이 아니라 **내가 고른 것**이라 흰색 어휘다(design.md §2). */
.hmit.fold.scoped{color:var(--t1);box-shadow:inset 2px 0 0 var(--t1)}
.hmit .tw{display:inline-flex;align-items:center;justify-content:center;flex:0 0 20px;width:20px;height:24px;
  font-size:12px;color:var(--t2);line-height:1;cursor:pointer;padding:0;border:0;background:transparent;border-radius:4px}
.hmit .tw:hover,.hmit .tw:focus-visible{color:var(--t1);background:rgba(255,255,255,.08)}
.hmit .tw.empty{visibility:hidden;cursor:default}
.treeicon{position:relative;display:inline-flex;align-items:center;justify-content:center;flex:0 0 18px;width:18px;height:18px;color:var(--t3)}
.treeicon svg{display:block;width:16px;height:16px}
.hmit.fold .treeicon{color:#efab72}
.treeicon .dot{position:absolute;right:-1px;top:-1px;width:5px;height:5px;margin:0;border:1px solid var(--panel);}
/* 왼쪽 위 도구모음 — 문서·폴더·접기를 한 줄에 두고, 검색은 그 아래 둔다 */
.vaulttitle{display:flex;align-items:center;gap:5px;min-width:0}
.vaulttitle .vaultheading{flex:1;min-width:0;padding-bottom:10px}
.vaulttitle #vaultmenu{flex:0 0 28px;padding:5px 4px;color:var(--t3);font-size:14px;line-height:1}
.vaulttitle #vaultmenu:hover,.vaulttitle #vaultmenu:focus-visible{color:var(--t1);background:rgba(var(--t1rgb),.06);border-radius:5px;outline:none}
.ltools{display:flex;align-items:center;gap:4px;margin-bottom:8px}
.ltools .ico{width:28px;height:28px}
/* 왼쪽 위 한 줄 — 거르개 칸 */
.lrow{display:flex;gap:6px;align-items:center}
.lrow #lfind{flex:1;min-width:0}
.hmtx{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
/* 잴 수 없는 점 — **신호등이 아니다.** 벡터가 없거나 걸린 질문이 없으면 여기로 물러선다 */
.dot.hmn{background:var(--t4)}
.hmez{font-size:12.5px;line-height:1.6;color:var(--t2);padding:10px 10px 12px}
.hmnote{font-size:10.5px;line-height:1.6;color:var(--t4);padding:12px 10px 0}
/* 로컬 그래프가 **죽은 공간을 먹는다** — 오른쪽 칸의 `flex:1` 자리가 이것이다 */
.hmnode{cursor:pointer}
.hmnode:hover .mtx{fill:var(--t1)}
/* 가운데(고른 조각)의 라벨 — 이웃(`.mtx` 11.5)보다 한 눈금 크고 밝다. **강조는 크기·밝기로
   낸다. 초록(`--acc`)을 안 쓴다** — 이 그림 안에 준비도 초록이 같이 살기 때문이다(위 ⚠). */
.hmctx{font-size:12.5px;fill:var(--t1)}
/* ⚠ **구멍 행의 ✕(`.gpx`)가 걷혔다** (#74 C2) — 구멍 행이 없다. 전사 쓰레기 질문을
   치우는 문은 문지기(#47 후속)와 연습 쪽에 남는다. */

/* ── 뜻 지도 (#67 재편) — **쌓기 홈의 가운데 칸이다.** 별도 화면이 아니다 ──
   ★ 점 하나 = md 조각 하나. 제목을 달고 다니지 않고, 스치면 툴팁·누르면 **오른쪽 판**이 열린다
     (박선호 2026-09-02: *"점 형태의 여러 md 파일들이 캔버스에 있고, 검색하면 해당되는 점들이 빛나는"*).
   ★ **은유는 우주다** (#70): 가운데 큰 구슬 = 태양 = 질문이 들어오는 커맨드 센터 ·
     점 = 별(md 파일 하나) · 판 = 우주. 별은 잡아서 옮긴다.
   ⚠ **오른쪽 판은 쌓기 홈의 그 판 그대로다** — `#right` 를 id 째로 다시 쓴다(`editPanel`).
     새 판을 지으면 저장·지우기·이분 뷰가 두 벌이 되고 한쪽이 조용히 낡는다.
   ⚠ 어휘를 새로 안 만들었다: 점 색은 신호등(`.dot.g/.a/.r` 과 같은 세 변수), 버튼은 `.gbtn`,
     작은 글씨는 `.foot`·`.mkfine` 이다.
   ★ **색 어휘 셋** (#70 확정 ②③): 무채색 = 쉼 · 흰색 = 내가 고른 것 · 신호등 = 측정 결과.
     그래서 **기본 상태엔 신호등이 없다** — 질문이 들어와야 재지고, 그때 켜진다. */
/* 판이 **가라앉아** 있어야 점이 뜬다 — 쌓기 홈의 판 색보다 한 겹 어둡다 */
/* ⚠ `container-type` 은 **남겨 둔다** — 이 칸의 폭으로 갈리는 규칙이 다시 생길 때(창 폭이
     아니라 칸 폭이다: 양쪽을 접으면 창은 그대로인데 이 칸만 커진다, #67 스펙 3) 그때
     선언부터 다시 세우지 않게. 지금 이것을 쓰는 규칙은 0개다. */
#cvwrap{position:relative;flex:1;min-width:0;min-height:0;overflow:hidden;background:rgba(0,0,0,.24);
  container-type:inline-size}
svg#cvb{width:100%;height:100%;display:block;cursor:grab;touch-action:none}
svg#cvb.grabbing{cursor:grabbing}
/* 어느 자로 재는 중인가 — **선언된 갈림을 화면 구석에 적는다**(`CONTEXT.md`). 신호등이 아니다 */
.cvhow{position:absolute;left:14px;top:14px;z-index:2;pointer-events:none;
  font-size:10.5px;color:var(--t4);white-space:nowrap}
.cvhow.mean{color:var(--t2)}
/* ★ 태양 = 커맨드 센터 (#70 확정 ④). **이 화면의 동사 하나다** — 누르면 질문 칸이 열린다.
   ⚠ 신호등 색을 안 쓴다: 이건 준비도가 아니라 「내가 던지는 자리」다. */
#cvb #orbg{cursor:pointer}
#cvb #orbg .halo{fill:rgba(var(--t1rgb),.05);stroke:none;transition:fill .2s ease}
#cvb #orbg .disc{fill:rgba(255,255,255,.045);stroke:var(--line2);stroke-width:1.4;
  transition:fill .2s ease,stroke .2s ease}
#cvb #orbg .mark{font-size:24px;fill:var(--t3);text-anchor:middle;dominant-baseline:central;
  pointer-events:none;transition:fill .2s ease}
#cvb #orbg:hover .disc,#cvb #orbg.asking .disc{fill:rgba(255,255,255,.085);stroke:var(--t3)}
#cvb #orbg:hover .halo,#cvb #orbg.asking .halo{fill:rgba(var(--t1rgb),.09)}
#cvb #orbg:hover .mark,#cvb #orbg.asking .mark{fill:var(--t1)}
/* 질문 팝오버 — 태양을 누르면 판 위에 뜬다. 창을 안 만들고 이 칸 안에서 산다 */
.askpop{position:absolute;z-index:5;width:min(330px,calc(100% - 28px));
  transform:translate(-50%,0) scale(.97);opacity:0;pointer-events:none;
  background:rgba(10,10,12,.97);border:1px solid var(--line2);border-radius:11px;
  padding:13px 14px;box-shadow:0 18px 44px -12px rgba(0,0,0,.8);
  transition:opacity .16s ease,transform .16s ease}
.askpop.show{opacity:1;transform:translate(-50%,0) scale(1);pointer-events:auto}
.askpop .askl{display:block;font-size:9.5px;letter-spacing:.13em;color:var(--t4);margin-bottom:8px}
#cvq{width:100%;background:none;border:none;border-bottom:1px solid var(--line);
  font-size:13px;color:var(--t1);padding-bottom:7px}
#cvq:focus{border-bottom-color:var(--line2)}
.askfoot{margin-top:9px;font-size:10px;color:var(--t4)}
/* 스치면 뜨는 제목 하나. 점은 제목을 달고 다니지 않는다 */
.cvtip{position:absolute;left:0;top:0;z-index:3;pointer-events:none;transform:translate(-50%,-100%);
  opacity:0;transition:opacity .12s ease;background:rgba(10,10,12,.94);border:1px solid var(--line2);
  border-radius:6px;padding:4px 8px;font-size:11.5px;color:var(--t1);white-space:nowrap;max-width:280px;
  overflow:hidden;text-overflow:ellipsis}
.cvtip.show{opacity:1}
/* 순위 상자 — 라이브 카드와 **같은 셋**이다(`paintRecs` 의 `[0,1,2]`). 원값은 QA 게이트 뒤다 */
.cvrank{position:absolute;right:14px;top:14px;width:min(262px,calc(100% - 28px));z-index:2;pointer-events:none;
  background:rgba(10,10,12,.9);border:1px solid var(--line);border-radius:9px;padding:11px 12px;
  opacity:0;transform:translateY(-6px);transition:opacity .18s ease,transform .18s ease}
.cvrank.show{opacity:1;transform:none}
.cvrank button{pointer-events:auto}   /* 상자는 못 누르지만 그 안의 수확 버튼은 눌린다 — 감사 #56 의 진짜 버그 */
.cvrank h4{font-size:10px;font-weight:400;color:var(--t4);letter-spacing:.02em}
.cvrank .cq{font-size:12px;color:var(--t1);line-height:1.45;margin:3px 0 8px}
.cvrow{display:flex;align-items:center;gap:7px;padding:5px 0;border-top:1px solid var(--line)}
.cvrow .t{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
  font-size:11.5px;color:var(--t2)}
.cvrow.lead .t{color:var(--t1)}
.cvrow .s{font-size:11px;color:var(--t4);font-variant-numeric:tabular-nums;flex:0 0 auto}
.cvrank .cvfoot{margin-top:8px;font-size:10px;line-height:1.55;color:var(--t4)}
/* 재료 없음 — **순위 대신** 이 자리가 뜬다 (#67 확정 ④). 띠가 아니라 상자 안이라 신호등이 아니다 */
.cvnone{font-size:12px;line-height:1.6;color:var(--t2);margin:2px 0 9px}
/* ⚠ **범례(`.cvlegend`)와 손잡이 설명(`.cvhint`)이 걷혔다** (#74 C5 · design.md 원칙:
   *"글자로 설명하지 말고 모양으로 말한다"*). 남는 덧글자는 어느 자로 재나(`.cvhow`) 하나와
   빈 볼트 한 줄(`.cvez`)뿐이다. 좁은 칸에서 둘이 겹치던 `@container` 규칙도 같이 죽었다. */
/* ⚠ **순위 상자는 안 숨긴다.** 그건 질문의 **답**이라, 좁다고 걷으면 물어본 사람이 아무것도
   못 받는다 — 대신 칸 폭을 따라 줄어든다(`width:min(...)`). 걷히는 것은 설명글뿐이다. */
/* 정본을 기다리는 동안 — 빈 저장소와 갈려 보여야 한다(`RECEIVED` 머리글) */
.opening{flex:1;display:flex;align-items:center;justify-content:center;font-size:12.5px;color:var(--t4)}
/* 볼트가 비었을 때 — **빈 판은 고장으로 읽힌다.** 그 말은 글자가 든다 (`cvez` 의 그 규율) */
.cvez{position:absolute;left:0;right:0;top:50%;transform:translateY(-50%);z-index:2;
  pointer-events:none;text-align:center;font-size:12.5px;line-height:1.8;color:var(--t3);padding:0 24px}
/* 별 — 반지름·색이 전부다. **전환은 CSS 가 든다**(`canvasPaint` 는 속성만 바꾼다).
   ⚠ 커서가 `grab` 이다 — **잡아서 옮기는 것**이 이 점의 두 번째 동사이기 때문이다 (#70 확정 ⑤) */
#cvb .cvn{cursor:grab}
svg#cvb.grabbing .cvn{cursor:grabbing}
#cvb .cvn .hit{fill:transparent}
#cvb .cvn .ring{fill:none;stroke:none;transition:stroke .18s ease}
#cvb .cvn .d{transition:fill .28s ease,r .28s ease,opacity .28s ease,filter .28s ease}
/* 가라앉음·밝기는 **속성**이 든다(`litOpacity`) — 목업: 안 켜진 별 .24, 켜진 별 .55+.45·일치도, 고른 별은 .7 아래로 안 잠긴다 */
/* ★ **고른 별 = 흰 발광** (#70 확정 ③). 헤일로가 그 표시를 들고, 점 자체는 흰빛으로 탄다.
   ⚠ 전 판은 **점선 테**였다 — 그게 상위 셋의 실선 테와 같은 어휘라 「고름」과 「순위」가
     한 눈에 안 갈렸다. 색 어휘를 셋으로 나눈 것이 이 자리를 푼다. */
#cvb .cvn .selhalo{fill:rgba(var(--t1rgb),.09);stroke:rgba(var(--t1rgb),.42);stroke-width:1;
  opacity:0;transition:opacity .2s ease}
#cvb .cvn.sel .selhalo{opacity:1}
#cvb .cvn.sel .d{filter:drop-shadow(0 0 13px rgba(var(--t1rgb),.62))}
/* ⚠ **발광 색을 리터럴로 안 적는다** — 팔레트를 고치면 발광만 옛 색으로 남아 한 화면이 두 말을 한다.
   성분 변수(`--accrgb`·`--warnrgb`)에서 뽑는다 — 그 선언 머리글이 이유를 든다.
   ⚠ **측정이 선택 위에 온다.** 같은 특정성이라 순서가 이긴다 — 켜진 별의 색은 신호등이 들고,
     「내가 고른 것」은 흰 헤일로가 계속 든다. 둘이 한 별에 겹칠 수 있어서 자리를 갈라 뒀다. */
#cvb .cvn.lit-a .d{filter:drop-shadow(0 0 6px rgba(var(--warnrgb),.55))}
#cvb .cvn.lit-g .d{filter:drop-shadow(0 0 11px rgba(var(--accrgb),.75))}
/* ⚠ **빨강엔 발광을 안 준다** (#74). 빨강은 「이 주제인데 약하다」라서 켜지되 **안 빛난다** —
   빛나면 그것이 답 행세를 한다. 색 토큰(`--risk`)은 이미 있고 성분 변수는 안 만들었다
   (design.md §8 의 그 줄: 성분 변수는 발광이 필요할 때만 는다). */
/* ★ 몸의 종류 (#74 C1) — 항성·작은 중심·행성·위성. **크기는 층이고 SVG 속성이 든다**
   (`orbitLayout` 의 `r`), CSS 가 드는 것은 **채움과 테**뿐이다.
   ⚠ 작은 중심은 **빈 원**이다 — 파일이 아니라 폴더라 「잴 것이 없다」를 모양이 말한다. */
#cvb .cvn.ksun{cursor:pointer}
#cvb .cvn.ksun .d{stroke:rgba(var(--t1rgb),.28);stroke-width:1.2}
#cvb .cvn.ksun.scoped .d{stroke:var(--t1);stroke-width:2}
#cvb .cvn.kcenter .d{fill:none!important;stroke:var(--t4);stroke-width:1.2}
#cvb .cvn.kcenter{cursor:default}
/* 궤도 고리 — **아주 옅은 원 하나.** 뜻을 안 든다(색이 없다): 자리가 구조에서 나온다는
   사실만 말한다 (design.md §1). */
#cvb .orbit{fill:none;stroke:rgba(var(--t1rgb),.045);stroke-width:1;pointer-events:none}
/* 상위 셋 = 실선 테. **초록을 테에 안 쓴다** — 그 초록은 준비도의 것이다.
   ★ **셋이 동급이 아니다** (#67 「top-3 부드럽게」). 1위가 제일 밝고 굵으며 아래로 옅어진다 —
     라이브 카드가 1위만 `.lead` 로 밝히는 그 위계와 같은 모양이다.
   ⚠ 순위 테(r13)와 선택 헤일로(r19)는 **반지름이 갈려 있다** — 같은 자리에 그리면 둘 중
     하나가 안 읽힌다. */
/* ★ **켜져 있는 동안 돈다** (#75 3) — 점선이라 도는 것이 보인다. 미는 것은 `canvasTick` 이고
   (`stroke-dashoffset`), CSS 는 점선의 모양만 든다. ⚠ 자전이 아니다: 몸은 안 돌고 테만 흐른다. */
#cvb .cvn.top .ring{stroke:var(--t1);stroke-dasharray:5 4;stroke-width:1.7;opacity:1}
#cvb .cvn.top.k2 .ring{stroke-width:1.2;opacity:.6}
#cvb .cvn.top.k3 .ring{stroke-width:1;opacity:.38}
/* 선은 **반응으로만** 나타난다 (#70 확정 ③) — 쉴 때는 안 그린다. 기본 불투명도가 0 이다 */
#cvb .beam{fill:none;opacity:0;transition:opacity .3s ease,stroke-width .3s ease}
/* 파동 고리 — 검색이 **중앙에서** 퍼진다. rAF 가 반지름을 민다(전환 아님) */
#cvb .ripple{pointer-events:none}
/* `prefers-reduced-motion` — 파동을 안 돌리고 전환도 끈다. 결과 화면은 **같다**.
   ⚠ 걸리는 자리가 `#cv`(옛 지도 화면)에서 `#cvwrap`(홈의 가운데 칸)으로 옮겨졌다 (#67 재편) */
#cvwrap.rm .cvn .d,#cvwrap.rm .cvn .ring,#cvwrap.rm .cvn .selhalo,#cvwrap.rm .beam,
#cvwrap.rm #orbg .disc,#cvwrap.rm .cvrank,#cvwrap.rm .cvtip,#cvwrap.rm .askpop{transition:none}
/* ── 프론트 설정 (#61 C) — **쌓기 모드 안의 한 화면**이다. 모드가 아니다 ──
   ⚠ 어휘를 새로 안 만들었다 — 카드·작은 글씨·중립 점·코드 한 줄은 전부 위 `mk*` 그대로다.
   ⚠ **신호등을 안 쓴다**(`CONTEXT.md` 신호등 조항): 「연결됨/로그인 필요/없음」은 시스템
     상태이지 준비도가 아니다. 그 자리는 중립 점(`.mkdot`)의 **채움·굵기**가 든다. */
#setbody{flex:1;padding:26px 24px 24px;display:flex;flex-direction:column;align-items:center;
  gap:22px;overflow-y:auto}
#setbody>*{width:100%;max-width:620px;flex:0 0 auto}
/* ★ **이 화면의 스크롤바만 보이게 둔다** (#65 ⑩). 다른 칸의 3px 은 읽는 중에 눈을 안 끌라고
   그렇게 뒀는데, 설정은 **아래에 더 있다는 것 자체가 정보**다 — 단축키·권한·볼트가 접힌 자리
   아래 있고, 모르면 「그 칸이 없다」로 읽힌다. 어휘를 새로 안 만들고 굵기·색만 올린다. */
#setbody::-webkit-scrollbar{width:11px}
#setbody::-webkit-scrollbar-thumb{background:var(--t4);border-radius:6px;
  border:3px solid transparent;background-clip:content-box}
#setbody::-webkit-scrollbar-thumb:hover{background:var(--t3);background-clip:content-box}
.setgrp{display:flex;flex-direction:column;gap:10px}
.setlbl{flex:0 0 66px;font-size:11px;color:var(--t4)}
.setfld{flex:1;min-width:0;background:rgba(0,0,0,.22);border:1px solid var(--line);
  border-radius:5px;padding:6px 9px;font-size:12px;line-height:1.45;height:30px}
.setfld:focus{border-color:var(--line2)}
/* 드롭다운 — `appearance:none` 이 네이티브 화살표까지 걷어서, **떨어진다는 표시가 0개**였다
   (#65 ⑥). 화살표는 감싼 칸의 `::after` 가 든다 — 바깥 자산을 안 부른다(판정선 검사). */
select.setfld{appearance:none;cursor:pointer;padding-right:24px}
.setsel{flex:1;min-width:0;position:relative;display:flex}
.setsel .setfld{flex:1}
.setsel:after{content:"▾";position:absolute;right:9px;top:0;bottom:0;display:flex;align-items:center;
  pointer-events:none;color:var(--t3);font-size:10px}
input[type=range]{flex:1;min-width:0;accent-color:var(--t2)}
/* 연결 카드 한 장 — **누르면 다시 잰다.** 「다시 확인」 버튼을 따로 안 만든다 */
.setcli{cursor:pointer}
.setcli:hover{border-color:var(--t3)}
/* 단축키 녹화 칸 (2026-08-31 설정 통합) — **`.gbtn` 에 얹는다.** 새 어휘가 아니라
   폭을 고정하고 글꼴을 고정폭으로 바꾸는 것뿐이다(조합이 바뀔 때 줄이 안 흔들리게).
   ⚠ 녹화 중 테두리는 **신호등이 아니다** — 색을 안 쓰고 글자색(`--t1`)만 올린다. */
.setkey{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;min-width:96px;text-align:center}
.setkey.rec{border-color:var(--t1);color:var(--t1)}
#ierr{display:none;font-size:11.5px;line-height:1.6;color:var(--warn);
  border-left:2px solid var(--warn);padding-left:11px}
#isum{font-size:11.5px;color:var(--t3)}
.cand{border:1px solid var(--line);border-radius:8px;padding:15px 17px;background:rgba(255,255,255,.02)}
.cand.done{opacity:.45}
.irow{display:flex;gap:9px;align-items:flex-start;margin-bottom:8px}
.ilbl{font-size:10px;color:var(--t4);flex:0 0 34px;padding-top:6px}
.cq{flex:1;min-width:0;font-size:11.5px;line-height:1.5;color:var(--t3);padding-top:5px}
/* 문항이 질문 목록으로 어떻게 가나 — **읽는 한 줄**이다 (#53. 예전엔 여기가 칩 목록이었다) */
.cqn{flex:1;min-width:0;font-size:11px;line-height:1.5;color:var(--t4);padding-top:6px}
.cti{flex:1;min-width:0;background:rgba(0,0,0,.22);border:1px solid var(--line);border-radius:5px;
  padding:6px 9px;font-size:12.5px}
.cti:focus{border-color:var(--line2)}
/* 본문은 **원문 그대로** 보인다 — 줄바꿈까지. 기계가 다듬은 문장이 여기 있으면 안 된다 */
.cbody{position:relative;font-size:11.5px;line-height:1.7;color:var(--t2);white-space:pre-wrap;
  background:rgba(0,0,0,.22);border-radius:6px;padding:9px 11px;margin-bottom:9px;max-height:104px;overflow:auto}
.orig{position:absolute;right:8px;top:6px;font-size:9px;color:var(--t4);background:var(--panel);
  border:1px solid var(--line);border-radius:3px;padding:1px 5px}
.cacts{display:flex;gap:8px;justify-content:flex-end}
.okmsg{font-size:11px;color:var(--acc)}
/* ── 받기 (#40) — 파일·붙여넣기를 덩이로 잘라 초안으로 만든다 ──
   ⚠ 새 화면이 아니다. **던져 넣기 화면 그 자리**고, 위에 파일 줄과 진행 띠가 하나씩 얹힐 뿐이다. */
#ifiles:empty,#ibar:empty{display:none}
#ifiles{font-size:11px;line-height:1.7;color:var(--t3);display:flex;flex-direction:column;gap:3px}
.ifile{display:flex;gap:8px;align-items:baseline}
.ifile .itag{flex:0 0 auto;font-size:9.5px;color:var(--t4);border:1px solid var(--line2);
  border-radius:3px;padding:1px 5px}
.ifile.bad,.ifile.bad .itag{color:var(--warn);border-color:rgba(224,178,90,.4)}
#ibar{border:1px solid var(--line2);border-radius:8px;padding:12px 14px;font-size:12px;
  line-height:1.6;color:var(--t2);display:flex;flex-direction:column;gap:9px}
#ibar.warn{border-color:rgba(224,178,90,.4);background:rgba(224,178,90,.07)}
#ibar.okd{border-color:var(--acc-b);background:var(--acc-d)}
/* 초안이 붙는 자리 — 원문(`.cbody`) 아래다. **원문은 그대로 남는다**: 무엇에서 나온 초안인지
   눈으로 대볼 수 있어야 기계가 지어낸 것을 사람이 잡는다. */
/* ⚠ **초록으로 안 칠한다** — 초록은 신호등의 「준비됨」이다(`CONTEXT.md`). 초안은 아직
   판정을 안 받은 글자라, 상자는 중립으로 두고 뜻은 `.dhow` 표식이 든다. */
.dbox{border:1px solid var(--line2);border-radius:7px;background:rgba(255,255,255,.035);
  margin:0 0 10px;padding:11px 13px}
.dti{font-size:13px;line-height:1.5;color:var(--t1)}
.dbo{font-size:11.5px;line-height:1.7;color:var(--t2);white-space:pre-wrap;margin-top:6px;
  max-height:96px;overflow:auto}
.dhow{font-size:9.5px;color:var(--t4);border:1px solid var(--line2);border-radius:3px;
  padding:1px 5px;margin-left:7px;vertical-align:middle}
/* 한 덩이에서 이야기가 여럿 나온다 (#40 2판) — 장과 장 사이가 안 붙게. */
.dbo+.dti{margin-top:12px}
/* 「이야기를 못 찾았다」 — 사고가 아니라 판정이라 빨갛게 안 칠한다. 흐리게 둔다. */
.dnone{color:var(--t3)}
/* ── 면접에서 온 질문 (#22) ── */
.fromiv{font-size:9.5px;color:var(--warn);border:1px solid rgba(224,178,90,.4);
  border-radius:3px;padding:1px 5px;flex:0 0 auto}
/* ⚠ **채우기 가이드(#35)의 CSS 가 통째로 걷혔다** (#74 C5) — `#fillstart`·`.fbar`·
   `.fbh`·`.fbn`·`.fbq`·`.fbhint`. 짚을 구멍이 없으면 띠도 없다. */
/* ── 연습 (#36) — 앱이 묻고 내 답이 채점된다 ──────────────────────────────────
   ⚠ **쌓기 껍데기 그대로다.** 배경은 불투명(`--panel`)이고 창 층위도 일반이다 —
     숨을 이유가 없다(혼자 하는 리허설이라 화면 공유 위에 뜰 일이 없다).
     은신 자체는 두 모드 다 그대로다(`WindowPrivacy` 가 정한다). */
#app.practice{background:rgba(var(--panelrgb),var(--opa));border:1px solid var(--line)}
#pr{flex:1;padding:18px 24px;display:flex;flex-direction:column;gap:15px;overflow-y:auto}
#pr::-webkit-scrollbar{width:3px}
#pr::-webkit-scrollbar-thumb{background:var(--line2);border-radius:2px}
.pq{font-size:16.5px;line-height:1.45;color:var(--t1)}
.pn{font-size:10.5px;line-height:1.5;color:var(--t4)}
/* 답 칸 — 귀가 있으면 받아적히고, 없으면(브라우저 단독) 사람이 친다. **같은 칸이다**
   ★ **자란 답은 이 칸 안에서만 자란다** (#66-8 재수리, `실측 2026-09-01`). 전 판은 답이 길어지면
     `#pr` 을 통째로 바닥까지 밀었는데, `#pr` 은 문항까지 드는 칸이라 **묻고 있는 질문이 위로
     사라졌다** — 답은 보이는데 무엇에 답하는지가 안 보이는 화면이다. 상한을 답 칸에 걸어
     문항과 「채점/다음 질문」 줄이 언제나 남게 한다. */
#pans{min-height:82px;max-height:190px;overflow-y:auto;
  background:rgba(0,0,0,.22);border:1px solid var(--line);border-radius:7px;
  padding:10px 12px;font-size:12.5px;line-height:1.75;color:var(--t2);white-space:pre-wrap;outline:none}
#pans::-webkit-scrollbar{width:3px}
#pans::-webkit-scrollbar-thumb{background:var(--line2);border-radius:2px}
#pans:empty:before{content:attr(data-ph);color:var(--t3)}
#pans .vol{opacity:.5}
.pres{border:1px solid var(--line);border-radius:8px;padding:11px 13px;font-size:12px;line-height:1.6;color:var(--t2)}
.pres.g{border-color:var(--acc-b);background:var(--acc-d)}
.pres.a{border-color:rgba(224,178,90,.4);background:rgba(224,178,90,.07)}
.pres.r{border-color:rgba(224,112,92,.4);background:rgba(224,112,92,.07)}
.prow{display:flex;gap:9px;align-items:center;flex-wrap:wrap}
.sumrow{display:flex;gap:8px;align-items:center;padding:7px 0;border-bottom:1px solid var(--line);
  font-size:11.5px;line-height:1.45;color:var(--t2)}
/* ── 개념 제안 (#33) — 칩 칸 **위에** 얹히는 줄 하나. 새 화면이 아니다 ──
   ⚠ 색이 초록(확정된 칩)이 아니라 파랑(`--me`)이다. **기계가 낸 것과 사람이 고른 것을
     눈으로 가르는 자리** — 누르면 초록 칩으로 옮겨 앉는다. */
.vaultdialog{position:absolute;inset:0;z-index:1000;background:#0008;display:flex;align-items:center;justify-content:center;padding:24px}
.vaultsheet{background:var(--panel);color:var(--t1);border:1px solid var(--line2);border-radius:12px;padding:24px;width:min(480px,100%);max-height:90%;overflow:auto;box-shadow:0 16px 64px #0006}
.vaultsheet h3{margin:0 0 18px}.vaultsheet label{display:block;margin:12px 0}.vaultsheet input,.vaultsheet select{display:block;width:100%;margin-top:6px;padding:8px;background:var(--glass);color:var(--t1);border:1px solid var(--line2);border-radius:6px}.vaultsheet [hidden]{display:none}.vaultsheet small{color:var(--t3)}.vaultbuttons{display:flex;justify-content:flex-end;gap:10px;margin-top:18px}#verror{color:var(--warn)}
.vaultpopover{position:absolute;z-index:1100;display:flex;flex-direction:column;gap:2px;min-width:176px;max-width:calc(100% - 16px);padding:5px;background:var(--panel);color:var(--t1);border:1px solid var(--line2);border-radius:8px;box-shadow:0 12px 32px rgba(var(--t1rgb),.08)}
.vaultpopover [role="menuitem"]{width:100%;padding:7px 10px;border-radius:5px;text-align:left;color:var(--t2);white-space:nowrap}
.vaultpopover [role="menuitem"]:hover,.vaultpopover [role="menuitem"]:focus-visible{background:rgba(var(--t1rgb),.08);color:var(--t1);outline:none}

/* 2026-09-07: 탐색기 + 문서/우주 작업 공간. 상태 안내 외의 설명은 두지 않는다. */
#cols #rzr{display:none}
#cols #right{flex:0 1 0%;width:0!important;min-width:0;border:0;opacity:0;visibility:hidden;pointer-events:none;transform:translateX(12px);
  transition:flex-basis .22s cubic-bezier(.2,.7,.2,1),padding .22s cubic-bezier(.2,.7,.2,1),opacity .16s,transform .22s,visibility 0s .22s}
#cols.document-open #right{flex-basis:100%;width:auto!important;padding:22px clamp(22px,5vw,80px);opacity:1;visibility:visible;pointer-events:auto;transform:none;transition-delay:0s}
#cols.document-open #cvwrap{visibility:hidden;pointer-events:none}
@media (min-width:1000px){
  #cols.document-open #cvwrap{visibility:visible;pointer-events:auto}
  #cols.document-open #right{flex-basis:42%;border-left:1px solid var(--line);padding:20px 24px}
}
#right .dochead{display:flex;align-items:center;gap:8px;flex-shrink:0}
#right .docidentity{display:flex;align-items:center;gap:8px;flex:1;min-width:0}
#right .docpath{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--t3);font-size:12px}
#right .docsavestate{flex-shrink:0;color:var(--t4);font-size:11px;white-space:nowrap}
#right .docsavestate[data-state="dirty"]{color:var(--t2)}
#right .docsavestate[data-state="saving"]{color:var(--t3)}
#right .docsavestate[data-state="failed"]{color:var(--warn)}
#right .docbody{display:flex;flex:1;min-height:0;flex-direction:column}
#right #ti{font-size:24px;border:0;background:transparent;padding:6px 0}
#right #bo{flex:1;min-height:200px;resize:none;background:transparent;border:0;padding:8px 0;font-size:15px;line-height:1.85}
#right .dochead button{flex-shrink:0}
#cvwrap{background:radial-gradient(ellipse at 45% 48%,rgba(var(--t1rgb),.045),transparent 60%),rgba(0,0,0,.30)}
#cvb .beam{display:none}
/* 2026-09-08 합의: 종류는 고정 색, 검색은 원래 색의 밝기, 선택은 흰 테두리로 구분한다. */
#cvb .cvn{--body-glow:#dfe8f5}
#cvb .cvn.ksun{--body-glow:#ffb979}
#cvb .cvn.kplanet{--body-glow:#a9d4ff}
#cvb .cvn .surface{filter:drop-shadow(0 0 3px var(--body-glow));transition:filter .2s ease}
#cvb .cvn.ksun .surface{filter:drop-shadow(0 0 5px var(--body-glow))}
#cvb .cvn .d,#cvb .cvn.ksun .d{fill-opacity:0;stroke:none;filter:none}
#cvb .cvn.kcenter .d{stroke:rgba(224,233,245,.4);stroke-width:1;stroke-dasharray:none}
#cvb .cvn .shine{display:none}
#cvb .cvn .corona{opacity:.48;transition:opacity .2s ease}
#cvb .cvn:hover .surface{filter:drop-shadow(0 0 7px var(--body-glow))}
#cvb .cvn.lit-a .surface{filter:drop-shadow(0 0 5px var(--body-glow))}
#cvb .cvn.lit-g .surface{filter:drop-shadow(0 0 8px var(--body-glow))}
#cvb .cvn.sel .surface,#cvb .cvn.scoped .surface{filter:drop-shadow(0 0 12px var(--body-glow))}
#cvb .cvn.sel .corona,#cvb .cvn.scoped .corona{opacity:.95}
#cvb .cvn .selhalo{fill:none;stroke:#f5f8ff;stroke-width:1.6;filter:drop-shadow(0 0 4px #d9eaff);opacity:0}
#cvb .cvn.sel .selhalo,#cvb .cvn.scoped .selhalo{opacity:1}
#cvb .cvn.lit-a .d,#cvb .cvn.lit-g .d,#cvb .cvn.sel .d{filter:none}
#cvb .orbit{stroke:rgba(var(--t1rgb),.12);stroke-width:.8}
#cvrank .dot,#leftlist .treeicon .dot{background:#c3d2e5}
#cvb .cvn.kcenter{cursor:pointer}
#cvb .shine{fill:var(--t1);opacity:.52;pointer-events:none}
#cvb .ambient{pointer-events:none;fill:var(--t1)}
#cvb .ambient .glow{fill:url(#skyglow)}
#cvrank button.cvrow{width:100%;text-align:left;color:var(--t2)}
#cvrank .preview-copy{flex:1;min-width:0;display:block}
#cvrank .preview-copy .t{display:block}
#cvrank .preview-row{align-items:flex-start;padding:10px 0}
#cvrank .preview-row>.dot{margin-top:5px}
#cvrank .preview-row .s{color:var(--t3)}
#cvrank .preview-excerpt{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden;font-size:11px;line-height:1.6;color:var(--t3);margin-top:5px;white-space:normal}
#cvrank .preview-scope{float:right;margin-left:10px;font-weight:400;font-size:10px}
#orbg .disc{fill:rgba(var(--t1rgb),.75);filter:drop-shadow(0 0 16px rgba(var(--t1rgb),.5))}
#orbg .halo{stroke:rgba(var(--t1rgb),.15)}
/* 탐색·질문은 고정된 머리, 결과는 지도를 가리지 않는 별도 열이다. */
#cvwrap{display:grid;grid-template-columns:minmax(0,1fr) 0px;grid-template-rows:auto auto minmax(0,1fr);transition:grid-template-columns .22s cubic-bezier(.2,.7,.2,1)}
#cvnav{position:relative;grid-row:1;grid-column:1/-1;display:flex;align-items:center;gap:4px;padding:10px 14px 4px;min-width:0;z-index:2}
#cvnav button{padding:5px 8px;color:var(--t2);font-size:12px;border-radius:5px}
#cvnav button:disabled{opacity:.3;cursor:default}
#cvnav button:not(:disabled):hover{background:rgba(var(--t1rgb),.08)}
#cvnav span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--t2);font-size:12px;padding:0 6px}
.workspacequery{grid-row:2;grid-column:1/-1;display:flex;gap:8px;padding:4px 16px 8px;border-bottom:1px solid var(--line)}
.workspacequery input{flex:1;min-width:0;background:rgba(var(--t1rgb),.04);border:1px solid var(--line);border-radius:6px;padding:6px 10px;font-size:12px;color:var(--t1)}
.workspacequery:focus-within input{padding-top:9px;padding-bottom:9px}
.workspacequery button{padding:6px 10px;font-size:12px;color:var(--t2)}
#cvstage{position:relative;grid-row:3;grid-column:1;min-width:0;min-height:0;overflow:hidden}
#cvstage svg#cvb{position:absolute;inset:0;min-width:0;min-height:0}
#cvwrap:has(.cvrank.show){grid-template-columns:minmax(0,1fr) 262px}
#cvwrap .cvrank{position:relative;grid-row:3;grid-column:2;top:auto;right:auto;width:auto;min-width:0;min-height:0;overflow:hidden;display:block;margin:0;border:0;border-radius:0;padding:16px 0;background:rgba(0,0,0,.16);pointer-events:none;transform:none;opacity:0;visibility:hidden;transition:opacity .14s,padding .22s,visibility 0s .22s}
#cvwrap .cvrank.show{overflow:auto;border-left:1px solid var(--line);padding:16px;pointer-events:auto;opacity:1;visibility:visible;transition-delay:0s}
#cvwrap .cvhow{top:auto;bottom:10px;left:16px}
@container (max-width:620px){#cvwrap:has(.cvrank.show){grid-template-columns:minmax(0,1fr) 210px}}
#cols.document-open #cvwrap:has(.cvrank.show){grid-template-columns:minmax(0,1fr) 0px}
#cols.document-open #cvwrap .cvrank{overflow:hidden;padding-left:0;padding-right:0;border:0;opacity:0;visibility:hidden;pointer-events:none}
@media (prefers-reduced-motion:reduce){#cols #right,#cvwrap,#cvwrap .cvrank{transition:none;transform:none}}
#leftlist .hmit:focus-visible{outline:1px solid var(--t2);outline-offset:-2px}
#leftlist .hmit.dragover{background:rgba(var(--t1rgb),.13)}
#setnav{display:flex;gap:5px;flex-wrap:wrap;margin-bottom:20px}
#setnav button{padding:8px 12px;font-size:12px;color:var(--t3)}
#setnav button.active{background:rgba(var(--t1rgb),.07);color:var(--t1)}
#setbody .setpage[hidden]{display:none}

/* 승인된 탐색기 초안의 프레임·색·간격을 실제 저장소에 적용한다. */
#app.stack{--panelrgb:16,21,30;--panel:#10151e;--glass:#0d121b;--t1:#e4e9f1;--t2:#bec9d8;--t3:#8995a8;--t4:#63758d;--t1rgb:228,233,241;--line:#ffffff12;--line2:#ffffff20;background:#090d14}
#app.stack #top{height:49px;min-height:49px;padding:0 20px;background:#0d1119}
#app.stack #brand{font-size:15px;font-weight:600;letter-spacing:.3px}
#app.stack #left{background:#10151e;border-right:1px solid var(--line);padding-top:5px}
#app.stack #lefttop{padding:16px 14px 10px;gap:0}
.vaultheading{font-size:13px;font-weight:500;padding:2px 5px 18px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#app.stack #lfind{background:#ffffff05;padding:7px 8px;color:var(--t1)}
#app.stack #leftlist{padding:2px 10px 10px}
#app.stack .hmit{min-height:30px;margin:0;border-radius:5px;padding-top:4px;padding-bottom:4px;gap:5px;font-size:13px}
#app.stack .hmit.fold{margin-top:3px;color:var(--t2);font-size:13px}
#app.stack .hmit.sel{background:#88b6ff16;color:#d6e7ff}
#app.stack .hmit.scoped{box-shadow:inset 2px 0 #bbd5fa}
#app.stack .hmit .hmtx{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.fileedit{min-width:34px;font-size:11px!important}
.hmit.cosmic-hover{background:rgba(174,199,236,.16);box-shadow:inset 2px 0 #c4d8f3}
.filemore{flex:0 0 22px;padding:0 3px;color:var(--t3);opacity:.45;font-size:14px}
.hmit:hover .filemore,.hmit:focus-within .filemore{opacity:1}
#app.stack #leftpin{background:none;flex-direction:row;align-items:center;justify-content:space-between;padding:10px 14px;gap:8px}
#leftpin button{padding:7px;color:var(--t3);font-size:12px}
#app.stack #right{background:#0d121b}
#app.stack #sv{background:#d4e3f3;color:#172432;border-color:transparent}
#app.stack #cvwrap{background:radial-gradient(ellipse at 45% 48%,#263b552b,transparent 65%),#060b13}
#settingspane{display:flex;flex:1;min-width:0;min-height:0;flex-direction:column;background:#0d121b}
.settingsbar{height:52px;flex-shrink:0;display:flex;align-items:center;justify-content:space-between;padding:0 25px;border-bottom:1px solid var(--line);color:var(--t3);font-size:12px}
#settingspane #setbody{padding:40px 32px;gap:0;align-items:stretch}
#settingspane #setbody>*{width:100%;max-width:696px;margin-left:auto;margin-right:auto}
#settingspane #setnav{border-bottom:1px solid var(--line);padding-bottom:12px;margin-bottom:4px;gap:5px}
#settingspane #setnav button{padding:9px 12px;font-size:12px}
#settingspane .mkcard{background:none;border:0;border-radius:0;padding:0;margin:0}
#settingspane .mkcard>.setlbl{flex:0 0 auto;margin-top:16px}
#settingspane .mkrow{padding:22px 0;margin:0;border-bottom:1px solid var(--line);gap:12px;flex-wrap:wrap}
#settingspane .setlbl{min-width:96px;color:var(--t1);font-size:13px}
#settingspane .gbtn{background:#172131;border:1px solid #ffffff10;padding:8px 12px;color:#d4dfec}
#settingspane #setnav .gbtn{background:none;border:0}
#settingspane #setnav .active{background:#ffffff09;color:#e3ecf9}
#settingspane input[type=range]{max-width:180px;margin-left:auto;accent-color:#a9c6f0}
#settingspane #setvault{width:100%;overflow-wrap:anywhere}
#settingspane #setvaultbtn{margin-left:auto}

</style>
</head>
<body>
<div id="app"></div>
<script>
/* ── 브리지 ── 있으면 Swift 가 정본을 든다. 없으면(브라우저 단독) localStorage 가 대신한다.
   ⚠ 이 대체 경로가 `cue.html` 개발 동선을 지킨다 — Swift 를 빌드하지 않고 화면을 고치는 길. */
const post=(n,b)=>{try{webkit.messageHandlers[n].postMessage(b===undefined?{}:b)}catch(e){}};
const bridged=()=>{try{return !!webkit.messageHandlers.saveDocument}catch(e){return false}};
/* ⚠ **브라우저 목업 게이트(`MOCK` = `location.hash`)는 걷혔다** (승격 라운드, #61).
   목업 셋 중 쌓기 v3 은 **정식 화면**이 됐고(`stackRender`), 지도(`#mock-map`)는 인라인
   이분 뷰가 대체해서 통째로 걷혔고, 연결 카드(`#mock-connect`)는 프론트 설정 화면으로 이사했다.
   해시로 갈리는 화면이 이제 0개다 — 다시 생기면 그때 이 상수를 다시 세워라. */

/* ⚠ **표준 예상 질문 열 개(`STD`)가 죽었다** (#74 C5). 질문을 미리 써 두지 않는다 —
   ADR 0006 이 정한 것: 질문은 **입력 기록**에서 오지 우리가 지어 주는 것이 아니다.
   그래서 새 볼트를 열어도 `.clonie/questions.json` 이 안 생긴다. **기존 볼트의 질문은
   안 건드린다** — 연습이 그것으로 계속 돈다. */
const SEED_TITLE="여기에 내 경험을 한 줄로 쓴다";
const SEED_BODY="무슨 일이 있었고 무엇이 달라졌는지 적는다. 이 본문은 면접 중 그 조각을 골랐을 때만 펼쳐진다.";
const KEY="cue.doc.v1";  /* ⚠ 옛 키(cue.v1)를 안 읽는다 — #8: localStorage → 파일 이행은 안 한다 */
const SCHEMA=1;

/* id 는 **인덱스가 아니다**(#8). 질문을 지우거나 순서를 바꿔도 조각이 안 어긋난다.
   `crypto.randomUUID` 는 안전 컨텍스트에서만 있고 이 화면은 origin 이 없다 — 그래서 직접 만든다. */
let _seq=0;
const uid=p=>p+"-"+Date.now().toString(36)+"-"+((_seq++).toString(36))+Math.floor(Math.random()*1296).toString(36);
/* Swift 의 ISO8601 은 소수점 초를 안 받는다. 받는 쪽도 너그럽게 고쳐뒀지만 여기서도 안 붙인다. */
const now=()=>new Date().toISOString().replace(/\.\d+Z$/,"Z");

let DOC=blank(),mode="stack",sel=null,opened=null,manual=false,heardV="",mineV="",notice=null;
/* ★ 볼트 리비전은 화면이 해석하지 않는 **왕복 표**다 (#84). 실제 `VaultRevision` 은 Swift 가
   들고, 화면은 문서와 함께 받은 이 표를 다음 저장에 그대로 돌려준다. 저장 하나가 끝나기 전에는
   다음 것을 보내지 않는다 — 같은 리비전으로 저장 둘을 줄 세우면 둘째가 첫째와 충돌한다. */
let VAULT_REVISION=null,VAULT_BASE=blank(),SAVE_FLIGHT=null,SAVE_PENDING=false,SAVE_PENDING_AUTO=false,SAVE_SEQ=0;
let EDITOR_SAVE_STATE="saved",EDITOR_SAVE_TIMER=null,EDITOR_COMPOSING=false;
const EDITOR_AUTOSAVE_MS=800;
let EDITOR_NAVIGATION=null;
let TERMINATION_WAITING=null;
/* id → 그 파일의 로컬 편집을 시작한 리비전 표. 외부 reload 뒤에도 같은 파일만 옛 기준선을 쓴다. */
let DIRTY_REVISIONS={};
let VAULT_CONNECTED=true;
let DIRTY_PIN_SIG=null;
/* ★ 조각 id → **볼트 상대경로** (#74 A). Swift 가 `receiveDocument` 로 같이 준다 —
   「우주」의 항성이 볼트 폴더라 이 표가 그림의 축이다. ⚠ **저장으로 안 돌아간다**:
   경로는 파일이 놓인 자리에서 나오는 파생값이라 md 에 안 쓰고, `save()` 도 안 싣는다.
   ⚠ 브라우저 단독·아티팩트는 빈 표로 온다 — 그때는 전부 미분류 항성 하나다(선언된 갈림). */
let PATHS={};
/* ★ **고르기 창은 한 번에 하나다** (#80 1). `beginSheetModal` 은 두 번 불려도 거절하지 않고
   시트를 **큐에 쌓는다**(AppKit 표준 동작) — 막을 자리는 Swift 가 아니라 **누르는 화면**이다.
   통로는 하나도 안 늘렸다: 잠긴 동안 안 쏘는 것이 전부다.

   ⚠ **푸는 신호가 두 줄에서 다르다. 계약이 달라서지 취향이 아니다.**
     · 던져넣기 — **취소도 답이 온다**(`pickAndExtractDocuments` 의 `finish`: *"취소도 여기로
       온다"*). 그래서 `onIngestFiles` 하나로 푼다. 백그라운드 추출이 몇 초 걸려도 그동안
       잠겨 있는 것이 맞다 — 읽는 중에 또 고르면 짐이 두 벌 온다.
     · 볼트 — **취소 때 아무것도 안 온다**(`AppDelegate.pickVaultFolder` 의
       `guard resp == .OK … else { return }`). 답이 오면(`setSystemState`) 풀고, 안 오면
       **스스로 푼다.** 안 그러면 취소한 사람의 버튼이 영영 죽는다.
   ⚠ 자가 해제가 덮는 것은 **시트가 붙기 전 구간**뿐이다 — 붙고 나면 창이 시트 모달이라
     클릭이 화면까지 안 온다. 그래서 짧아도 된다(`morphing` 이 200ms 로 같은 일을 한다). */
const PICKING={ingest:false,vault:false};
const PICK_FREE_MS=1000;
/** 처음 한 번만 참 — 연타의 둘째부터는 거짓(= 쏘지 않는다). **표를 인자로 받는다**:
    그래야 `node --test` 가 화면 전역 없이 이 규칙만 잰다. */
const pickTake=(lock,which)=>{if(!lock||lock[which])return false;lock[which]=true;return true};
const pickFree=(lock,which)=>{if(lock)lock[which]=false};
/** 잠긴 줄의 버튼은 **눌리지 않는다** — 잠금이 안 보이면 사람은 안 눌린 줄 알고 또 누른다.
    ⚠ 그리는 자리마다 다시 부른다(화면을 새로 지으면 `disabled` 도 같이 날아간다). */
function paintPicking(id,which){const b=document.getElementById(id);if(b)b.disabled=!!PICKING[which]}
/* ★ **정본이 도착했나** (박선호 2026-09-02: *"정상적인 로딩상태 표시를 안하고 이전 값을 보여주는"*).
   브리지가 있으면 `load()` 는 빈 문서를 돌려주고 진짜는 `receiveDocument` 로 뒤에 온다 —
   그 사이에 그리면 **빈 저장소**(「아직 쌓인 답변이 없어요」)가 먼저 뜨고 문서가 오면
   갈아끼워진다. 브라우저 단독은 `load()` 가 곧 정본이라 처음부터 참이다. */
let RECEIVED=!bridged();
/* 쌓기 모드 안의 화면 — 조각 편집이냐 던져 넣기냐 (#14). **모드가 아니다** */
/* ⚠ **「첫 실행이면 받기 화면」이 걷혔다** (승격 라운드, #61 A). 시작 화면은 언제나
   쌓기다 — 비어 있으면 **빈 쌓기**가 뜨고, 넣는 문은 왼쪽 칸이 든다(위·아래 버튼·드롭).
   그래서 `opensIngest`·`onlySeeds`·`ingestOptOut`(한 번 나갔나) 셋이 같이 걷혔다:
   끌고 가는 화면이 없으면 「나갔다」를 기억할 이유도 없다. */
let stackView="edit";
/* ★ **`"canvas"` 가 죽었다** (#67 재편, 박선호 2026-09-02: *"따로 지도 버튼이 있는게 아니라"*).
   뜻 지도는 화면이 아니라 **쌓기 홈의 가운데 칸**이다 — 「확대」는 모드 전환이 아니라
   양쪽 패널을 접는 것이고, 그러면 가운데가 `flex:1` 로 저절로 커진다(`#cols` CSS).
   그래서 `stackView` 가 드는 것은 이제 셋: `edit`(홈 3단) · `settings` · `ingest`. */
/* ★ **설정에 잠깐 다녀오는 사람의 자리표** (#65 P3-4). 나가는 문(`setback`)이 언제나 홈이라,
   받기 화면에서 메뉴바 「Settings…」로 들어오면 **붙여넣던 자소서가 죽고 돌아갈 길도 없었다.**
   ⚠ **한 번만 산다** — `ingestRender` 가 글을 되돌리면서 비운다. 안 비우면 다음에 받기 화면을
     여는 사람에게 남의 글이 앉는다. 세우는 자리는 `openSettingsScreen` 하나다. */
let SETBACK=null;
/* ★ 3단의 양쪽 폭 — **세션에 산다.** 사람이 끈 자리는 다시 그려도 남아야 하고(그리는 자리가
   여럿이다), 파일에는 안 남긴다 — 창 크기가 기기마다 다른데 폭만 따라가면 접힌 채로 뜬다.
   `0` = 접힘. 복귀 폭은 `PANE_DEF` 가 든다. */
const PANE_DEF={l:242,r:340},PANE_MIN={l:180,r:250},PANE_SNAP=140,PANE_MAX=560;
/* ★ **오른쪽 판은 기본 접힘** (박선호 2026-09-02: *"굳이 오른쪽 패널이 있어야되나?"*). 하는 일이
   「쓰기」 하나라 별을 고르거나 + 를 누를 때만 연다(`paneOpen`). 우주가 그만큼 넓다. */
let PANE={l:PANE_DEF.l,r:0};
let EXPLORER_WIDTH=PANE_DEF.l;
function paneApply(key,w){
  if(key==="r"&&w<=0&&PANE.r>0&&!leaveEditorAllowed(()=>paneApply(key,w)))return;
  PANE[key]=w;
  if(key==="l"&&w>0)EXPLORER_WIDTH=w;
  const p=document.getElementById(key==="l"?"left":"right"),h=document.getElementById(key==="l"?"rzl":"rzr");
  if(p){p.style.width=w+"px";p.classList.toggle("zip",w<=0)}
  if(h)h.dataset.zip=w<=0?"1":"0";
  if(key==="l")paintExplorerToggle();
  if(key==="r"){
    const cols=document.getElementById("cols");if(cols)cols.classList.toggle("document-open",w>0);
    if(p)p.inert=w<=0;
    canvasApplyVT();canvasWake();
  }
}
function paneOpen(key){if(PANE[key]>0)return;paneApply(key,PANE_DEF[key]);if(key==="l"&&typeof canvasFit==="function")canvasFit()}
/* 왼쪽 목록 거르개의 글자. **자가 아니다** — 글자가 들어 있나만 본다(`#lfind` CSS 머리글) */
let LFIND="";
/* ⚠ **별을 끌어 옮긴 자리 표가 죽었다** (#74). 자리는 이제 볼트 폴더(궤도)가 정하고,
   끌기는 **이 세션의 위상**일 뿐이다 — 파생 사이드카도 그 통로도 같이 걷혔다.
   ⚠ 사용자의 옛 `.clonie/layout.json` 은 **안 읽고 안 지웠다** — 코드를 되돌리면 다시 읽힌다. */
/* ★ 뜻 지도 (#67) — 그 칸이 드는 것 셋.
   `CANVQ` = 지금 던진 질문 글자 · `CQV` = **그 글자의 뜻 벡터**(`{q,v}`) · `CANV` = 배치 한 판.
   ⚠ **`QVEC` 를 안 건드린다.** 그것은 면접이 들은 말의 벡터고, 지도에서 덮으면 면접으로
     돌아갔을 때 순위가 **지도에서 친 질문**으로 매겨진다 — 같은 칸을 두 화면이 나눠 쓰는 자리.
   ⚠ `CANV` 는 조각 목록이 그대로면 **살려 둔다** — 사람이 끌어 옮긴 자리가 저장 한 번에
     날아가면 「배치 = 내 멘탈맵」이 거짓말이 된다. 갈렸나는 id 서명(`sig`)으로 잰다. */
let CANVQ="",CQV=null,CANV=null,CANVAS_RESIZE=null;
/* ★ 면접 범위 (#73 Q20 · #79 2026-09-04 결재).
   `LAST_SUN` = 저장소 화면에서 **마지막으로 켠 항성**. 끄는 것은 이 값을 안 지운다 —
     「마지막에 보던 것」이지 「지금 켜져 있는 것」이 아니다(면접이 그것을 기본값으로 든다).
   `LIVE_SUN` = 면접이 **지금** 쓰는 범위. `null` = 갤럭시(전부).
   ⚠ 둘은 세션에만 산다. 창을 다시 열면 갤럭시부터다 — 기억할 값이면 볼트가 들어야 한다. */
let LAST_SUN=null,LIVE_SUN=null;
/* ★ 태양에 친 질문 중 **뜻 벡터를 기다리는** 것 (#79). 같은 글자의 벡터가 오면 그때 기록한다 —
   색 없는 줄을 먼저 적으면 「그때 저장소가 얼마나 답했나」가 영영 빈 칸으로 남는다.
   ⚠ 글자가 바뀌면 앞 것은 **버린다**: `canvasAsk` 가 그때마다 덮어쓴다(벡터는 영영 안 올 수 있다). */
let askLogPending=null;
/* 받기 진행 (#40). `{items, ks:[지금 만드는 덩이], draft:{k:{title,body,how}}, n,got,fail,
   banner, done, saved}` · 안 돌고 있으면 null. **세션에만 산다.** */
let INTAKE=null;
/* ★ 「공통 지능」 (#51 → #55) — 받기 화면의 **한 칸**. Swift 가 `setCloudDrafter` 로
   알려준 것은 사다리 두 층의 준비 상태다: `key`(설정에 키·모델이 있나) · `cli`(이 맥에
   공식 CLI 가 깔려 있나) · `ready`(둘 중 하나라도). `on` 은 **지금 켜져 있나**다.
   ⚠ **키도 경로도 여기 안 온다** — 화면은 WebView 라 여기 앉힌 글자는 우리 손을 떠난다.
   ★ **#55 가 기본값을 뒤집었다.** 전엔 꺼짐이 기본인 옵트인이었다(#51). 지금은
     **연결된 공통 지능이 있으면 그것이 기본**이고, 온디바이스가 폴백이다
     (박선호 2026-08-31: *"차라리 기존 ai 구독연결및 api 연결을 염두해두고 공통적인
     지능을 연결시켜서 확장 및 튜닝으로 가는게 맞아 보이는데"*).
   ⚠ **그래서 남기는 것이 「끔」 하나로 뒤집혔다.** #51 은 「켰다」를 파일에 안 남겼다 —
     그게 다음 문서를 조용히 내보내기 때문이다. **「껐다」에는 그 위험이 없다**: 남은 것이
     조용히 만드는 결과는 언제나 「안 나간다」쪽이다. 그래서 끈 것만 남기고 켠 것은 안 남긴다.
   ⚠ `touched` = **이번 세션에 사람이 손댔나.** 설정 저장 때 `setCloudDrafter` 가 다시
     오는데, 그때 방금 사람이 끈 것을 기본값으로 되돌리면 안 된다. */
/* ⚠ **「지금 고른 두뇌」는 이 칸에 없다** (2026-09-02, 리뷰 발견 ⑥). 그 집은 `CHOICE` 하나고
     이 회신은 **그 칸을 채워 주기만** 한다(`setCloudDrafter`) — 여기 한 벌 더 두면 설정 화면과
     받기 화면이 서로 다른 선택을 들고 있게 된다. `cli`(= CLI 층이 준비됐나)도 같이 걷었다:
     아무도 안 읽었고, 화면이 읽는 것은 「이번에 두드릴 층」(`lane`) 하나다. */
let CLOUD={ready:false,on:false,key:false,hasKey:false,lane:"",
           provider:"",model:"",cliName:"",autoLabel:"",why:""};
let cloudTouched=false;
/* 사람이 「이 맥 안에서만」을 골라 남긴 것. **값이 있을 때만 뜻이 있다** — 없으면 미선택이다.
   ⚠ 브라우저 단독(`cue.html`)에도, WebView 안에도 같은 코드가 돈다. WebView 는 origin 이
     없어 `localStorage` 가 사고를 낼 수 있고, 그러면 **안 남는 채로 잘 도는 것**이 맞다
     (기본값이 매 세션 다시 정해질 뿐, 되돌리기는 여전히 토글 하나다). */
const DKEY="cue.drafter.v1";
const readDrafterPref=()=>{try{return localStorage.getItem(DKEY)||""}catch(e){return ""}};
const writeDrafterPref=v=>{try{v?localStorage.setItem(DKEY,v):localStorage.removeItem(DKEY)}catch(e){}};
/* ⚠ **채우기 흐름(#35)이 통째로 죽었다** (#74 C5). 그 흐름이 짚던 것은 「미리 써 둔 질문의
   구멍」이고, 질문을 미리 쓰지 않기로 한 순간(ADR 0006) 짚을 구멍이 없다.
   같이 죽은 것: 흐름 상태 둘 · 열기·닫기·다음·현재 구멍·순서 짓기 다섯 · 코칭 문구 셋 ·
   띠와 버튼 넷. **옛 이름을 여기 안 적는다** — 걷힘을 세는 검사(#74 AC7)가 주석을 안 가려서,
   적으면 그 자리가 안 걷힌 것으로 세어진다. 목록의 정본은 #74 다. */
/* ★ 연습 (#36). **세션에만 산다** — 성적은 파일에 안 남는다. 연습은 기록이 아니라 리허설이고,
   남기면 다음 세션이 그 수를 「내 실력」으로 읽는다.
   `{ids:[질문id…], k:몇 번째, head/headq:쌓인 발화, cur/vol/curq:지금 발화, res:{질문id:채점}, done}`
   ⚠ 글자가 **두 벌**인 이유는 면접 모드와 같다 — 보이는 것은 들린 그대로(`head`+`cur`+`vol`),
     검색에 넣는 것은 부호를 걷은 것(`headq`+`curq`, `TranscriptText.forSearch`). */
let prac=null;
/* ★ 면접 중에 주운 「저장소가 못 덮는 질문」 (#22). **세션에만 산다** —
   쌓기로 돌아갈 때 한 번에 문서로 옮기고 비운다. 면접 중에는 저장을 안 건드린다. */
let harvest=[];
/* ── ★ 입력 기록 (ADR 0006 §③ · #79 2026-09-04 결재: 전부 + 그때의 색) ─────────────
   **실제로 온 입력**만 여기 산다 — 태양에 친 것(`canvasAsk`)과 면접에서 들린 것
   (`judgeHarvest` → `commitHarvest`). 미리 쓴 질문은 없다(질문을 안 쓰기로 했다).
   ⚠ **색은 온 순간 `rank()` 가 준 것**이다. 나중에 다시 안 잰다 — 기록이 드는 사실은
     「그때 저장소가 얼마나 답했나」이지 「지금 답하나」가 아니다.
   ⚠ **글자 자 판정에는 색을 안 적는다** (#53: 그 자는 세 무리를 못 갈라 색을 못 낸다).
     이미 적힌 색도 글자 자로는 안 덮는다 — 못 재는 자가 잰 자를 지우면 안 된다.
   ⚠ **가르는 것은 자 이름이 아니라 「색을 냈나」다.** 뜻 자도 색이 없을 때가 있다 —
     저장소가 비어 순위가 한 줄도 안 나오는 자리다(`canvasNoteAsked` 의 `r.length===0`).
     그것도 **못 잰 것**이라 있던 색을 안 덮는다. 자 이름만 보면 그 줄이 초록을 `null` 로 지운다.
   ⚠ **불변이다** — 새 배열을 돌려준다. 부르는 쪽이 `DOC.asked` 에 앉히고, 시험은 입력을
     다시 읽어 「안 건드렸나」를 잰다. */
const isAskedId=id=>typeof id==="string"&&id.startsWith("a-");
const askedById=id=>(DOC.asked||[]).find(x=>x.id===id)||null;
/* ★ 순위 한 벌을 **기록의 판정**으로 옮긴다. 기록 줄(`DOC.asked`)과 면접 세션 버퍼
   (`askedPending`)가 **같은 규칙**을 쓰라고 여기 하나만 둔다 — 두 곳에서 각자 짜면
   한쪽만 고쳐지고 그 갈림이 조용히 산다(`rank` 를 두 곳에서 다시 정렬하지 않는 것과 같은 규율).
   ⚠ 색은 **뜻 자일 때만** 나온다 (#53) — 글자 자는 세 무리를 못 갈라 색을 못 낸다.
   `how0` = 순위가 **한 줄도 없을 때** 적을 자 이름. 저장소가 통째로 빈 채 뜻 자로 잰 자리가
   그것이고(`canvasNoteAsked`), 안 주면 자 이름 없이 적힌다(면접 쪽 — 잰 것이 없으면 잰 자도 없다). */
const verdictOf=(r,how0)=>{
  const m=!!(r&&r.length&&r[0].how==="뜻");
  return m?{c:r[0].c,s:r[0].s,how:"뜻"}
          :{c:null,s:null,how:(r&&r.length)?r[0].how:(how0||null)};
};
function logAsked(list,text,source,verdict,at0,count0=1){
  const t=(text||"").trim();
  if(!t)return list||[];
  const at=at0||now();
  // 면접 버퍼는 여러 번 들린 질문을 한 줄로 합친다. 저장할 때 그 횟수를 한 번으로 줄이지 않는다.
  const count=Number.isSafeInteger(count0)&&count0>0?count0:1;
  const mean=!!(verdict&&verdict.how==="뜻"&&verdict.c);   /* 색이 있어야 「잰 것」이다 — 위 두 번째 ⚠ */
  const out=(list||[]).slice();
  const k=out.findIndex(x=>sim(t,x.text)>=SAME_Q);
  if(k>=0){
    const o=out[k];
    out[k]=Object.assign({},o,{at:at,count:(o.count||1)+count},
      mean?{color:verdict.c,score:verdict.s,how:"뜻"}:{how:o.color?o.how:((verdict&&verdict.how)||"글자")});
    return out;
  }
  out.push({id:uid("a"),text:t,source:source,at:at,
    color:mean?verdict.c:null,score:mean?verdict.s:null,
    how:verdict?verdict.how:null,count:count});
  return out;
}
/* 되묻는 순서 — **약한 것부터** (#79 결재). 자 = 연습에서 마지막으로 받은 색(`practiceColor`),
   없으면 온 순간의 색. 빨강 → 주황 → **모름**(글자 자·색 없음) → 초록.
   ⚠ 모름이 초록보다 앞이다 — 못 잰 것과 답한 것은 다르고, 못 잰 쪽이 급하다.
   같은 색이면 최근 것 먼저: 어제 못 답한 것이 지난주 것보다 뜨겁다. */
/* ⚠ **네 칸이 다 여기 있다.** 「모름」을 지도 밖 숫자로 두면 칸 사이의 거리가 두 곳에서
   정해져, 색을 하나 더할 때 이 지도만 고치고 그 숫자는 그대로 남는다(리뷰 Magic Number). */
const ASKED_RANK={r:0,a:1,"?":2,g:3};   /* "?" = 색 없음 — 글자 자·빈 저장소 */
function askedOrder(list){
  const key=x=>{const c=x.practiceColor||x.color||"?";return ASKED_RANK[c in ASKED_RANK?c:"?"]};
  return (list||[]).slice()
    .sort((a,b)=>key(a)-key(b)||String(b.at||"").localeCompare(String(a.at||"")))
    .map(x=>x.id);
}
/* ★ 면접에서 들린 것의 **세션 버퍼** — `harvest` 와 같은 수명이다(면접 중에는 저장을 안
   건드린다, #22). ⚠ **`harvest` 와 규칙이 다르다**: 저기는 빨강만 줍고(예상 질문에 얹으려는
   것이라서), 여기는 **전부** 든다 — 「무엇을 물어봤나」가 연습의 재료고, 초록이었다는 사실이
   다음에 그것을 뒤로 보낸다(`askedOrder`). */
let askedPending=[];
/* ⚠ **버퍼도 `logAsked` 를 지난다** — 병합 자(`sim>=SAME_Q`)도 뜻/글자 규칙도 기록 줄과 한 벌이다.
   그래서 여기 쌓이는 것은 **기록 줄과 같은 모양**이고, `commitHarvest` 는 그것을 그대로 옮긴다.
   같은 면접 안에서 다시 들린 것은 줄을 안 늘리고 횟수만 오른다(색은 잰 자가 왔을 때만 갈린다). */
function noteAsked(t,r){askedPending=logAsked(askedPending,t,"interview",verdictOf(r))}
/* ── 면접 모드 전사 상태 (#17) ──
   heardV/mineV = **검색에 넣는 글자**. 브리지가 있으면 Swift 가 부호를 걷어서 준다(`TranscriptText`) —
   `실측 2026-08-28`(#15): 끝의 `?` 하나가 정답을 한 칸 밀어낸다.
   화면에 보이는 것은 curConf/curVol 이고 그건 **들린 그대로**다. 요약도 손질도 안 한다(라운드 8 Q1). */
let hist=[],curWho="them",trouble=null;
/* ⚠ **관마다 따로 든다.** 두 관은 동시에 살아 있어서 한 칸에 담으면 서로를 지운다 —
   `실측 2026-08-28`: 한 질문 동안 them↔me 가 여섯 번 오갔다(마이크가 주변 소리를 문다).
   지난 줄로 밀어 올리는 것은 **그 관의 `ended` 가 왔을 때뿐**이다. 화자가 바뀌는 것은 발화가 끝난 것이 아니다. */
const CUR={them:{c:"",v:""},me:{c:"",v:""}};
/* 화면에 실제로 걸린 순서. **1위가 바뀔 때만 갈아끼운다**(라운드 8 Q2-다) —
   밑의 둘은 속으로만 바뀌고, 점수 표기도 발화가 끝날 때만 새로 붙는다. 읽는 중에 화면이 안 튀게. */
const ORD={top:null,list:[],score:{},color:{},how:"글자"};

function blank(){return {schemaVersion:SCHEMA,questions:[],fragments:[],asked:[]}}
/* ★ 씨앗 조각에 **표식을 박는다** (`seed:true`, QA 2026-08-30 블로커 F2).
   ⚠ 표식이 없으면 이 한 장이 **실전 검색 1위**로 뜬다 — `실측`: 「성능 개선해본 경험이
     있나요」에 *"여기에 내 경험을 한 줄로 쓴다"* 가 1.042 초록 1위였다. 예시가 답으로
     나오는 것은 빈 결과보다 나쁘다(화면이 그것을 「준비된 조각」으로 칠한다).
   ⚠ **글자로 판별하지 않는다.** 문구를 그대로 둔 채 한 글자만 고쳐도 글자 비교는 틀리고,
     사람이 우연히 같은 문장을 쓰면 그 조각이 죽는다. 그래서 **생성 시 결정**이고,
     `Fragment.seed` 로 디스크를 건넌다 — 화면에만 두면 재기동 한 번에 사라진다.
   ⚠ 표식이 하는 일은 **라이브·연습 순위에서 빼는 것 하나뿐**이다. 목록·편집기·구멍 세기는
     그대로다 — 씨앗은 「채울 자리」로 보여야 한다. */
/* ⚠ **질문 축이 여기서 빠졌다** (#74 C5). 심는 것은 **조각 예시 한 장**뿐이다 —
   빈 우주는 고장으로 읽히지만, 안 물어본 질문 열 개는 사람의 볼트에 심을 것이 아니다. */
function seed(d){
  if(!d.fragments.length){const t=now();
    d.fragments=[{id:uid("f"),title:SEED_TITLE,body:SEED_BODY,questionIds:[],createdAt:t,updatedAt:t,seed:true}]}
  return d;
}
/* 이 조각이 아직 **예시**인가 — 순수 함수라 `node --test` 가 잠근다.
   사람이 한 번이라도 저장하면 화면이 표식을 뗀다(`sv` 손잡이). 그때부터 보통 조각이다. */
const isSeed=p=>!!(p&&p.seed);
/* ★ **표식이 생기기 전에 만들어진 볼트**에 표식을 한 번 박는다 (블로커 F2의 이행분).
   표식이 없던 판(2026-08-30 이전)으로 씨앗을 받은 사람은 이 줄이 없으면 영영 그 예시가
   1위로 뜬다 — 고친 코드가 **이미 있는 볼트를 안 고치는** 자리다.

   ⚠ **여기서만 글자를 본다. 그리고 그것이 안전한 이유가 있다** — 대조하는 것이
     *우리가 출하한 문구 두 개와 글자 단위로 같은가*라서, 걸리는 것은 **사람이 한 글자도
     안 고친 그 한 장**뿐이다. 판별자는 여전히 표식이고(`isSeed`), 이건 표식이 없던 시절의
     문서를 한 번 끌어올리는 **이행**이다. 한 번 박히면 다시는 이 길로 안 온다.
   - Returns: 뭐라도 박았으면 `true` — 부르는 쪽이 그때만 저장한다. */
function backfillSeed(d){
  let hit=false;
  ((d&&d.fragments)||[]).forEach(p=>{
    if(p.seed||p.title!==SEED_TITLE||p.body!==SEED_BODY)return;
    p.seed=true;hit=true;
  });
  return hit;
}
/* ⚠ **씨앗 질문을 정본에 박던 자리(`seedNeedsSave`)가 죽었다** (#74 C5).
   심을 질문이 없으니 박을 것도 없다 — 새 볼트를 열어도 `.clonie/questions.json` 이 안 생긴다.
   ⚠ **기존 볼트의 `questions.json` 은 안 건드린다** — 사람 데이터고, 연습이 그것으로 돈다.
   경위(질문이 디스크에 0개로 남던 2026-08-31 사고)는 #74 와 그 커밋이 든다. */
function load(){
  if(bridged())return blank();      /* Swift 가 receiveDocument 로 밀어넣는다 */
  let loaded;try{const r=localStorage.getItem(KEY);if(r)loaded=seed(JSON.parse(r))}catch(e){}
  loaded=loaded||seed(blank());VAULT_BASE=docCopy(loaded);return loaded;
}
const docCopy=d=>JSON.parse(JSON.stringify(d||blank()));
const sameDocValue=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
/* `base → local` 변경만 `remote` 위에 얹는다. id 가 있는 배열 셋은 외부에서 새로 들어온 행을
   남기고, 화면에서 실제로 고치거나 지운 행만 화면 쪽 결정을 따른다. */
function mergeDocRows(base,local,remote,key){
  const B=new Map(((base&&base[key])||[]).map(x=>[x.id,x]));
  const L=new Map(((local&&local[key])||[]).map(x=>[x.id,x]));
  const out=((remote&&remote[key])||[]).map(docCopy),at=new Map(out.map((x,i)=>[x.id,i]));
  for(const [id,b] of B){
    if(!L.has(id)){if(at.has(id))out.splice(at.get(id),1)}
    else if(!sameDocValue(b,L.get(id))){
      const i=out.findIndex(x=>x.id===id);if(i<0)out.push(docCopy(L.get(id)));else out[i]=docCopy(L.get(id));
    }
    at.clear();out.forEach((x,i)=>at.set(x.id,i));
  }
  for(const x of (local&&local[key])||[])if(!B.has(x.id)&&!out.some(y=>y.id===x.id))out.push(docCopy(x));
  return out;
}
function mergeDocument(base,local,remote){
  const out=docCopy(remote);
  out.schemaVersion=!sameDocValue(base&&base.schemaVersion,local&&local.schemaVersion)
    ?local.schemaVersion:remote.schemaVersion;
  out.questions=mergeDocRows(base,local,remote,"questions");
  out.fragments=mergeDocRows(base,local,remote,"fragments");
  out.asked=mergeDocRows(base,local,remote,"asked");
  return out;
}
function changedFragmentIDs(base,local){
  const B=new Map(((base&&base.fragments)||[]).map(x=>[x.id,x]));
  const L=new Map(((local&&local.fragments)||[]).map(x=>[x.id,x]));
  return [...new Set([...B.keys(),...L.keys()])].filter(id=>!sameDocValue(B.get(id),L.get(id)));
}
function holdDirty(ids,revision,replace=false){
  if(!revision)return;
  ids.forEach(id=>{if(id&&(replace||!DIRTY_REVISIONS[id]))DIRTY_REVISIONS[id]=revision});
}
function dirtyOverridesForSave(){
  const changed=new Set(changedFragmentIDs(VAULT_BASE,DOC)),out={};
  for(const id of Object.keys(DIRTY_REVISIONS)){
    if(changed.has(id))out[id]=DIRTY_REVISIONS[id];else delete DIRTY_REVISIONS[id];
  }
  return out;
}
function syncDirtyRevisionPins(force=false){
  const revisions={};
  for(const [id,token] of Object.entries(DIRTY_REVISIONS)){
    if(!token)continue;(revisions[token]||(revisions[token]=[])).push(id);
  }
  for(const token of Object.keys(revisions))revisions[token].sort();
  const sig=JSON.stringify(revisions);
  if(force||sig!==DIRTY_PIN_SIG){DIRTY_PIN_SIG=sig;post("pinVaultRevisions",{revisions})}
}
function editorSaveStateText(state){
  return {saved:"저장됨",dirty:"변경됨",saving:"저장 중…",failed:"저장 실패"}[state]||"";
}
function paintEditorSaveState(){
  const el=document.getElementById("docsavestate");if(!el)return;
  el.textContent=editorSaveStateText(EDITOR_SAVE_STATE);
  if(el.dataset)el.dataset.state=EDITOR_SAVE_STATE;
  if(el.setAttribute)el.setAttribute("aria-label",editorSaveStateText(EDITOR_SAVE_STATE));
}
function setEditorSaveState(state){EDITOR_SAVE_STATE=state;paintEditorSaveState()}
function clearEditorAutosave(){
  if(EDITOR_SAVE_TIMER!==null){clearTimeout(EDITOR_SAVE_TIMER);EDITOR_SAVE_TIMER=null}
}
function scheduleEditorAutosave(){
  clearEditorAutosave();
  if(EDITOR_COMPOSING||!(mode==="stack"&&stackView==="edit"&&PANE.r>0))return;
  EDITOR_SAVE_TIMER=setTimeout(()=>{
    EDITOR_SAVE_TIMER=null;
    const draft=takeEditorDraft();
    if(!draft||(draft.titleDirty===false&&draft.bodyDirty===false))return;
    saveEditorValue("auto");
  },EDITOR_AUTOSAVE_MS);
}
function save(origin="manual"){
  DOC.schemaVersion=SCHEMA;
  if(bridged()){
    if(SAVE_FLIGHT||!VAULT_REVISION){SAVE_PENDING=true;SAVE_PENDING_AUTO=origin==="auto";if(origin==="auto"||origin==="manual")setEditorSaveState("saving");return false}
    const sent=docCopy(DOC),requestID=++SAVE_SEQ,revisionOverrides=dirtyOverridesForSave();
    syncDirtyRevisionPins();
    SAVE_FLIGHT={requestID,document:sent,revision:VAULT_REVISION,revisionOverrides,auto:origin==="auto"};
    if(origin==="auto"||origin==="manual")setEditorSaveState("saving");
    post("saveDocument",{requestID,revision:VAULT_REVISION,revisionOverrides,
                         json:JSON.stringify(sent)});return true
  }
  try{localStorage.setItem(KEY,JSON.stringify(DOC));VAULT_BASE=docCopy(DOC);setEditorSaveState("saved");return true}
  catch(e){setEditorSaveState("failed");onVaultTrouble("저장하지 못했어요. 내용을 유지했으니 다시 저장해 주세요.");return false}
}
/* ★ 종료 준비는 800ms 자동 저장보다 먼저 **현재 편집 DOM을 저장 짐에 올린다**.
   AppKit 의 종료 보류는 이 화면이 `terminationReady` 를 보낸 뒤에만 풀린다. 저장 확인 전
   종료를 허가하면 `VaultIO.flush()` 는 아직 JS 에 닿지 않은 글자를 알 수 없다. */
function finishTermination(ok,token=TERMINATION_WAITING){
  if(!token||TERMINATION_WAITING!==token)return;
  TERMINATION_WAITING=null;
  post("terminationReady",{token,ok:!!ok});
}
function terminationSaveSettled(){
  if(!TERMINATION_WAITING)return;
  if(SAVE_FLIGHT||SAVE_PENDING)return;
  const draft=takeEditorDraft();
  if(draft&&(draft.titleDirty||draft.bodyDirty)){
    if(!saveEditorValue("manual"))finishTermination(false);
    return;
  }
  if(vaultHasDraft()){
    save("manual");
    if(SAVE_FLIGHT||SAVE_PENDING)return;
    finishTermination(false);return;
  }
  finishTermination(true);
}
function prepareForTermination(token=uid("termination")){
  clearEditorAutosave();
  TERMINATION_WAITING=token;
  if(mode==="stack"&&stackView==="edit"){
    const draft=takeEditorDraft();
    if(draft&&(draft.titleDirty||draft.bodyDirty)){
      if(!saveEditorValue("manual")){finishTermination(false);return}
    }
  }
  if(!SAVE_FLIGHT&&!SAVE_PENDING&&vaultHasDraft())save("manual");
  terminationSaveSettled();
}
function cancelTerminationPreparation(token,reason=""){
  if(!token||TERMINATION_WAITING!==token)return;
  TERMINATION_WAITING=null;
  if(reason)onVaultTrouble(reason);
}
/* 화면을 다시 지어도 편집기의 **저장 전 글자와 커서**를 되놓는다. `sel` 인덱스는 외부 md가
   끼어들면 달라지므로 id로 잡는다. 고른 파일이 밖에서 지워졌으면 새 조각 칸으로 보존한다. */
function takeEditorDraft(){
  if(!(mode==="stack"&&stackView==="edit")||PANE.r===0)return null;
  const ti=document.getElementById("ti"),bo=document.getElementById("bo");if(!(ti&&bo))return null;
  const active=document.activeElement===ti?"ti":document.activeElement===bo?"bo":null;
  const a=active?document.getElementById(active):null;
  const cur=sel===null?null:DOC.fragments[sel];
  return {id:cur&&cur.id||null,title:ti.value,body:bo.value,
    titleDirty:ti.value.trim()!==(cur&&cur.title||""),bodyDirty:bo.value!==(cur&&cur.body||""),active,
    start:a&&typeof a.selectionStart==="number"?a.selectionStart:null,
    end:a&&typeof a.selectionEnd==="number"?a.selectionEnd:null,
    direction:a&&a.selectionDirection||"none"};
}
function putEditorDraft(d){
  if(!d)return;
  const ti=document.getElementById("ti"),bo=document.getElementById("bo");if(!(ti&&bo))return;
  const cur=sel===null?null:DOC.fragments[sel];
  ti.value=d.titleDirty?d.title:(cur&&cur.title||"");
  bo.value=d.bodyDirty?d.body:(cur&&cur.body||"");
  const a=d.active==="ti"?ti:d.active==="bo"?bo:null;
  if(a){a.focus();if(d.start!==null&&a.setSelectionRange)a.setSelectionRange(d.start,d.end,d.direction)}
}
/* ★ Swift → JS 문서 통로 하나. `meta.revision` 은 Swift 안의 실제 리비전을 가리키는 불투명 표다.
   `save` 확인이면 보낸 뒤 변경만, `reload`면 마지막 수신 뒤 변경만 새 디스크 문서 위에 얹는다. */
function receiveDocument(json,note,meta){
  VAULT_CONNECTED=true;
  const editor=meta&&meta.kind!=="load"&&RECEIVED?takeEditorDraft():null;
  const selectedID=workspaceSelectedID();
  const oldEntries=VAULT_ENTRIES;
  const oldSelectedPath=workspaceFile(selectedID)?.path;
  const beforeRevision=VAULT_REVISION,flight=SAVE_FLIGHT;
  const selectedPath=editor&&editor.id?PATHS[editor.id]:null;
  const dialogNode=document.getElementById("vaultdialog");
  const actionDialog=meta&&meta.kind!=="load"&&dialogNode&&dialogNode.parentNode?dialogNode:null;
  if(meta&&meta.kind==="reload"&&!flight){
    holdDirty(changedFragmentIDs(VAULT_BASE,DOC),beforeRevision);
    if(editor&&editor.id&&(editor.titleDirty||editor.bodyDirty))holdDirty([editor.id],beforeRevision);
  }
  RECEIVED=true;
  let d;try{d=JSON.parse(json)}catch(e){d=blank()}
  const remote={schemaVersion:d.schemaVersion||SCHEMA,questions:d.questions||[],fragments:d.fragments||[],
                     asked:d.asked||[]};
  let next=remote,runPending=false,pendingAuto=false;
  if(meta&&meta.kind==="load"){
    /* 첫 기동·볼트 교체다. 옛 볼트의 늦은 저장 확인을 새 볼트에 이어 보내지 않는다. */
    SAVE_FLIGHT=null;SAVE_PENDING=false;SAVE_PENDING_AUTO=false;VAULT_ACTION=null;EDITOR_NAVIGATION=null;
    setEditorSaveState("saved");
    for(const id of Object.keys(DIRTY_REVISIONS))delete DIRTY_REVISIONS[id];
  }else if(meta&&meta.kind==="save"&&SAVE_FLIGHT&&meta.requestID===SAVE_FLIGHT.requestID){
    next=mergeDocument(SAVE_FLIGHT.document,DOC,remote);
    const unsaved=changedFragmentIDs(remote,next),base=meta.savedRevision||SAVE_FLIGHT.revision;
    for(const id of Object.keys(SAVE_FLIGHT.revisionOverrides))delete DIRTY_REVISIONS[id];
    holdDirty(unsaved,base,true);
    if(editor&&editor.id&&(editor.titleDirty||editor.bodyDirty))holdDirty([editor.id],base,true);
    pendingAuto=SAVE_PENDING_AUTO;
    SAVE_FLIGHT=null;runPending=SAVE_PENDING;SAVE_PENDING=false;SAVE_PENDING_AUTO=false;
    if(editor&&(editor.titleDirty||editor.bodyDirty))setEditorSaveState("dirty");
    else setEditorSaveState("saved");
  }else if(meta&&meta.kind==="conflict"&&SAVE_FLIGHT&&meta.requestID===SAVE_FLIGHT.requestID){
    next=mergeDocument(VAULT_BASE,DOC,remote);
    const base=SAVE_FLIGHT.revision;
    holdDirty(changedFragmentIDs(remote,next),base);
    if(editor&&editor.id&&(editor.titleDirty||editor.bodyDirty))holdDirty([editor.id],base);
    SAVE_FLIGHT=null;SAVE_PENDING=false;SAVE_PENDING_AUTO=false;setEditorSaveState("failed");
    finishTermination(false);
  }else if(meta&&meta.kind==="reload"){
    next=mergeDocument(VAULT_BASE,DOC,remote);
  }
  VAULT_BASE=docCopy(remote);DOC=next;
  if(meta&&meta.revision)VAULT_REVISION=meta.revision;
  PATHS=(d&&d.paths)||{};
  VAULT_FOLDERS=(meta&&meta.folders)||[];VAULT_TRASH=(meta&&meta.trash)||[];
  VAULT_ENTRIES=(meta&&meta.entries)||[];
  const movedPath=path=>{const old=oldEntries.find(e=>e.path===path);if(!old)return path;const matches=VAULT_ENTRIES.filter(e=>e.id===old.id);return matches.find(e=>e.path===path)?.path||(matches.length===1?matches[0].path:path)};
  const nextSelectedPath=movedPath(oldSelectedPath);
  const nextSelected=workspaceFiles().find(f=>f.path===nextSelectedPath);
  if(editor&&nextSelected&&!nextSelected.p.entry&&!editor.titleDirty&&!editor.bodyDirty)editor.id=nextSelected.p.id;
  WORKSPACE_SELECTED_ID=meta?.kind==="load"?null:nextSelected?.p.id||null;
  if(meta?.kind==="load"){WORKSPACE_SCOPE="";LZIP=Object.fromEntries(VAULT_FOLDERS.map(p=>[p,true]))}
  else {WORKSPACE_SCOPE=movedPath(WORKSPACE_SCOPE)||"";LZIP=Object.fromEntries(Object.entries(LZIP).map(([p,v])=>[movedPath(p),v]));if(CANV&&CANV.relatedID===selectedID)CANV.relatedID=nextSelected?.p.id||null}

  if(meta&&meta.kind==="load")VAULT_LAST_OPERATION=null;
  notice=note||null;
  /* 초안 벡터도 낡았다 (#33). 지우는 이유는 「틀려서」가 아니라 **가리키던 화면이 사라져서**다 —
     남겨두면 앞 문서의 답 벡터로 연습 첫 채점이 나온다. */
  for(const k in DRAFT)delete DRAFT[k];
  /* 볼트 교체·옛 통로는 받기를 버린다. 저장 확인과 같은 볼트의 외부 reload는 **안 버린다**:
     이제 저장마다 문서 확인이 돌아오므로 여기서 지우면 여러 덩이 중 첫 저장 뒤 나머지가 사라진다. */
  if(!meta||meta.kind==="load")INTAKE=null;
  /* ★ **벡터도 같이 버린다** (#66-3, `실측 2026-09-01`). 전 판은 `DRAFT`·`INTAKE`·`fill` 은
     비우면서 `VEC`·`QVEC` 만 남겼다 — 그런데 이 둘은 **id 로 조각을 짚는다.** 볼트를 밖에서
     갈아 같은 id 에 다른 글이 앉으면(rebindVault·flushPendingVaultReload 가 그 경로다)
     낡은 벡터가 새 글의 것인 척 초록을 낸다: 실측에서 "오늘 점심 메뉴" 조각이 "주도적으로
     문제를 해결한 경험" 에 초록이었다.
     ⚠ **색인이 실패하면 `receiveVectors` 가 영영 안 온다** — 그때 낡은 자를 들고 있으면
       그 거짓말이 안 걷힌다. 못 재는 것은 화면이 이미 정직하게 말한다(「색인이 아직 없어요」). */
  VEC=null;QVEC=null;
  syncDirtyRevisionPins(meta&&meta.kind==="load");
  /* 표식 없던 판으로 만들어진 씨앗을 한 번 끌어올린다 (블로커 F2 이행). 저장까지 해야
     디스크에 앉는다 — 안 그러면 열 때마다 다시 박고 재기동하면 또 1위로 뜬다. */
  const filled=backfillSeed(DOC);
  /* ⚠ **질문 축의 저장이 여기서 빠졌다** (#74 C5) — 심을 질문이 없다. 남은 저장은
     씨앗 조각 표식의 이행분 하나뿐이다. */
  if(filled)save();
  if(editor&&editor.id){const i=DOC.fragments.findIndex(p=>p.id===editor.id);sel=i<0?null:i}
  else if(editor)sel=null;
  else if(meta&&meta.kind!=="load"&&selectedID){const i=DOC.fragments.findIndex(p=>p.id===selectedID);sel=i<0?null:i}
  else sel=null;
  if(nextSelected&&oldSelectedPath!==nextSelected.path&&!(editor&&(editor.titleDirty||editor.bodyDirty)))WORKSPACE_SCOPE=nextSelected.path.split("/").slice(0,-1).join("/");
  if(!editor&&WORKSPACE_SELECTED_ID){const i=DOC.fragments.findIndex(p=>p.id===WORKSPACE_SELECTED_ID);sel=i<0?null:i}
  if(editor&&editor.id&&PATHS[editor.id]!==selectedPath)revealWorkspaceFile(editor.id);
  /* ★ **설정 화면이면 다시 안 그린다** (#65 ⑨). `onQuestionTidy` 가 쓰는 그 가드와 같은
     모양·같은 이유다: 이 화면은 문서를 한 글자도 안 그리는데, 다시 그리면 사람이 치고 있던
     주소·키·모델 칸이 통째로 날아간다 — 「보던 것을 뺏는 것」이 기능 하나보다 비싸다.
     ⚠ **위의 상태 갱신은 다 지났다.** 건너뛰는 것은 **그리기 한 번**뿐이고, 알림(`notice`)도
       안 사라진다 — 설정을 나가는 문(`setback`)이 `stackRender()` 를 부르고 그때 그려진다. */
  if(mode==="stack"&&stackView==="settings"){paintHomeList();if(runPending)save(pendingAuto?"auto":"manual");terminationSaveSettled();return}
  /* 자동 저장 확인은 문서·목록 상태만 갱신한다. `render()` 를 부르면 textarea와
     selection이 통째로 새로 생겨서, 사용자가 계속 치던 자리를 빼앗는다. */
  if(meta?.kind==="save"&&flight?.auto&&meta.requestID===flight.requestID){
    paintHomeList();
    paintEditorSaveState(editor&&(editor.titleDirty||editor.bodyDirty)?"dirty":"saved");
    if(runPending)save(pendingAuto?"auto":"manual");
    terminationSaveSettled();
    resumeEditorNavigation(true);return;
  }
  render();if(actionDialog)app.appendChild(actionDialog);putEditorDraft(editor);
  if(runPending)save(pendingAuto?"auto":"manual");
  terminationSaveSettled();
  if(meta?.kind==="conflict")EDITOR_NAVIGATION=null;
  else resumeEditorNavigation(meta?.kind==="save");
}
function onVaultDisconnected(){
  VAULT_CONNECTED=false;RECEIVED=true;DOC=blank();VAULT_BASE=blank();VAULT_REVISION=null;
  SAVE_FLIGHT=null;SAVE_PENDING=false;SAVE_PENDING_AUTO=false;EDITOR_NAVIGATION=null;sel=null;WORKSPACE_SELECTED_ID=null;WORKSPACE_SCOPE="";VAULT_ENTRIES=[];VEC=null;QVEC=null;
  for(const id of Object.keys(DIRTY_REVISIONS))delete DIRTY_REVISIONS[id];
  finishTermination(false);
  render();
}
/* 쓰기가 실패해도 다음 저장을 영영 막지 않는다. 글자는 이미 DOC/편집 DOM에 있으므로 그대로 둔다. */
function onDocumentSaveFailed(requestID){
  if(!SAVE_FLIGHT||SAVE_FLIGHT.requestID!==requestID)return;
  const editor=takeEditorDraft(),base=SAVE_FLIGHT.revision;
  holdDirty(changedFragmentIDs(VAULT_BASE,DOC),base);
  if(editor&&editor.id&&(editor.titleDirty||editor.bodyDirty))holdDirty([editor.id],base);
  SAVE_FLIGHT=null;SAVE_PENDING=false;SAVE_PENDING_AUTO=false;EDITOR_NAVIGATION=null;
  setEditorSaveState("failed");
  syncDirtyRevisionPins();
  finishTermination(false);
}

/* ★ 벡터 꾸러미가 들어오는 자리 (#34). Swift `ContentGraph` 가 색인을 돌린 뒤 **비동기로** 부른다 —
   `sendDocument` 와 나란히 가지만 임베딩이 끝나야 알 수 있어서 뒤따라온다.
   ⚠ **JS→Swift 통로는 하나도 안 늘렸다.** 늘어난 것은 Swift→JS 뿐이다(그쪽은 배열에 안 박혀 있다).
   ⚠ 안 오는 것이 정상인 경우가 셋: 브라우저 단독(`cue.html`) · 모델 미설치 · 색인 실패.
     그때 `VEC` 는 null 로 남고 화면은 bigram 으로 돈다 — **선언된 갈림**이지 고장이 아니다. */
function receiveVectors(json){
  /* ★ **실패도 화면에 반영한다** (#66-6, `실측 2026-09-01`). 이른 `return` 셋이 자만 지우고
     칠하지 않아서, 색인이 실패한 뒤에도 준비도 줄과 점 색이 **낡은 값 그대로** 남았다 —
     다음 렌더에서야 뒤집혀 그동안 한 화면이 두 말을 했다. 나가는 문을 하나로 모은다. */
  let d;try{d=JSON.parse(json)}catch(e){return dropVectors()}
  const dim=d&&d.dimensions;
  if(!(dim>0))return dropVectors();
  const frags={},passages={},ques={},F=d.fragments||{},P=d.passages||{},Q=d.questions||{};
  for(const k in F){const v=unvec(F[k],dim);if(v)frags[k]=v}
  for(const k in P){
    const list=(P[k]||[]).map(x=>{
      if(!x||typeof x.id!=="string"||typeof x.sourceText!=="string")return null;
      const v=unvec(x.vectorBase64,dim);if(!v)return null;
      return {id:x.id,sourceText:x.sourceText,text:typeof x.text==="string"?x.text:"",hash:typeof x.hash==="string"?x.hash:"",range:x.range||null,v:v};
    }).filter(Boolean);
    if(list.length)passages[k]=list;
  }
  for(const k in Q){const l=(Q[k]||[]).map(s=>unvec(s,dim)).filter(Boolean);if(l.length)ques[k]=l}
  VEC=(Object.keys(frags).length||Object.keys(passages).length||Object.keys(ques).length)?{dim:dim,frags:frags,passages:passages,ques:ques}:null;
  /* 문서가 갈렸으면 들고 있던 질의 벡터도 낡았다 — 차원이 바뀌었을 수도 있다 */
  if(!VEC)QVEC=null;
  paintByVectors();
}
/* 자를 통째로 버린다 — **버리고 나서 칠한다.** 그것이 이 함수가 있는 이유다 (#66-6). */
function dropVectors(){VEC=null;QVEC=null;paintByVectors()}
/* ★ 자가 바뀌었을 때 **다시 칠하는 자리 하나** (#46 · 셀프 실기 수리 · #66-6).
   ⚠ **화면을 다시 그리지는 않는다**: 손대는 것은 준비도 줄·왼쪽 칸·그림 칸 셋뿐이고
     편집기(`#ti`·`#bo`)는 안 건드린다(`paintHomeList` 머리글) — 벡터는 저장 뒤 비동기로
     오는데 그때 사용자는 다음 답변을 치고 있다.
   ⚠ 전 판은 성공 경로에만 있었다. 실패는 자만 지우고 화면은 낡은 값을 든 채였고, 그래서
     **색인이 실패한 뒤에도 준비도 줄과 점 색이 초록이었다** — 한 화면이 두 말을 하는 자리다. */
function paintByVectors(){
  if(mode==="live")return applyRank(true);
  paintHomeList();
  /* ★ 뜻 지도도 자가 바뀌면 같이 움직인다 (#67). **배치가 뜻에서 나오므로** 색인이 도착하면
     점이 앉는 자리부터 달라진다 — 안 고치면 지도는 「고른 원」인데 준비도 줄은 색을 낸다.
     ⚠ 오른쪽 판은 안 건드린다 — 위 셋과 같은 이유다(사람이 치는 중일 수 있다). */
  if(mode==="stack"&&stackView==="edit")canvasRefresh();
}
/* ★ 내용 그래프가 「이미 비슷한 조각이 있다」고 말하는 자리 (#32, ADR 0003 §3-①).
   Swift `ContentGraph` 가 저장 뒤에 **비동기로** 부른다 — 임베딩이 끝나야 알 수 있어서다.

   ⚠ **다시 그리지 않는다.** 이 알림이 도착할 때 사용자는 이미 다음 조각을 치고 있을 수 있고,
   `stackRender()` 는 편집기를 통째로 갈아끼워 **그 글자를 지운다**. 그래서 띠 하나만
   제자리에서 고쳐 쓴다 (`paintCur` 이 같은 이유로 같은 모양을 쓴다). */
function onIndexNotice(text){
  if(!noticeFits(text,mode,false))return;
  notice=text;paintNotice();
}
/* 띄워도 되는 자리인가 — **순수 함수라 `node --test` 가 잠근다.**
   ① 빈 글자는 빈 띠가 된다 ② 면접 중엔 띠 자리가 없다(화면이 통째로 다르다)
   ③ 채우기 제안이 떠 있으면 비킨다 — 그 띠에는 **눌러야 하는 버튼**이 붙어 있어서
      여기서 덮으면 그 버튼이 사라진다. 중복 알림은 다음 저장에 다시 온다. */
const noticeFits=(text,m,offer)=>!!(text&&m==="stack"&&!offer);
/* ══ 볼트가 말썽이다 (QA 블로커 F1) ═══════════════════════════════════════════
   ★ Swift `VaultIO` 가 **비동기로** 부른다. 저장·읽기가 주 스레드를 떠나면서 실패와 대기가
   갈 곳이 없어졌다 — 전엔 `stderr` 로만 나갔고, `실측 2026-08-30`: 문서 폴더 권한 창에
   걸린 앱이 **25분 동안 아무 말도 안 하고** 멈춰 있었다.
   ⚠ **통로를 안 늘렸다** — 이건 Swift→JS 이고 그쪽은 브리지 배열에 안 박혀 있다
     (`onIndexNotice`·`onQueryVector` 가 같은 길로 왔다).
   ⚠ **띠를 새로 짓지 않는다** — 알림 띠(`.wb`)를 그대로 쓴다. 다만 `#nb` 와 **다른 요소**다:
     같은 자리에 겹쳐 쓰면 「지금 채우기」 버튼(#35)이 사라진다(`noticeFits` 가 그래서 있다).
   ⚠ 빈 글자는 **띠를 걷는다** — 저장이 다시 성공하면 Swift 가 빈 글자를 보낸다. */
let vaultTrouble=null;
function onVaultTrouble(text){
  vaultTrouble=(text||"").trim()||null;
  paintVaultTrouble();
  const error=document.getElementById("foldererror");if(error)error.textContent=vaultTrouble||"";
}
/* 띠 하나만 제자리에서 짓고 고쳐 쓴다. ⚠ **다시 그리지 않는다** — 이 말이 도착할 때
   사용자는 조각을 치는 중일 수 있고 `stackRender()` 는 편집기를 통째로 갈아끼워 그 글자를
   지운다 (`paintNotice`·`paintReady`·`paintCur` 가 같은 이유로 같은 모양을 쓴다).
   ⚠ 띠가 앉을 자리가 없으면(면접·연습 중) **든 채로 있는다** — 쌓기로 돌아오는
     `stackRender()` 가 이 함수를 다시 불러 그때 그린다. 말이 사라지지는 않는다.
   ★ **버튼이 `post` 를 안 부른다.** 위 막대의 「설정」을 대신 누른다 — 그 손잡이는
     `stackRender` 안에 산다. 설정 화면이 여는 통로(`loadModels` 등)가 네트워크에 닿아서,
     면접 모드에서 닿을 수 있는 함수에 그 통로를 두면 판정선이 빨개진다. */
function paintVaultTrouble(){
  const right=document.getElementById("stacknotices");
  if(!right)return;
  let el=document.getElementById("vb");
  if(!vaultTrouble){if(el)el.remove();return}
  if(!el){
    el=document.createElement("div");el.className="wb";el.id="vb";
    const t=document.createElement("span");t.id="vbt";
    const row=document.createElement("div");row.className="row";row.style.marginTop="9px";
    const b=document.createElement("button");b.className="gbtn";b.textContent="폴더 다시 고르기";
    // 저장소 헤더와 같은 연결 동작을 사용한다. 면접 화면에는 이 헤더가 없다.
    b.onclick=()=>{const picker=document.getElementById("vaultmenu");if(picker)picker.click()};
    row.appendChild(b);el.appendChild(t);el.appendChild(row);
    right.insertBefore(el,right.firstChild);
  }
  const tx=document.getElementById("vbt");
  if(tx)tx.textContent=vaultTrouble;   /* esc 가 필요 없다 — textContent 는 태그를 안 판다 */
}

/* 안내만 제자리에서 갱신한다. 패널을 열거나 편집기를 다시 짓지 않는다. */
function paintNotice(){
  const right=document.getElementById("stacknotices");if(!right)return;
  let el=document.getElementById("nb");
  if(!notice){if(el)el.remove();return}
  if(!el){el=document.createElement("div");el.className="wb";el.id="nb";
    right.insertBefore(el,right.firstChild)}
  el.textContent=notice;   /* esc 가 필요 없다 — textContent 는 태그를 안 판다 */
}

const qtext=id=>{const q=DOC.questions.find(q=>q.id===id);return q?q.text:""};
const bg=s=>{const x=(s||"").replace(/\s+/g,"");const o=new Set();for(let i=0;i<x.length-1;i++)o.add(x.slice(i,i+2));return o};
function sim(a,b){const A=bg(a),B=bg(b);if(!A.size||!B.size)return 0;let n=0;for(const g of A)if(B.has(g))n++;return n/(A.size+B.size-n)}
/* ★ 글자 자 — **조각의 내용 하나**만 본다 (#53). 제목+본문이 축의 전부다.
   ⚠ **걷힌 것**(경계표 ④): `questionIds` 로 갈라져 그 조각이 답하는 질문의 글자
     (기준 질문 + 사람이 적은 말투 변형 = 옛 `qforms`)를 같이 보던 갈래.
     **frontmatter 의 `questions` 를 검색에 안 쓴다** — 그것이 이 티켓의 절반이다.
   ⚠ 그 갈래가 냈던 값(#23 `실측 2026-08-29`: 정답 평균 2.12위 → 1.00위)은 **사람이 칩을
     정확히 걸어 둔 볼트**에서 잰 값이다. 실전에서 그 자리를 채운 것은 전사 쓰레기였고
     (#52 채증 ④ — `fromInterview` 질문 5건 전부), 그 글자가 색인의 열쇠가 되면
     **질문 목록이 더러워질수록 검색이 나빠진다.** 그 되먹임을 끊는 것이 #53 이다.
   ⚠ 이 축은 옛 코드의 「칩이 없을 때의 축」 그대로다 — 한 줄도 안 바꿨다.
     신호등 경계(`RISK_G`/`RISK_A`)의 근거는 아래 그 상수 자리에 다시 적어 뒀다. */
const qscore=(p,q)=>sim(q,p.title+" "+p.body);

/* ══ 라이브 검색 — 뜻으로 찾는다 (#34, ADR 0003 §4) ═══════════════════════════════
   벡터는 **Swift 가** 만든다(CoreML, #31·#32). 코사인·순위·색은 **여기 남는다** —
   그래야 `node --test` 가 잠그고 브라우저 단독 동선(`cue.html`)이 산다
   (`tests/screen-load.mjs` 머리글이 그 자물쇠의 집이다). */
let INDEX_STATE="unknown",SPEECH_STATE="unknown",SPEECH_MESSAGE="";
let VAULT_ENTRIES=[],WORKSPACE_SELECTED_ID=null,WORKSPACE_SCOPE="";
let VAULT_FOLDERS=[],VAULT_TRASH=[],VAULT_LAST_OPERATION=null,VAULT_ACTION=null,VAULT_ACTION_SEQ=0,VAULT_MENU=null;
let VEC=null;    /* {dim, frags:{짧은조각:Float32Array}, passages:{조각id:[{v,sourceText,…}]}, ques:{질문id:[Float32Array,…]}} */
let QVEC=null;   /* {q:"<그 질의의 글자>", v:Float32Array} — 글자가 어긋나면 안 쓴다 */

/* base64(float32 little-endian) → Float32Array. `ContentIndexStore.encode(vector:)` 의 짝이다.
   길이가 안 맞으면 **0 벡터가 아니라 null** 을 돌려준다 — 0 벡터는 코사인 0 으로 조용히 섞인다. */
function unvec(s,dim){
  if(typeof s!=="string"||!(dim>0))return null;
  let raw;try{raw=atob(s)}catch(e){return null}
  if(raw.length!==dim*4)return null;
  const b=new Uint8Array(raw.length);
  for(let i=0;i<raw.length;i++)b[i]=raw.charCodeAt(i);
  return new Float32Array(b.buffer);
}
/* 진짜 코사인이다 — 길이로 나눈다. Swift 는 정규화된 벡터를 주지만 **그걸 믿는 자리를 안 만든다**:
   여기서 나누면 이 함수만 보고도 맞는지 알 수 있고, 384 곱셈은 어차피 공짜다. */
function cosv(a,b){
  if(!a||!b||a.length!==b.length||!a.length)return null;
  let d=0,x=0,y=0;
  for(let i=0;i<a.length;i++){d+=a[i]*b[i];x+=a[i]*a[i];y+=b[i]*b[i]}
  if(!(x>0)||!(y>0))return null;
  const c=d/Math.sqrt(x*y);
  return c===c?c:null;                 /* NaN 은 비교에서 조용히 진다 — 여기서 잡는다 */
}

/* ★ **내용 직접**의 초록선 — `실측 2026-08-30`(#34). 감으로 박은 값이 아니다.
   말뭉치 = `tests/fixtures/screen_vectors.json` (#23 프로브 말뭉치 그대로: 조각 6 · 질문 10 ·
   정답 질의 8 · 저장소 밖 질의 6). 뜬 자 = `scripts/make_screen_vectors_fixture.py`.
   같은 말뭉치 실측: 내용 직접(query: ↔ passage:) 정답 0.447~0.564 · 저장소 밖 최고 0.5128.

   선을 고른 조리법:
     max( 저장소 밖 질의의 최고점 , 같은 볼트 오답의 90분위 ) + 0.001
     ① 저장소 밖 최고 = **헛초록 0** 을 지키는 자리. #23 이 정한 판정선이다.
     ② 오답 90분위 = 같은 볼트의 **틀린 조각**이 초록으로 새지 않는 자리.
        `ContentIndexer.linkFloor` 가 이웃 문턱을 고른 조리법과 같다 — 음성 표본 90분위.
        ⚠ 이 ②가 없으면 인도메인에서 통째로 초록이 된다. 실측: 「잘 안 풀렸던 프로젝트」에
          **틀린 조각 셋**이 초록으로 떴고 정답은 4위로 밀렸다.
     ③ +0.001 = fp16 CoreML 대 fp32 파이썬의 실측 코사인 편차(1.38e-4)를 덮는 여유.
        그 수의 집은 `tests/fixtures/embedding_reference.json` 의 `tolerance`.
   실측 대입:  max(0.5128, 0.5405) + 0.001
   ★ **눈금이 하나라 나누는 일이 남았다.** 갈래가 둘이던 때는 「자기 선으로 나눈 뒤 max」가
     서로 다른 눈금을 붙이는 장치였는데, 이제 갈래가 하나다. 그래도 나눈다 — **1.0 이 곧
     초록선**이라는 규약을 `eris`·준비도·연습이 전부 물고 있고, 그 규약이 곧 신호등이다.
   ⚠ 이 값은 **이 모델·이 프리픽스 규약의 값**이다. 둘 중 하나가 바뀌면 같이 다시 재라 —
     `tests/screen-vectors.test.mjs` 가 fixture 에서 분포를 **다시 재서** 빨개진다.

   ⚠ **걷힌 것**(#53, 경계표 ①): `SIM_G_MEDIATED`(0.6822)와 그것이 재던 **개념 매개 갈래**
     — 질의를 그 조각이 답하는 **질문**에 대고 재서(query: ↔ query:) 조각을 건너짚던 길.
     걷은 이유는 성능이 아니라 **열쇠의 성질**이다: 그 갈래가 보는 글자가 `questions` 라
     수확 질문(전사 원문)이 목록에 앉는 순간 그것이 색인의 열쇠가 됐다(#52 채증 ④).
     ★ **값이 있었다는 것은 숨기지 않는다** — 같은 말뭉치에서 매개를 걷으면 정답 평균
       1.50위 → 2.00위, 정답 초록 6/8 → 3/8 로 내려간다(`실측 2026-08-31`, #53).
       그 수는 **칩이 정확한 볼트**의 수고, 실전 볼트는 그 모양이 아니었다는 것이 이 결정이다. */
const SIM_G_DIRECT=0.5415;
/* 주황선 — 초록선의 92.5%. `실측 2026-08-30`: 저장소 밖 질의 × 조각 36쌍의 정규화 점수
   90분위가 0.9155(중앙 0.85)였다. 그 위를 주황으로 본다 — ①과 같은 90분위 조리법.
   ⚠ e5 는 **관계없는 한국어 문장에도 0.55쯤**을 준다(`ContentIndexer` 주석과 같은 사실).
     그래서 이 눈금엔 「0 에 가까운 빨강」이 없다. 빨강은 「선의 92.5% 밑」이라는 뜻이다.
   ⚠ **「노랑 과다」는 아직 안 고쳤다** (#53 이 다음으로 미룬 것). 매개를 걷으니 정답의
     주황이 2/8 → 3/8 로 늘었다 — 재보정은 실전 전사 질의 분포로 해야 하고 그 표본이 아직 없다. */
const SIM_A=0.925;

/* 조각 하나의 라이브 점수 = **내용 직접 하나**. 초록선으로 나눠 1.0 = 초록선 눈금으로 낸다.
   ⚠ **이 레포의 「내용 직접」 자는 이 함수 하나다** (#53). 연습(`practiceReadiness`)의
     「준비된 답변이 없다」(`unprepared`)가 `bestDirect` 를 거쳐 **같은 이 함수**로 온다 —
     매개 갈래가 있던 때는 라이브만 두 갈래라 자가 둘이었고, 그것이 「한 화면은 초록이라
     하고 다른 화면은 없다고 한다」(#49)를 만든 자리다.
   벡터가 없으면 null. 그때 부르는 쪽이 물러선다. */
function passageScore(p,qv,vec){
  if(!p||!qv||!vec)return null;
  let best=null;
  ((((vec||{}).passages||{})[p.id])||[]).forEach(x=>{
    const score=cosv(qv,x.v);
    if(score!==null&&(!best||score>best.score||(score===best.score&&x.id<best.passage.id)))best={score:score,passage:x};
  });
  if(best)return best;
  const score=cosv(qv,((vec||{}).frags||{})[p.id]);
  return score===null?null:{score:score,passage:null};
}
function escore(p,qv,vec){
  const hit=passageScore(p,qv,vec);
  return hit===null?null:hit.score/SIM_G_DIRECT;
}
/* 정규화된 눈금의 신호등. 1.0 = 초록선이라 견줄 상수가 하나 준다. */
const eris=n=>n>=1?"g":(n>=SIM_A?"a":"r");

/* 그 질문의 질의 벡터. 없으면 `null` — 이 갈림을 부르는 쪽마다 다르게 읽어서 뽑아 뒀다
   (준비도는 **안 세고**, 연습은 **예전 판정으로 물러선다**). */
const qvecOf=(qid,vec)=>((((vec||{}).ques||{})[qid])||[])[0]||null;
/* ★ 그 질문에 **내용으로** 가장 가까운 조각의 정규화 점수 — 잴 조각이 하나도 없으면 `null`.
   ⚠ **이 레포의 「내용 직접」 자는 `escore` 하나다.** 연습(`practiceReadiness`)과
     「준비된 답변이 없다」(`unprepared`)가 이 함수를 거쳐 **그 함수**를 부른다 — 두 벌이면
     한 화면은 초록이라 하고 다른 화면은 없다고 하는, 바로 그 갈림이 다시 난다(#49).
   ★ **#53 이 계산을 한 자리로 합쳤다.** 매개 갈래가 살아 있던 때 이 함수는 `escore` 를
     못 불렀다(그 함수가 칩까지 봐서 거울이 됐다) — 그래서 코사인·나누기를 여기 한 벌 더
     들고 있었다. 이제 `escore` 가 곧 내용 직접이라 그 두 벌이 한 벌이 됐다. */
function bestDirect(qv,fragments,vec){
  let best=null;
  (fragments||[]).forEach(p=>{
    if(isSeed(p))return;
    const n=escore(p,qv,vec);
    if(n===null)return;
    if(best===null||n>best)best=n;
  });
  return best;
}
/* ★ **선언된 갈림** (#34). 어느 자로 도는지는 이 함수 하나가 정한다 — 순수 함수라 잠긴다.
   "뜻"  = 임베딩. Swift 가 **그 질의의** 벡터를 실어 보냈을 때만이다. 글자가 어긋나면 안 쓴다 —
           한 어절 전 질의의 벡터로 매기면 화면이 조용히 틀린 답을 가리킨다.
   "글자" = bigram(`qscore`). 브라우저 단독(`cue.html`) · 모델 없음 · 벡터가 아직 안 온 사이가
           전부 여기로 온다. 물러서는 것이지 꺼지는 것이 아니다. */
const scorer=(q,qvec,vec)=>(vec&&qvec&&qvec.v&&qvec.q===q)?"뜻":"글자";

/* 줄 세우기. **점수와 색을 같이** 돌려준다 — 둘이 같은 눈금에서 나와야 위 카드가 아래 카드보다
   덜 초록인 일이 안 생긴다. `s` 의 눈금은 `how` 에 달렸다(뜻 = 1.0 이 초록선 · 글자 = bigram).
   ⚠ 인자 둘은 **시험이 갈아끼우라고** 있다. 안 주면 화면의 현재 상태를 쓴다.
   ⚠ 넷째(`scope`)는 다르다 — 시험용이 아니라 **면접이 쓰는 범위**다(아래 필터 주석). */
const rank=(q,qvec,vec,scope)=>{
  if(qvec===undefined)qvec=QVEC;
  if(vec===undefined)vec=VEC;
  if(!q.trim())return[];
  const how=scorer(q,qvec,vec);
  /* ★ 씨앗은 **여기서 빠진다** (QA 블로커 F2). 라이브·연습이 둘 다 이 함수를 지나서
     이 한 줄이 두 곳을 같이 덮는다 — 두 곳에 각각 거르면 한쪽이 조용히 낡는다.
     ⚠ **`map` 뒤에 거른다.** `i` 는 `DOC.fragments` 의 자리이고 `applyRank`·`ORD.list`·
       `paintRecs` 가 그 수로 조각을 다시 찾는다 — 먼저 거르면 카드가 딴 조각을 가리킨다.
     ★ **범위(`scope`)도 같은 자리에서 좁힌다** (#73 Q20). 면접이 항성 하나를 고르면 후보가
       그 폴더 안으로 준다 — **자·눈금·색은 그대로고 집합만 다르다.**
       `null`/`undefined` = 갤럭시(전부) · 빈 집합 = 아무것도 없다(전부가 아니다). */
  return DOC.fragments.map((p,i)=>{
    if(how==="뜻"){
      const hit=passageScore(p,qvec.v,vec),n=hit===null?null:hit.score/SIM_G_DIRECT;
      /* 방금 추가돼 아직 색인 안 된 조각은 0점·빨강이다. 다음 저장에서 벡터가 온다 —
         bigram 점수를 섞어 넣지 않는다. 눈금이 달라서 순서가 거짓말이 된다. */
      return {p,i,s:n===null?0:n,c:n===null?"r":eris(n),how:"뜻",passage:hit&&hit.passage};
    }
    const s=qscore(p,q);
    return {p,i,s:s,c:risk(s),how:"글자"};
  }).filter(x=>!isSeed(x.p)&&(scope==null||scope.has(x.p.id))).sort((a,b)=>b.s-a.s);
};
/* ★ 신호등 경계 — `실측 2026-08-28`(#20). 감으로 박은 값이 아니었다:
     정답 조각 0.154~0.611 · 오답 90분위 0.038 · 저장소 밖 전부 0.000
   → 초록은 오답 90분위를 크게 넘는 자리, 빨강은 저장소 밖이 앉는 자리(0)에 뒀다.

   ⚠ **그 근거는 #53 이 축을 좁히면서 낡았다.** 저 정답 0.154~0.611 은 `qscore` 가
     **칩의 질문 글자**를 같이 보던 때의 수다. 지금은 제목+본문 하나뿐이라, 같은 말뭉치
     (`tests/fixtures/screen_vectors.json`)를 이 함수로 다시 돌리면(`실측 2026-08-31`, #53):
         정답 조각      0.0000 ~ 0.0120  (8건 중 **0건**이 0.04 이상)
         오답 조각      중앙 0 · 90분위 0.0116 · 최대 0.0244
         저장소 밖      중앙 0 · 90분위 0.0125 · 최대 0.0137
     세 무리가 **통째로 겹친다.** 즉 이 눈금은 이제 **색을 못 낸다 — 전부 빨강이다.**
     순서는 아직 낸다(정답 top-1 3/8 · 화면 안 5/8). 그것이 폴백에 남은 전부다.
   ⚠ **그래서 값을 안 옮겼다.** 옮길 자리가 없다 — 겹치는 분포에는 가르는 선이 없고,
     선을 낮추면 오답이 같이 초록이 된다. 이 자를 되살리려면 자를 바꿔야지 선을 바꿀 일이
     아니다. #53 이 「문턱 재보정」을 다음으로 미룬 자리가 여기다.
   ⚠ **이건 폴백 쪽 눈금이다** (#34). 벡터가 있으면 화면은 `eris`/`SIM_G_DIRECT` 로 돈다.
     둘은 **다른 눈금이고 서로 못 견준다** — `rank()` 가 돌려주는 `how` 가 어느 쪽인지 든다. */
const RISK_G=0.15, RISK_A=0.04;
const risk=s=>s>=RISK_G?"g":(s>=RISK_A?"a":"r");
/* ⚠ **말투 변형을 적는 칸은 걷었다** (#34). 사람이 질문마다 세 가지 말투를 손으로 적어 넣던
   자리다(#23 ②). 걷은 이유: 그 칸이 하던 일 — 「면접관이 다르게 물어도 걸리게」 — 을
   이제 임베딩이 한다.
   ⚠ **#53 이 그 다음 칸까지 걷었다.** 이미 적어 둔 변형도 이제 **어느 자에도 안 들어간다** —
     글자 자는 조각 내용만 보고(`qscore`), 뜻 자는 매개 갈래가 없어 질문 벡터를 안 짚는다.
     `qvecOf` 가 `vec.ques[qid][0]`(기준 질문 하나)만 꺼내는 것이 그 사실이다.
   ⚠ **그래도 스키마의 `variants` 는 안 지운다.** 사람이 적어 둔 글자를 우리가 지우지 않고,
     md 볼트가 옵시디언에서 그대로 열려야 한다(경계표 「남는다」 4행). 안 읽을 뿐이다.
     → 그래서 `Question.variants` 를 `CueDocument` 에서 빼면 안 된다. */

/* ══ 걷힌 것 — 개념 제안 (#33) · 던져 넣기 칩 (#14→#29→#33) ═══════════════════════
   ★ **#53 이 통째로 걷었다** (경계표 ②③). 여기 살던 것: 조각 초안을 예상 질문 열에 대고
     상위 셋을 띄워 사람이 눌러 칩을 켜던 길(`suggestChips`·`SUGGEST_N/MIN/WAIT`·
     `suggestFits`·`draftText`·`askSuggest`·`recomputeSuggest`·`paintSuggest`)과,
     자소서 문항을 기존 질문에 붙이던 길(`chipFor`·`chipOn`·`CHIP_T`·`CHIP_ON`).

   ★ **왜 성능이 아니라 성질로 걷었나.** 저 길들의 실측은 살아 있다 —
     조각→질문 top-3 8/12(우연 3.6) · 문항→질문 1위 12/18. 그런데 그 셋이 켠 **칩이
     매칭의 열쇠**였고, 열쇠가 되는 순간 **질문 목록의 더러움이 검색으로 샜다**
     (#52 채증 ④: `fromInterview` 질문 5건이 전부 전사 쓰레기). #53 은 열쇠를 내용 하나로
     옮겼고, 그러면 「어느 질문에 붙일까」를 기계가 셋 띄워 물을 이유가 없어진다 —
     붙여도 순위가 안 바뀐다.

   ⚠ **`questionIds` 는 안 죽었다. 뜻이 바뀌었다** — 열쇠에서 **장부**로. 이제 그 값이 앉는
     자리는 셋뿐이고 전부 사람이 짚은 자리다: 채우기 흐름(#35) · 구멍 목록 클릭 ·
     받기 승인(문항 = 그 답이 답하는 물음). 읽는 쪽은 `gaps`·`unprepared`·
     `practiceScore`·`freshQids` — 전부 **준비도와 순서**다. 검색은 이제 안 읽는다.
     ⚠ **화면에 글자로 적던 자리는 v3 이 걷었다**(`itemMeta`·`paintLinked`, #61 A) —
       쌓기 홈에서 장부는 이제 안 보인다. 보이는 것은 뜻 유사도 하나다.
   ⚠ **말뭉치와 그 자물쇠는 안 지웠다** — `tests/fixtures/chip_suggest.json` 과
     `tests/chip-suggest.test.mjs`. 저 수들이 이 결정의 「다시 열 조건」이라, 수가 달라지면
     빨개져야 한다. 그 파일 머리글이 지금 무엇을 드는지 든다. */

/* ── 초안 벡터를 얻어오는 길 (#33 이 냈고 #36·#53 뒤에도 산다) ─────────────────────
   ★ **JS→Swift 통로 `embedDraft`.** 늘린 이유는 하나였다: **아직 저장 안 된 글자에는
   벡터가 없다.** 화면이 든 벡터는 `receiveVectors` 가 실어 온 **저장된** 조각·질문의
   것뿐이라(#34), 지금 치고 있는 글자는 화면 혼자서는 영영 못 잰다. 임베딩은 CoreML 이라
   JS 가 못 한다.
   ⚠ 대신 **코사인·순위는 안 넘겼다** — Swift 는 벡터만 만들어 돌려준다(ADR 0003 §4 의 갈림
     그대로). `embedQuery`/`onQueryVector`(#34)와 **같은 모양**이고, 다른 것은 부르는 쪽이
     Swift 가 아니라 화면이라는 것뿐이다.
   ⚠ **#53 뒤에 이 통로를 쓰는 곳은 연습의 답 한 칸(`answer`)뿐이다.** 편집기 제안(`edit`)과
     던져 넣기 후보(`c0`·`c1`…)가 같이 걷혔다. **통로는 안 걷는다** — 연습 채점이 그것 하나로
     뜻 자를 얻는다(`gradePractice` 머리글).
   ⚠ 이 통로가 없으면(브라우저 단독) `DRAFT` 가 영영 비고 연습은 글자 자로 돈다 — 선언된 갈림이다. */

/* 초안 벡터가 앉는 자리. **칸마다 따로** — 지금 사는 칸은 연습의 `answer` 하나다.
   `{t:"<그 벡터가 나온 글자>", v:Float32Array}` — 글자를 같이 드는 이유는 `QVEC` 와 같다. */
const DRAFT={};
/* ★ 초안 벡터가 도착하는 자리 (#33). Swift `ContentGraph` 가 **비동기로** 부른다.
   ⚠ `onQueryVector` 와 같은 규율 — **벡터와 그 벡터가 나온 글자를 같이 든다.**
   ⚠ **받는 칸이 하나로 줄었다** (#53). `edit`(편집기 제안)·`c*`(던져 넣기 후보 칩)가
     같이 걷혀서, 지금 이 함수가 하는 일은 연습의 답 벡터를 앉히는 것뿐이다.
     그래도 `DRAFT[d.slot]` 은 **칸 이름 그대로** 앉힌다 — 칸이 다시 늘 때 여기가 안 갈리게. */
function onDraftVector(json){
  if(!VEC)return;                       /* 질문 벡터가 없으면 초안 벡터만으론 못 잰다 */
  let d;try{d=JSON.parse(json)}catch(e){return}
  if(!d||typeof d.slot!=="string"||typeof d.text!=="string")return;
  const v=unvec(d.v,VEC.dim);
  if(!v)return;
  DRAFT[d.slot]={t:d.text,v:v};
  /* ★ 연습의 답 벡터가 도착했다 (#36). 글자 자로 이미 칠해둔 색을 **뜻 자로 갈아끼운다.**
     ⚠ 다시 그리지 않는다 — 사람이 답을 치고 있을 수 있다(`paintPractice` 머리글). */
  if(d.slot==="answer"&&mode==="practice"&&prac&&!prac.done){gradePractice();paintPractice()}
  /* ★ 뜻 지도의 자유 질문 벡터가 도착했다 (#67). **통로를 안 늘렸다** — 같은 `embedDraft`
     의 칸 하나(`canvas`)일 뿐이고, `kind:"query"` 라 라이브 검색과 **같은 축**이다.
     ⚠ 여기서도 다시 그리지 않는다 — 손대는 것은 지도 쪽뿐이다(`canvasVectorArrived`). */
  if(d.slot==="canvas")canvasVectorArrived();
}

/* ── 던져 넣기 (#14 · 스펙 #13) — 자소서를 문항 단위로 가른다. **LLM 호출 0** ──
   ★ 기계가 하는 것은 **자르기와 제안까지**다 (라운드 10 Q3).
   **본문을 만들거나 고치는 코드 경로가 여기 없다** — 생기면 그게 결함이다.
   ⚠ 예외 하나(#52): `unwrapHardLines` 가 감긴 줄을 이을 때 넣는 공백. 글자는 안 만들고
     시각 줄바꿈을 공백으로 바꿀 뿐이다 — 그 함수 머리글이 대가까지 든다. */
/* 문항 줄의 표기 변형을 한 줄에 모은다 — 「1.」 「1)」 「(1)」 「[1]」 「문항 1.」 「Q1.」 「1번.」
   ⚠ `\d{1,2}` 로 좁힌 것은 본문의 연도(`2024. 3월에`)가 문항으로 오인되던 자리다. 자물쇠가 든다.
   ⚠ 구분자 뒤의 `(?!\d)` 는 **소수**가 문항으로 오인되던 자리다 — PDF 추출문이 감긴 줄을 그대로
     넘겨 「1.8%에서 0.3%로」가 줄머리에 왔고, 3번 문항의 답이 거기서 두 동강 났다(#52 채증).
     자물쇠가 든다. ⚠ 룩어헤드는 `[ \t]*` **앞**이다 — 뒤로 옮기면 「1. 3년 후 목표」(점+공백+숫자)
     라는 정당한 문항까지 같이 죽는다. */
const QHEAD=/^[ \t]*(?:문항[ \t]*|Q[ \t]*)?[\[(]?[ \t]*(\d{1,2})[ \t]*(?:번)?[ \t]*[\].)](?!\d)[ \t]*(.+)$/;
function parseCoverLetter(text){
  const raw=text||"";
  if(!raw.trim())return{items:[],error:"붙여넣은 게 없어요 — 자소서 전문을 넣어 주세요"};
  const lines=raw.split(/\r?\n/),heads=[];
  lines.forEach((ln,i)=>{const m=ln.match(QHEAD);if(m&&m[2].trim())heads.push({i:i,q:m[2].trim()})});
  if(!heads.length)return{items:[],error:"문항을 못 찾았어요 — 「1.」 「1)」 「문항 1.」 처럼 번호 붙은 줄에서 갈라요. 번호를 넣거나 한 장씩 손으로 넣어 주세요"};
  const items=[];
  /* ★ **첫 문항 앞의 머리글도 낸다** (#66-2, `실측 2026-09-01`: 머리글 있는 자소서 152자→94자).
     `splitHeadings` 가 같은 자리에서 선언·준수하는 계약 — *글자를 흘리지 않는 것이 자르기의
     계약이다* — 을 문항 경로만 안 지키고 있었다. 모양도 그쪽의 `pre` 그대로다: **문항이 아닌
     별도 항목**(`q:""`)이지 첫 문항의 답에 붙이는 것이 아니다. 붙이면 표지·지원자 정보가
     1번 답의 본문이 되어 **「문항 경계는 사람이 그은 것」**(`mergeShortSections` ⚠)이 깨진다. */
  const pre=lines.slice(0,heads[0].i).join("\n").trim();
  if(pre)items.push({q:"",body:pre});
  heads.forEach((h,k)=>{
    const end=k+1<heads.length?heads[k+1].i:lines.length;
    /* ★ 안쪽은 안 건드린다. 양 끝 공백만 다듬는다 — 본문은 **받은 글**과 글자 단위로 같아야
       한다 (받은 글 = `unwrapHardLines` 를 지난 것. 감긴 줄의 공백 복원은 저 입구 한 곳뿐이다) */
    const body=lines.slice(h.i+1,end).join("\n").trim();
    if(body)items.push({q:h.q,body:body});
  });
  /* ⚠ **머리글 하나만으로는 성공이 아니다.** 답이 한 줄도 없으면 문항 경로는 실패고, 그때
     이 글은 다른 길(문단 자르기)로 가야 한다 — 머리글만 든 항목 하나를 성공이라 내면
     그 갈림이 막힌다. 그래서 세는 것은 **문항 항목**이다. */
  if(!items.some(it=>it.q))return{items:[],error:"문항은 찾았는데 답이 비어 있어요 — 문항 줄 아래에 답이 있어야 해요"};
  return{items:items,error:null};
}
/* 후보의 기본 제목 = 답의 **첫 문장**. 원문에서 잘라올 뿐 만들지 않는다. 사용자가 고친다. */
const candTitle=b=>(((b||"").trim().split(/(?<=다\.|요\.)/)[0])||"").trim().slice(0,34);

/* ── 받기 (#40) — **문항 번호가 없는 글도 받는다** ────────────────────────────
   ★ 파서를 두 개 만들지 않는다. 번호가 있으면 위 `parseCoverLetter` 그대로고, 없을 때만
     빈 줄(문단)을 경계로 삼아 덩이로 붙인다. 기계가 하는 것은 여전히 **자르기까지**다 —
     여기에 본문을 만들거나 고치는 코드가 없다(이야기 단위를 고르는 것은 Swift 쪽 모델이고,
     그것도 못 오면 `machineDraft` 로 물러선다). 생기면 그게 결함이다.

   ★ **2판에서 자르기의 역할이 줄었다** (#40, 박선호 2026-08-30 「못 쓸 수준」).
     1판은 기계가 이야기 경계를 정하고 모델이 그 덩이를 요약했다 — 문항 번호 없는 글에서
     빈 줄 1,200자로 자르니 **이야기 한가운데가 잘렸고**, 요약은 잘린 것을 요약했다.
     지금 자르기가 내는 것은 **모델이 볼 덩이**이지 조각 경계가 아니다. 무엇이 한 이야기인가는
     모델이 판정한다(`FragmentDrafter`). 그래서 덩이는 **글의 구조를 따라야** 한다.

   ⚠ 상한은 **덩이 하나가 모델의 입력에 들어갈 크기**다. `FragmentDrafter.inputLimit`(1,600)보다
     작아야 그쪽의 자름이 우리 덩이에는 안 걸린다. 1,400 은 거기서 한 뼘 물러선 값이고,
     `실측`이 아니라 선언한 기본값이다. 틀렸을 때의 대가는 이야기가 두 덩이에 걸치는 것이고,
     그러면 모델이 양쪽에서 반쪽씩 뽑는다 — 사람이 저장 뒤 편집기에서 합친다. */
const CHUNK_MAX=1400;
/* ★ 마크다운 헤딩 줄 — `#`~`####` 까지 (#40 2판). **여는 `#` 뒤에 공백이 있어야 한다.**
   ⚠ **짧은 단독 소제목 줄(`경력 사항` 같은 것)은 안 센다.** 그건 과욕이다 — 본문 첫 줄이
     소제목으로 오해되면 이야기가 통째로 쪼개져 2판이 고치려던 사고가 그대로 돌아온다.
     헤딩만 본다. 헤딩이 없는 글은 예전 길(문항 → 문단)로 그대로 간다. */
const MDHEAD=/^ {0,3}(#{1,4})[ \t]+(.+?)[ \t]*#*$/;
/* 헤딩을 경계로 구획을 낸다 — `[{h,body}]`. 헤딩이 하나도 없으면 **빈 배열**이다(호출자가 물러선다).
   ⚠ 첫 헤딩 앞의 머리글도 버리지 않는다 — 글자를 흘리지 않는 것이 자르기의 계약이다.
   ⚠ 몸이 빈 헤딩(바로 다음 줄이 또 헤딩)은 안 낸다. 큰 제목 아래 작은 제목이 바로 오는
     흔한 모양인데, 그때 맥락은 **작은 제목**이 든다. */
function splitHeadings(text){
  const lines=(text||"").split(/\r?\n/),heads=[];
  lines.forEach((ln,i)=>{const m=ln.match(MDHEAD);if(m&&m[2].trim())heads.push({i:i,h:m[2].trim()})});
  if(!heads.length)return[];
  const out=[],pre=lines.slice(0,heads[0].i).join("\n").trim();
  if(pre)out.push({h:"",body:pre});
  heads.forEach((hd,k)=>{
    const end=k+1<heads.length?heads[k+1].i:lines.length;
    const body=lines.slice(hd.i+1,end).join("\n").trim();
    if(body)out.push({h:hd.h,body:body});
  });
  return out;
}
/* 헤딩 글자를 그 덩이의 **맥락으로 본문 앞에** 붙인다. 모델은 덩이 하나만 보므로, 안 붙이면
   「이 글이 무엇에 대한 답인지」가 통째로 사라진다. ⚠ 만드는 것이 아니라 **원문의 줄을 옮기는 것**이다. */
const withHead=(h,b)=>h?h+"\n\n"+b:b;
/* 문장 경계로 다시 가른다 — 문단 하나가 이미 상한을 넘었을 때만 불린다.
   부호가 하나도 없으면 마지막엔 글자로 자른다. **글자를 흘리지 않는 것**이 이 함수의 계약이다. */
function chunkLong(p,cap){
  const out=[];let cur="";
  const push=s=>{if(s)out.push(s)};
  (p.split(/(?<=[.!?。？！])\s*/).filter(Boolean)).forEach(s=>{
    if(s.length>cap){
      push(cur);cur="";
      for(let i=0;i<s.length;i+=cap)push(s.slice(i,i+cap));
      return;
    }
    if(!cur){cur=s;return}
    if(cur.length+s.length<=cap){cur+=s;return}
    push(cur);cur=s;
  });
  push(cur);
  return out;
}
/* 빈 줄을 경계로 문단을 모아 **상한 이하의 덩이**로 만든다. 순수 함수 — `node --test` 가 잠근다. */
function chunkParagraphs(text,max){
  const cap=max||CHUNK_MAX;
  const paras=(text||"").split(/\r?\n[ \t]*\r?\n/).map(s=>s.trim()).filter(Boolean);
  const out=[];let cur="";
  paras.forEach(p=>{
    (p.length>cap?chunkLong(p,cap):[p]).forEach(piece=>{
      if(!cur){cur=piece;return}
      if(cur.length+2+piece.length<=cap){cur=cur+"\n\n"+piece;return}
      out.push(cur);cur=piece;
    });
  });
  if(cur)out.push(cur);
  return out;
}
/* ★ **최소 창** — 이보다 짧은 헤딩 구획은 옆 구획과 붙여서 모델에게 준다 (#40 2판 조정).
   `실측 2026-08-30` 셀프 실기, 창업대회 지원서(헤딩 넷): 구획 창이 **110·111·123·78자**로 나왔고
   `FragmentDrafter.storyFloor`(120)에 셋이 걸려 **진짜 이야기 둘(해커톤 2위·인터뷰로 병목 발견)이
   통째로 버려졌다.** 살아남은 123자 창도 창이 좁아 문장 단위로 조각났다.
   ⚠ 고칠 자리가 왜 여기인가: 바닥(`storyFloor`)을 낮추면 표지·목차가 도로 들어온다 — 그 바닥은
     길이로 가르는 자리라 옳다. **틀린 것은 바닥이 아니라 창이 너무 좁게 잘린 것**이다.
   ⚠ 값의 근거 = 위 실측의 **안정 구간**이다. 이 픽스처에서 답이 안 변하는 문턱대가 `125~223` 이고
     (그 밑이면 78자 꼬리만 붙고, 그 위면 넷이 한 창으로 뭉쳐 사건 셋이 한 창에 들어간다),
     200 은 그 구간 안에서 양쪽에 여유를 둔 값이다. `storyFloor` 의 1.7배 — 붙인 뒤에 바닥을
     **간신히** 넘는 것이 아니라 사건 하나가 맥락과 같이 들어갈 만큼 넘게 한다.
   ⚠ **선언한 값이지 실측이 아니다.** 틀렸을 때의 대가는 한 창에 사건이 둘 이상 들어가 모델이
     그중 하나를 흘리는 것이고, 원문은 카드에 그대로 남아 있다. */
const SECTION_MIN=200;
/* 이 구획에 문항 번호가 있나. **있으면 경계를 안 건드린다** — 문항 경계는 사람이 그은 것이다. */
const hasQuestions=s=>parseCoverLetter(s.body).items.length>0;
/* ★ 짧은 헤딩 구획들을 **인접한 것끼리 붙여** 창을 키운다 — 순수 함수, `node --test` 가 잠근다.
   붙일 때 **헤딩 글자는 각 부분 앞에 그대로 남긴다**(`withHead`) — 그래야 모델이 한 창 안에서도
   「여기부터 다른 이야기」를 본다. 만드는 것이 아니라 원문의 줄을 옮기는 것이다.
   ⚠ **문항 구획은 절대 안 붙인다** — 앞뒤 어느 쪽으로도. 문항 경계가 흐려지면 한 문항의 답이
     옆 문항과 섞여 저장된다.
   ⚠ 붙여도 `CHUNK_MAX` 를 안 넘는다 — 넘기면 `chunkParagraphs` 가 도로 잘라 헛일이 된다.
   ⚠ 꼬리 하나가 짧게 남으면 **앞으로 접는다.** 앞으로 접을 곳이 없는 외톨이는 그대로 두고,
     그 뒤는 `storyFloor` 가 판정한다(그 자리는 안 바꿨다).
   ★ **몇 편을 붙였는지 센다**(`n`). 그 수가 브리지를 타고 모델에게 간다 — 붙인 창에서만
     「대개 한 장」을 풀어야 하는데, 그것을 아는 것은 **여기뿐**이다(`FragmentDrafter.draft` 의
     `parts`). 글자를 모델 쪽에서 다시 뜯어 세면 자가 두 벌이 되고 곧 갈린다.
   - Returns: `[{h,body,merged,hs,n}]` · `hs` = 덮는 헤딩 이름들(화면 표시용) · `n` = 붙인 편 수 */
function mergeShortSections(secs,min){
  const lim=min||SECTION_MIN,out=[];
  const win=s=>withHead(s.h,s.body).length;
  const fold=(a,b)=>{a.body=withHead(a.h,a.body)+"\n\n"+withHead(b.h,b.body);
                     a.h="";a.merged=true;a.hs=a.hs.concat(b.hs);a.n=a.n+b.n};
  (secs||[]).forEach(s=>{
    const cur={h:s.h,body:s.body,merged:false,q:hasQuestions(s),hs:s.h?[s.h]:[],n:1};
    const last=out.length?out[out.length-1]:null;
    if(last&&!last.q&&!cur.q&&win(last)<lim&&win(last)+2+win(cur)<=CHUNK_MAX){fold(last,cur);return}
    out.push(cur);
  });
  if(out.length>1){
    const t=out[out.length-1],p=out[out.length-2];
    if(!t.q&&!p.q&&win(t)<lim&&win(p)+2+win(t)<=CHUNK_MAX){fold(p,t);out.pop()}
  }
  return out;
}
/* 구획 하나(`{h,body}`) → 덩이들. **구획 안에서도 순서는 같다** — 문항 번호가 있으면 문항이,
   없으면 문단이다. 헤딩을 이겨서가 아니라 **헤딩 아래에서 다시 가르는 것**이다:
   `# 지원서` 아래에 `1. 지원동기`가 오는 글에서 헤딩만 보면 문항 다섯이 한 덩이에 뭉친다.
   ⚠ 문단 상한에서 헤딩 길이를 뺀다 — 붙인 뒤에 상한을 넘으면 `CHUNK_MAX` 가 거짓말이 된다.
   ⚠ 붙인 구획(`merged`)은 `h` 가 비어 있다 — 헤딩이 **이미 본문 안에** 있기 때문이다.
     그래도 `kind` 는 `"head"` 다(헤딩에서 온 덩이가 맞다), 그리고 화면에 세울 이름은 `hs` 가 든다.
   ★ **`parts` 가 창마다 붙는다** — 이 창이 몇 편을 붙인 것인가. 문항 창은 언제나 1 이다(안 붙는다).
   ⚠ 붙인 구획이 그래도 상한을 넘어 **다시 갈리면 `parts` 를 1 로 떨어뜨린다.** 갈린 조각마다
     몇 편이 들었는지는 여기서 알 수 없고, 모르는 채로 큰 수를 보내면 모델이 없는 편을 찾는다.
     ⚠ 지금 배선에서는 안 일어난다(`mergeShortSections` 가 `CHUNK_MAX` 를 안 넘긴다) — 그래도
     둔다: 여기서 조용히 틀리면 그 창만 과분할되고 아무 데도 안 빨개진다. */
function sectionChunks(s,out){
  const q=parseCoverLetter(s.body);
  if(q.items.length){
    /* ⚠ **머리글 항목은 문항이 아니다** (#66-2). `q` 가 비면 `kind` 도 문항이 아니어야
       카드가 「문항」이라 적힌 채 물음 없는 덩이를 세우지 않는다. */
    q.items.forEach(it=>out.push({q:it.q,body:withHead(s.h,it.body),kind:it.q?"q":"para",h:s.h,parts:1}));
    return;
  }
  const cap=Math.max(300,CHUNK_MAX-(s.h?s.h.length+2:0));
  const label=s.h||(s.hs||[]).join(" · ");
  const bs=chunkParagraphs(s.body,cap);
  bs.forEach(b=>out.push({q:"",body:withHead(s.h,b),
    kind:(s.h||s.merged)?"head":"para",h:label,parts:bs.length===1?(s.n||1):1}));
}
/* 받은 글 하나 → 덩이 목록. **순서가 셋이다: 헤딩 → 문항 번호 → 빈 줄 문단.**
   ① 헤딩(`#`~`####`)이 있으면 거기서 먼저 가른다 — md 로 내보낸 지원서·이력서의 진짜 경계다
      ⚠ 가른 뒤에 **짧은 것끼리 다시 붙인다**(`mergeShortSections`) — 헤딩이 촘촘한 글에서
        구획 하나가 이야기 하나를 담기엔 너무 좁게 나온다(그 실측은 `SECTION_MIN` 머리글).
   ② 헤딩 아래(또는 헤딩이 없으면 글 전체)에 번호가 붙어 있으면 문항이 이긴다
   ③ 둘 다 없으면 빈 줄 문단. **여기가 2판 이전의 유일한 길이었고, 그래서 못 쓸 수준이었다**
   - Returns: `{items:[{q,body,kind,h}], error}` ·
     `kind` = `"q"`(문항) / `"head"`(헤딩 구획) / `"para"`(문단뿐) */
/* ★ 감긴 줄 펴기 (#52) — PDF 가 **시각 줄바꿈**을 그대로 넘겨서 생긴 사고를 입구에서 막는다.
   PDFKit 추출문에는 문단이 없다. 눈에 보이던 폭에서 잘린 물리 줄만 온다 — 그래서 문항 머리글이
   감겨 갈라졌고(「…기술해 주십시」+「오. (1,000자 이내)」), 줄머리에 온 소수가 문항으로 오인됐다.
   ⚠ **왜 화면에 있나**: 파일 던져넣기와 PDF 뷰어에서 긁어 붙여넣기가 **같은 길**로 온다.
     추출기(Swift)에 두면 붙여넣기가 그 자를 안 지난다 — 자가 둘이 되고 곧 갈린다.
   ★ **폭 신호로 스스로 문을 닫는다.** 사람이 친 글·md·docx 본문은 폭이 들쭉날쭉해서 게이트에
     안 걸린다. 걸리는 것은 **워드프로세서가 감은 글**뿐이다. 게이트 셋:
     ① 비빈 줄 8개 미만이면 표본이 없다 ② 비빈 줄 길이의 90퍼센타일 `w` 가 30~120 밖이면
     워드프로세서 감김 폭이 아니다(짧으면 손으로 친 글, 길면 md 긴 문단) ③ `w-8` 이상인 줄이
     비빈 줄의 절반 미만이면 감긴 글이 아니다.
   ⚠ **잇는 판정은 직전 「물리 줄」의 길이**이지 누적 문자열 길이가 아니다. 누적으로 재면
     문단 끝의 짧은 줄을 한 번 삼킨 뒤로도 계속 이어붙어 다음 문단까지 빨려 들어간다.
   ⚠ **공백 하나로 잇는다.** `실측 2026-08-31` — 이 함수가 `pdf-extracted-jasoseo.txt` 에서
     실제로 잇는 경계 **32곳**(43줄→11줄)을 하나씩 읽었다: **공백 소실 21 · 단어 중간 11.**
     공백 삽입이 다수 정답이다. (#52 채증은 같은 픽스처를 30곳 = 19+11 로 셌다 — 무엇을
     경계로 세느냐가 달라 공백 쪽만 둘이 갈린다. 단어 중간 11 은 양쪽이 같다.)
     `추론`: 대가는 「감정적으 로」 「주십시 오」 류 띄어쓰기 흠이 남는 것이고, 그건
     **구조 붕괴(문항 두 동강)보다 싸다** — 흠은 원문 글자가 다 남지만 붕괴는 답을 쪼갠다.
   ⚠ 블록 시작은 안 삼킨다 — 빈 줄 · `[` 로 여는 대괄호 소제목 · `QHEAD` · `MDHEAD`. */
/* 게이트 넷 — 선언한 값이지 실측이 아니다(`unwrapHardLines` 머리글). 이름이 곧 무엇을 재는가다. */
const UNWRAP_MIN_LINES=8;   /* 표본 하한 — 이 밑으론 감김을 판정할 표본이 없다 */
const UNWRAP_W_LO=30,UNWRAP_W_HI=120;  /* 워드프로세서 감김 폭의 범위 */
const UNWRAP_SLACK=8;       /* 「꽉 찬 줄」 판정의 여유 — w 에서 이만큼 모자라도 꽉 찬 것 */
function unwrapHardLines(text){
  const src=text||"";
  const lines=src.split(/\r?\n/),ne=lines.filter(l=>l.trim());
  if(ne.length<UNWRAP_MIN_LINES)return src;
  const lens=ne.map(l=>l.length).sort((a,b)=>a-b);
  const w=lens[Math.min(lens.length-1,Math.floor(lens.length*0.9))];
  if(w<UNWRAP_W_LO||w>UNWRAP_W_HI)return src;
  const full=w-UNWRAP_SLACK;
  if(ne.filter(l=>l.length>=full).length*2<ne.length)return src;
  const isBlock=ln=>!ln.trim()||/^[ \t]*\[/.test(ln)||QHEAD.test(ln)||MDHEAD.test(ln);
  const out=[];let prev=null;                 /* prev = 마지막으로 **읽은 물리 줄** */
  lines.forEach(ln=>{
    if(out.length&&prev&&prev.trim()&&prev.length>=full&&!isBlock(ln)){
      out[out.length-1]+=" "+ln.replace(/^[ \t]+/,"");
      prev=ln;return;
    }
    out.push(ln);prev=ln;
  });
  return out.join("\n");
}
function sliceIntake(text){
  /* ★ 펴기가 **입구 한 자리**다 (#52). 아래 세 길(헤딩·문항·문단)이 전부 이 뒤에 있어야
     감긴 줄이 어느 한 길에서만 고쳐지는 일이 안 생긴다. 안 감긴 글에는 항등이다(위 게이트). */
  text=unwrapHardLines(text||"");
  const raw=text||"";
  if(!raw.trim())return{items:[],error:"받은 글이 없어요 — 파일을 고르거나 자소서 전문을 붙여넣어 주세요"};
  const secs=splitHeadings(raw);
  if(secs.length){
    const items=[];mergeShortSections(secs,SECTION_MIN).forEach(s=>sectionChunks(s,items));
    if(items.length)return{items:items,error:null};
  }
  const r=parseCoverLetter(raw);
  if(r.items.length)return{items:r.items.map(it=>({q:it.q,body:it.body,kind:it.q?"q":"para",h:"",parts:1})),error:null};
  const chunks=chunkParagraphs(raw,CHUNK_MAX);
  if(!chunks.length)return{items:[],error:"가를 게 없어요 — 글자가 있는 줄이 하나도 없어요"};
  return{items:chunks.map(b=>({q:"",body:b,kind:"para",h:"",parts:1})),error:null};
}
/* ★ 초안이 못 올 때 물러설 자리 — **첫 줄이 제목, 나머지가 본문**이다 (#40).
   ⚠ 한 줄뿐이면 제목만 `candTitle` 로 잘라내고 **본문은 원문 그대로 둔다** — 기계가
     본문을 만들지 않는다는 던져 넣기 철학 그대로다. 빈 본문으로 저장하면 그 조각은
     제목만 남아 색인이 얕아진다. */
function machineDraft(text){
  const t=(text||"").trim(),i=t.indexOf("\n");
  if(i<0)return{title:candTitle(t)||t.slice(0,34),body:t};
  return{title:t.slice(0,i).trim().slice(0,60),body:t.slice(i+1).trim()};
}
/* ★ 문항 하나가 **어느 물음인가** (#14 → #29 → #33 → #53).
   ⚠ **#53 이 「기존 질문에 붙이기」를 걷었다.** 여기 있던 `chipFor`(문항↔질문 대칭 코사인)와
     `CHIP_T`(0.13)·`CHIP_ON`(0.60)·`chipOn` 이 그것이고, 붙일 자리를 고르던 칩 목록 UI 도
     같이 걷혔다. 남은 규칙은 하나다: **문항은 그 자체로 예상 질문이 된다**
     (#13 사용자 이야기 4 — 그 길은 안 죽었다. 「새 질문으로」가 늘 켜져 있던 셈이다).
   ⚠ **그러면 같은 질문이 두 번 앉지 않나.** 그것만 막는다 — `SAME_Q` 로. **자를 새로 안
     만든다**: 수확 질문이 「이미 목록에 있나」를 재는 그 자, 그 문턱 그대로다
     (`실측 2026-08-29`, #22: 같은 질문 0.733~1.000 · 다른 질문 0.000~0.130. 안 겹친다).
   ⚠ **글자 자뿐이라 뜻이 같고 말이 다른 두 물음은 못 합친다.** 걷힌 `chipFor` 의 뜻 자가
     그 자리를 12/18 로 맞혔었다 — 잃은 것을 적어 둔다. 대가는 질문 목록에 비슷한 물음이
     두 줄 앉는 것이고, 사람이 구멍 목록에서 지울 수 있다(`.gpx`). 매칭은 안 다쳐도 된다:
     **질문 글자는 이제 어느 자에도 안 들어간다**(`qscore`·`escore` 머리글).
   - Returns: 그 문항이 앉을 질문 id. 기존 것에 붙였으면 그 id, 아니면 **새로 앉히고** 그 id. */
function questionForItem(text){
  const t=String(text||"").trim();
  if(!t)return null;
  const same=DOC.questions.find(x=>sim(t,x.text)>=SAME_Q);
  if(same)return same.id;
  const q={id:uid("q"),text:t};
  DOC.questions.push(q);
  return q.id;
}

/* ★ 「같은 질문을 또 들었나」 문턱 — `실측 2026-08-29`(#22).
   전사 흔들림으로 갈라진 같은 질문(합쳐야 하는 것)과, 말투만 다른 같은 뜻(살려야 하는 것)을
   이 `sim` 으로 갈랐다:
     같은 질문 다시 들은 것   0.733 ~ 1.000   (「…계신가요」 vs 「…계신가요요」 = 0.933)
     말투가 다른 같은 뜻      0.000 ~ 0.130   ← **이건 합치면 안 된다.** 새 변형이 색인을 넓힌다
     아예 다른 질문           0.000 ~ 0.077
   ★ **여기는 안 겹친다** — 간격 0.603. 이 레포의 다른 문턱들(#20 색 · #14 칩)과 다른 점이다.
   0.45 는 그 간격 한가운데다. */
const SAME_Q=0.45;
/* ★ **판정을 미루는 자리** (QA 2026-08-30 블로커 F3).
   `onEar` 의 `ended` 는 `onQueryVector` 보다 **먼저** 온다 — 전사를 임베딩이 기다리지 않게
   통로를 갈랐기 때문이다(#34, `startInterviewEars` 주석). 그래서 확정 시점의 `rank()` 는
   **글자 자**로 돌고, 뜻 자로는 초록인 질문이 빨강으로 읽혀 구멍으로 주워진다.
   `실측 2026-08-30`(jiwon 재현 자료 · 질의 8개): 확정 시점 판정으로 **5개가 잘못 주워졌다.**
   그 중 「동료와 의견이 부딪쳤을 때 어떻게 하셨나요」는 한 박자 뒤 **1.138 초록**이었다.
   → **잴 수 있는 자가 곧 온다면 기다린다.** 기다려도 안 오는 자리(브라우저 단독 · 모델 없음 ·
     색인 실패)에서는 예전 그대로 글자 자로 즉시 판정한다 — `scorer()` 와 같은 **선언된 갈림**이다.
   ⚠ 못 잰 채 남은 것은 **안 줍는다.** 잘못 줍는 것(남의 저장소에 헛질문이 앉는다)이
     못 줍는 것(다음 면접에 다시 들린다)보다 비싸다. */
const HARVEST_WAIT_MAX=6;
let harvestPending=[];
/* 이 질의를 **지금** 판정해도 되나 — 순수 함수라 `node --test` 가 잠근다.
   ① 벡터 꾸러미가 아예 없다 → 기다려도 안 온다. 지금 글자 자로 잰다
   ② 그 질의의 벡터가 이미 왔다(`scorer`=="뜻") → 지금 잰다
   ③ 그 밖 = 꾸러미는 있는데 이 질의의 벡터만 아직이다 → **기다린다** */
const harvestNow=(q,qvec,vec)=>!vec||scorer(q,qvec,vec)==="뜻";
/* 확정된 상대 질문 하나를 본다. **빨강이면**(어떤 조각도 안 덮으면) 주워 둔다.
   ⚠ 판정할 자가 아직이면 줄을 세운다 — `applyRank` 가 벡터를 받은 뒤 다시 부른다. */
function harvestQuestion(q){
  const t=(q||"").trim();
  if(t.length<4)return;                               /* 한두 글자는 전사 부스러기다 */
  /* ⚠ 재조준과 **같은 자**를 건다 (#41). "네 알겠습니다" 같은 맞장구 뭉치는 저장소 밖이라
     빨강으로 매겨져 「면접에서 온 질문」으로 얹힌다 — 구멍 목록이 추임새로 오염된다. */
  if(!askable(t))return;
  if(!harvestNow(t,QVEC,VEC)){
    if(harvestPending.indexOf(t)<0)harvestPending.push(t);
    /* 밀린 것은 버린다 — `embedQuery` 가 낡은 질의를 버리는 것과 같은 사정이다(벡터가
       영영 안 올 수 있다). 버린 것은 **안 줍는다**: 위 대가 비교 그대로. */
    while(harvestPending.length>HARVEST_WAIT_MAX)harvestPending.shift();
    return;
  }
  judgeHarvest(t);
}
/* 판정 한 번. **자가 무엇이든 여기 한 곳**이다 — 확정 시점과 벡터 도착 뒤가 갈리면
   같은 질문이 자에 따라 다르게 주워진다. */
function judgeHarvest(t){
  const r=rank(t);
  /* ★ 기록은 **자에 상관없이** 여기서 (#79) — 글자 자면 색 없이 적힌다. 아래 줍기는 뜻 자만.
     ⚠ **이 줄이 return 들보다 앞이다**: 줍기가 안 드는 것(초록·이미 있는 질문)도 기록이다. */
  noteAsked(t,r);
  /* ★ **글자 자로는 이제 판정하지 않는다** (#53). 이 함수가 이미 든 규칙 — *잘못 줍는 것이
     못 줍는 것보다 비싸다*(`harvestQuestion` 머리글) — 을 새 실측에 그대로 적용한 것이다.
     `실측 2026-08-31`: 축이 제목+본문 하나로 줄면서 글자 자의 세 무리(정답 · 오답 · 저장소 밖)가
     **통째로 겹쳤다**(`RISK_G` 머리글의 표). 즉 이 자로 매기면 **들리는 말이 전부 빨강**이고,
     그러면 되먹임이 「답할 조각이 없는 질문」이 아니라 **면접에서 들린 말 전부**를 줍는다 —
     #52 채증 ④(수확 질문 5건 전부 전사 쓰레기)가 바로 그 모양이다.
     ⚠ **선언된 갈림**이지 고장이 아니다: 브라우저 단독 · 모델 없음 · 색인 실패에서는
       되먹임이 **안 돈다.** 예전엔 돌았고 그때는 칩 글자가 자를 받쳐 줬다 — 그 받침이 없다.
     ⚠ 저장소가 통째로 비면(`r.length===0`) 잴 것이 없으니 그대로 줍는다. 잴 자가 없는 것과
       **잴 대상이 없는 것**은 다르다. */
  if(r.length&&r[0].how!=="뜻")return;
  /* ⚠ 색은 `rank()` 가 같이 준다 — 여기서 `risk(r[0].s)` 로 다시 재면 안 된다.
     점수의 눈금이 자에 따라 다르다(#34): 뜻 자는 1.0 이 초록선, 글자 자는 0.15 다. */
  if(r.length&&r[0].c!=="r")return;                   /* 초록·주황은 안 얹는다 */
  if(DOC.questions.some(x=>sim(t,x.text)>=SAME_Q))return;   /* 이미 목록에 있다 */
  if(harvest.some(x=>sim(t,x)>=SAME_Q))return;              /* 이 면접에서 이미 주웠다 */
  harvest.push(t);
}
/* 기다리던 것 중 **이제 잴 수 있는 것**을 판정한다. `applyRank` 가 부른다 —
   그래야 harvest 판정이 화면 순위와 **같은 상태(QVEC·VEC)** 에서 나온다. */
function resolveHarvest(){
  if(!harvestPending.length)return;
  const rest=[];
  harvestPending.forEach(t=>{if(harvestNow(t,QVEC,VEC))judgeHarvest(t);else rest.push(t)});
  harvestPending=rest;
}
/* 쌓기로 돌아갈 때 한 번에 옮긴다. 여기서 처음으로 문서가 바뀐다.
   ⚠ 아직 못 잰 것은 **여기서 버린다** — 면접이 끝났으니 그 벡터는 이제 안 온다.
   ★ 정돈은 **줄만 세운다** (#47) — 실제 요청은 `pumpTidy` 가 낸다. 왜 여기서 안 보내나:
     이 함수는 면접 모드 안(`goMode`)에서 불리고, 정돈은 쌓기에서 할 일이다.
     자세한 것은 `pumpTidy` 머리글. */
function commitHarvest(){
  harvestPending=[];
  /* ★ 기록이 먼저다 — **줍힌 것이 없어도** 옮긴다(초록만 들린 면접이 그 모양이다).
     그래서 아래 `if(!harvest.length)return` 보다 위에 산다. */
  if(askedPending.length){
    askedPending.forEach(e=>{DOC.asked=logAsked(DOC.asked,e.text,"interview",{c:e.color,s:e.score,how:e.how},e.at,e.count)});
    askedPending=[];
    if(!harvest.length)save();      /* 줍힌 것이 있으면 아래 `save()` 가 같이 싣는다 */
  }
  if(!harvest.length)return;
  const n=harvest.length;
  harvest.forEach(t=>{const q={id:uid("q"),text:t,fromInterview:true};
    DOC.questions.push(q);tidyQ.push(q.id)});
  harvest=[];
  save();
  /* 조각이 없으니 이 질문들은 **자동으로 구멍**이 된다 — 구멍 짚기 동선이 그대로 이어받는다.
     ★ **#53 이 이 질문들을 매칭에서 뺐다** (경계표 ③ · 「남는다」 2행). 얹히는 것은 그대로고,
       달라진 것은 얹힌 뒤다: 예전에는 이 글자가 **색인의 열쇠**로 들어갔다 —
       ① 글자 자의 `qforms` ② 뜻 자의 매개 갈래 ③ 던져 넣기·편집기 칩 제안. 셋이 다 걷혔다.
       `실측 2026-08-31`(#52 채증 ④): 실전 볼트의 `fromInterview` 질문 **5건이 전부 전사
       쓰레기**였고, 그것이 열쇠인 동안 **면접을 할수록 검색이 나빠졌다.** 그 되먹임을 끊는다.
     ⚠ 그래도 **정돈(#47)은 그대로 돈다** — 목록에 뜨는 글자라 사람이 읽는다. 색인 때문이
       아니라 화면 때문이고, 그 이유는 이 조치 뒤에도 안 죽었다. */
  notice=`면접에서 온 질문 ${n}개를 예상 질문에 얹었다 — 아래 구멍 목록에서 지울 수 있다`;
  /* ★ 문지기(#47 후속)가 몇을 버리면 **위 줄의 개수가 거짓말이 된다.** 그때 고쳐 쓰려고
     지금 세운 줄과 수를 들고 있는다 — 고치는 자리는 `fixHarvestNote` 하나다. */
  tidyNote=notice;tidyKept=n;tidyDrop=0;
}
/* ── 수확 질문 정돈 (#47) ────────────────────────────────────────────────────
   ★ 왜 (박선호 2026-08-30, 실전 재실기): *"마이크에서 인식한 약간 발음이 뭉개지거나 문장
     완성 상태가 안좋은 그대로 색인을 보여주는게 너무 어설픔"*. 전사 원문 그대로 구멍 목록에
     앉으면 어설프고, 그 글자가 그대로 임베딩 색인에도 들어간다.

   ★ **이 통로는 쌓기 쪽에서만 열린다.** `commitHarvest` 는 줄만 세우고(`tidyQ`), 통로를
     실제로 여는 것은 아래 `pumpTidy` 하나이며 그것은 `stackRender` 아래에서만 불린다 —
     ⚠ 이 주석에 통로를 여는 **글자 모양 그대로**(`post(` + 이름)를 안 적는다.
       판정선 검사는 주석을 안 가려서, 적으면 「면접 모드가 이 통로를 연다」로 세어진다.
     `tests/check_interview_offline.py` 의 선언된 경계(`BOUNDARY = ("stackRender",)`) **바깥**이다.
     온디바이스라 네트워크 판정선과는 무관하지만, **면접 중에 모델을 물고 있을 이유가 없다**:
     귀·검색·임베딩이 이미 돌고 있고 거기에 생성까지 얹으면 그게 밀린다.
   ⚠ 그래서 이 넷(`tidyQ`·`pumpTidy`·`onQuestionTidy`·`fixHarvestNote`)을 면접 모드에서
     부르면 안 된다. 부르는 순간 판정선이 재는 그래프가 넓어진다.
     (`dropQuestion` 은 예외다 — ✕ 버튼이 `stackRender` 안에서도 부르고, 그 자리는
      선언된 경계라 순회가 거기서 멈춘다.)

   ★ **정돈 앞에 문지기가 섰다** (#47 후속 · #52 채증 ④). Swift 쪽 `AskedQuestion` 이
     「이게 면접관이 던진 질문이긴 한가」를 판정하고, `junk` 로 오면 그 질문을 목록에서 뗀다.
     왜 정돈이 그 일을 못 하나: 정돈은 다듬기만 해서 **다듬어진 인사말**을 낸다. */
let tidyQ=[],tidyCur=null,tidyDirty=false;
/* ★ 문지기가 버린 수 · 얹혔다고 말한 줄과 그 수 (#47 후속 — `fixHarvestNote`). **세션에만 산다.** */
let tidyDrop=0,tidyNote=null,tidyKept=0;
/* ★ 정돈문을 받아들일까 — **순수 함수라 `node --test` 가 잠근다.**
   받아들일 수 없으면 `null` 이고, 그때는 **원문을 그대로 둔다**.
   ⚠ **자가 둘이고 방향이 반대다.** 양쪽 다 `실측 2026-08-30` 에서 나왔다:
     ① 크게 길어졌다 = 모델이 **지어내기 시작한 것**. 어설픈 원문보다 없던 내용이 색인에
        앉는 쪽이 나쁘다.
     ② 크게 짧아졌다 = **내용이 떨어져 나간 것.** 실측에서 「아 그러면은 저희 회사에 지원하신
        이유가 어떻게 되실까」(27자)가 「지원하신 이유」(7자)로 왔다 — 정돈이 아니라 잘림이다.
   ⚠ 여러 줄도 안 받는다. 질문은 한 문장이라는 것이 이 정돈의 계약이다.
   ⚠ 배수는 **실측이 아니라 선언한 값이다.** 실측에서 성한 정돈은 0.58~1.3배 안에 있었다. */
/* 질문 하나를 문서에서 떼어낸다 — **지우는 자가 여기 하나다.**
   ⚠ 조각이 든 칩(`questionIds`)도 같이 뗀다. 자가 둘이면 한쪽이 그것을 남겨
     **없는 질문을 가리키는 칩**이 저장소에 앉는다.
   ⚠ 저장하지 않는다 — 부르는 쪽이 언제 저장할지 안다(✕ 는 그 자리에서, 문지기는 줄이 다 빠진 뒤). */
function dropQuestion(id){
  DOC.questions=DOC.questions.filter(q=>q.id!==id);
  DOC.fragments.forEach(p=>{if(p.questionIds)p.questionIds=p.questionIds.filter(x=>x!==id)});
}
function tidyOk(orig,text){
  const o=String(orig||"").trim(),t=String(text||"").trim().replace(/\s+/g," ");
  if(!o||!t)return null;
  if(t.length>Math.max(60,Math.round(o.length*1.6)))return null;
  if(t.length<Math.max(4,Math.round(o.length*0.5)))return null;
  return t;
}
/* 줄에서 하나를 꺼내 보낸다. **한 번에 하나만** — `pumpIntake` 와 같은 사정이다
   (FoundationModels 는 동시 요청을 거절할 수 있다).
   ⚠ **브리지가 없으면 줄을 비운다** — 브라우저 단독엔 답이 영영 안 온다. 원문 유지다.
   ⚠ 여러 번 불려도 안전해야 한다 — `stackRender` 가 그릴 때마다 부른다. */
function pumpTidy(){
  if(tidyCur!==null||!tidyQ.length)return;
  if(!bridged()){tidyQ=[];return}
  const id=tidyQ.shift(),q=DOC.questions.find(x=>x.id===id);
  if(!q){pumpTidy();return}
  tidyCur=id;post("tidyQuestion",{id:id,text:q.text});
}
/* ★ Swift → JS. 정돈문 `{id,text}` / 실패 `{id,error,why}`. 실패도 답이다 — 안 오면 줄이 멈춘다.
   ⚠ 갈아끼운 뒤 `save()` 한다. 저장이 끝나면 Swift 가 **정돈문으로 색인을 다시 돈다**
     (`indexFragments` 가 질문 축도 같이 든다) — 그게 이 티켓의 절반이다.
   ⚠ **다시 그리는 것은 줄이 다 빠진 뒤 한 번뿐이다.** 답마다 그리면
     ① 사람이 보는 목록이 질문마다 한 번씩 튀고
     ② `stackRender` 는 **지금 보고 있는 화면을 통째로 다시 짓는다** — 받기 화면이면
        `ingestRender` 가 `INTAKE` 를 비우고(그 머리글), 설정 화면이면 사람이 치고 있던
        키 칸이 날아간다. 둘 다 「보던 것을 뺏는 것」이라 기능 하나보다 비싸다.
     ⚠ **전 판의 이유는 걷혔다**: 「씨앗뿐인 문서면 받기 화면으로 넘어간다」는 줄이
       승격 라운드(#61 A)에 사라졌다 — 시작 화면은 언제나 쌓기다(`stackView` 머리글).
       남은 이유는 위 ②뿐이고, 그건 여전히 참이다.
     아래 세 조건이 그 둘째를 막는 자리다: 쌓기 · 편집 화면 · 아무 조각도 안 고르는 중. */
function onQuestionTidy(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d)return;
  if(tidyCur===d.id)tidyCur=null;
  const q=DOC.questions.find(x=>x.id===d.id);
  /* ★ **문지기 판정이 먼저다** (#47 후속). `junk` 는 「질문이 아니다」는 **판정**이지 사고가
     아니라, 여기서 그 줄을 목록에서 뗀다. 사고(`d.error`)는 이 칸을 안 달고 오고 아래에서
     「원문 유지」로 흘러간다 — 그 갈림의 근거는 `QuestionTidier.tidy` 의 문지기 주석에 있다.
     ⚠ **이번 면접이 방금 얹은 것만 여기 온다** — 줄(`tidyQ`)을 채우는 자리가 `commitHarvest`
       하나다. 볼트에 이미 있던 질문은 이 자를 안 탄다(사람 데이터라 우리가 안 지운다). */
  if(q&&d.junk){dropQuestion(d.id);tidyDrop++;tidyDirty=true;save()}
  else{const t=q?tidyOk(q.text,d.text):null;
    if(q&&t&&t!==q.text){q.text=t;tidyDirty=true;save()}}
  if(tidyQ.length){pumpTidy();return}
  fixHarvestNote();
  if(!tidyDirty)return;
  tidyDirty=false;
  if(mode==="stack"&&stackView==="edit"&&sel===null)stackRender();
}
/* 줄이 다 빠진 뒤 **한 번.** 「N개를 얹었다」가 버린 만큼 틀렸으니 그 줄을 고쳐 쓴다.
   ⚠ **띠가 아직 그 줄일 때만 고친다.** 그새 사람이 채우기를 시작했거나 다른 알림이 왔으면
     그 자리는 이제 다른 것의 자리다 — 덮으면 방금 뜬 말을 지운다.
   ⚠ 하나도 안 남으면 「지금 채우기」도 끈다 — 그 버튼이 하는 말이 *면접에서 온 것부터
     짚어요* 인데, 짚을 것이 없으면 그 말이 거짓말이다. */
function fixHarvestNote(){
  const m=tidyDrop;tidyDrop=0;
  if(!m||notice!==tidyNote)return;
  const kept=Math.max(0,tidyKept-m);
  notice=kept?`면접에서 온 질문 ${kept}개를 예상 질문에 얹었다 — 질문이 아닌 ${m}개는 걸러냈다`
             :`면접에서 들린 ${m}개는 질문이 아니라 안 얹었다`;
  tidyNote=notice;tidyKept=kept;
}

/* ══ 연습 (#36) — 앱이 묻고, 기존 귀가 듣고, 기존 자가 채점한다 ═════════════════════
   ★ **새 부품이 거의 없다.** 연습은 면접 모드의 변형이다:
       질문이 **상대가 아니라 앱**에서 나오고 · **마이크만** 듣고 · 질의가 상대 말이 아니라 **내 답**이다.
   귀는 `InterviewEars` 그대로(`startListening` 에 「시스템 오디오는 빼라」만 얹었다),
   채점은 `rank()` 그대로다(#34 의 뜻 자 · 못 쓰면 글자 자). **자를 새로 만들지 않았다** —
   그래서 이 흐름이 곧 귀와 검색의 실전 시험이 된다(티켓이 그것을 요구했다).

   ⚠ **자가 채점이지 감독이 아니다.** 이 자가 재는 것은 「닮았나」라서 질문을 그대로 소리내어
     읽어도 점수가 난다. 막는 코드를 안 넣는다 — 속이는 대가가 본인 것이고, 막으려면
     「답인가」를 판정하는 새 자가 필요한데 그건 이 티켓이 산 것이 아니다.
   ⚠ **점수는 재훈련이 아니다.** 성적은 파일에 안 남는다(`prac` 는 세션에만 산다). */

/* ══ 연습이 쓰는 자 셋 — **여기가 그 집이다** (#74 C5) ══════════════════════════
   ★ 셋은 저장소(우주) 화면에서 통째로 나왔다. 준비도 줄·구멍 행·채우기가 죽으면서
     남은 부르는 쪽이 **연습 하나**가 됐고, 그래서 이름 앞에 그 사실을 적고 여기로 옮겼다
     (`readiness`→`practiceReadiness` · `unprepared`→`practiceUnprepared` · `gaps`→`practiceGaps`).
   ⚠ **자를 안 바꿨다** — 재는 것은 여전히 `escore`(내용 직접) 하나고 문턱도 `eris` 그대로다.
     바뀐 것은 **이름과 사는 자리**뿐이고, 그래서 옛 이름을 세는 grep(#74 AC7)이 0 이 된다.
   ⚠ `practiceReadiness` 를 지금 부르는 화면은 없다 — 자물쇠(`tests/chip-suggest.test.mjs`)가
     ADR 0005 의 수를 이 함수로 재고 있어서 남는다. 그 자물쇠가 죽으면 이 함수도 같이 죽는다. */
/* ★ 준비도 집계 (#46) — 「질문 N개 중 초록 몇 · 주황 몇 · 빨강 몇」. 순수 함수라 `node --test` 가 잠근다.
   ★ **자를 새로 안 만들었다.** 이 함수가 하는 계산은 라이브 검색의 **내용 직접 갈래 그대로**다 —
     `cosv` 로 재고 `SIM_G_DIRECT` 로 나누고 `eris` 로 칠한다. 그래서 여기 초록은 화면이
     「그 질문이 들리면 초록 카드가 뜬다」고 말하는 것과 **같은 뜻**이다(`CONTEXT.md` 신호등 불변식 ①).
   ⚠ **거울이 되면 안 된다.** 질의로 세우는 것이 그 질문의 벡터라, 매개 갈래가 살아 있던 때
     그것을 쓰면 자기 자신과의 코사인 1.0 을 물어 **무조건 초록**이 됐다. #53 이 그 갈래를
     통째로 걷어서 이제 이 함정 자체가 없다 — 그래도 이 줄을 남긴다: 다시 지으면 다시 생긴다.
   ⚠ **칩으로 안 좁힌다.** 받기(#40)가 넣은 답변은 `questionIds` 가 비어 있어서, 칩으로 좁히면
     방금 들어온 답변 열 장이 전부 빨강으로 세어진다 — 저장소에 있는데 없다고 말하는 셈이다.
   ⚠ 씨앗은 뺀다 — `rank()` 가 빼는 것과 같은 이유(예시가 「준비됨」으로 세어지면 안 된다).
   ⚠ 벡터가 없으면 **`null` 이고 줄이 통째로 사라진다.** 글자 자로 물러서지 않는다: 눈금이
     달라(#34) 두 자의 수가 같은 줄에 섞이면 그 줄이 거짓말이 된다. **선언된 갈림**이다.
   - Returns: `{n,g,a,r}` · 잴 수 있는 질문이 하나도 없으면 `null` */
function practiceReadiness(questions,fragments,vec){
  if(!vec)return null;
  const out={n:0,g:0,a:0,r:0};
  (questions||[]).forEach(q=>{
    const qv=qvecOf(q.id,vec);
    if(!qv)return;
    const best=bestDirect(qv,fragments,vec);
    out.n++;out[best===null?"r":eris(best)]++;
  });
  return out.n?out:null;
}
/* ★ 「이 질문엔 준비된 답변이 없다」인가 — **연습 화면이 띄우는 그 한 줄의 판정** (#49).
   순수 함수라 `node --test` 가 잠근다.

   ★ **왜 `practiceGaps()` 가 아닌가.** `practiceGaps()` 는 **칩이 안 걸린 질문**을 센다. 그런데 받기가 앉힌
   조각은 `questionIds` 가 비어 있어(`saveDrafts` 의 ⚠), 글을 통째로 넣은 **직후**에 연습을 열면
   방금 넣은 답이 있는데도 「준비된 답변이 없다」+빨강이 뜬다. 같은 순간 **준비도 줄은 초록**이다 —
   그 줄은 내용 직접 자로 재기 때문이다. 한 화면이 두 말을 하고 있었다.
   `실측 2026-08-30`(말뭉치 `tests/fixtures/chip_suggest.json`, 조각 12장의 칩을 **전부 비운** 판):
   `practiceGaps()` 는 질문 10개를 **전부** 구멍이라 했고, 내용 직접 자는 **초록 5 · 주황 2 · 빨강 3** 이다.
   즉 7개는 답이 있는데 없다고 말하고 있었다.

   ⚠ **칩이 이기는 것이 먼저다.** 사람이 건 칩은 확정된 간선이라 점수를 볼 것도 없다.
   ⚠ **벡터가 없으면 예전 판정 그대로** — 브라우저 단독·모델 없음·색인 실패에서는 칩만 남는다.
     선언된 갈림이지 고장이 아니다(`practiceReadiness` 가 통째로 사라지는 것과 같은 자리).
   ⚠ **자를 새로 안 만들었다.** 저장소에 기계 추측을 쓰지도 않는다 — 고친 것은 **읽는 쪽**이다. */
function practiceUnprepared(qid,fragments,vec){
  /* ★ 기록 줄(`a-…`)엔 칩도 질문 벡터도 없다 — 아래 두 자는 정의상 「없다」고 답한다. 그 줄의 판정은
     **온 순간의 색**(연습에서 다시 받은 색이 있으면 그것)이다 (#79): 빨강이었으면 준비가 없던 것이고,
     색이 없으면(글자 자) 모르는 것이지 없는 것이 아니다 — 없다고 말하지 않는다. */
  const A=askedById(qid);
  if(A)return (A.practiceColor||A.color)==="r";
  if((fragments||[]).some(p=>((p.questionIds||[]).includes(qid))))return false;
  const qv=qvecOf(qid,vec);
  if(!qv)return true;
  const best=bestDirect(qv,fragments,vec);
  return best===null||eris(best)==="r";
}

/* ⚠ **이건 검색이 아니라 장부다** (#53). 세는 것은 「사람이·흐름이 확정한 간선이 있는가」이고,
   그 간선은 채우기(#35)·구멍 짚기·받기 승인에서만 앉는다. **매칭은 이 수를 안 본다** —
   면접 중 순위는 내용 직접 하나로 나고, 칩이 0개인 조각도 똑같이 1위가 될 수 있다.
   ⚠ 「답이 있나」를 묻는 자리에는 `practiceUnprepared` 를 쓴다 — 그 머리글이 이 둘의 갈림을 든다. */
const practiceGaps=()=>DOC.questions.filter(q=>!DOC.fragments.some(p=>(p.questionIds||[]).includes(q.id)));

/* ★ **방금 들어온 답변이 걸릴 만한 질문** (#49 H3) — 순수 함수라 `node --test` 가 잠근다.
   왜 있나: 받기(#40)로 열 장이 한 번에 들어온 직후에 연습을 열면, 기본 순서는 **구멍부터**라
   방금 쓴 것과 아무 상관 없는 질문이 먼저 뜬다. 첫 한 문항이 「방금 넣은 그 이야기」여야
   사람이 자기가 뭘 만들었는지 그 자리에서 본다.
   ⚠ **자를 새로 안 만든다** — `sim`(순위·색이 쓰는 그 bigram Jaccard) 그대로다.
     뜻 자를 쓰려면 방금 저장된 조각의 벡터가 필요한데 그건 색인이 끝나야 오고,
     이 버튼은 그것을 기다릴 수 없다(기다리면 「바로」가 아니다).
   ⚠ 순서는 ① 그 조각이 **이미 든 칩** ② 그 다음 **글자로 닮은 순**이다. ①이 앞인 이유는
     칩은 사람이·색인이 확정한 간선이고 ②는 짐작이라서다.
   ⚠ 점수가 0인 질문은 **안 넣는다.** 넣으면 아무 상관 없는 질문이 앞으로 당겨져
     기본 순서(구멍 먼저)보다 나쁜 순서가 된다 — 「실패 시 기존 순서 그대로」가 그 뜻이다.
   ⚠ 점수가 같으면 id 순 — 실행마다 순서가 안 바뀌게(`suggestChips` 와 같은 규칙).
   - Returns: 질문 id 목록, 앞자리부터. 셀 것이 없으면 **빈 배열**(부르는 쪽이 기존 순서로 간다) */
const FRESH_N=3;
function freshQids(frags,questions,n){
  const list=(frags||[]).filter(Boolean),out=[],seen=new Set();
  list.forEach(p=>((p.questionIds||[])).forEach(id=>{if(!seen.has(id)){seen.add(id);out.push(id)}}));
  const scored=[];
  (questions||[]).forEach(q=>{
    if(seen.has(q.id))return;
    let best=0;
    list.forEach(p=>{const s=sim(q.text,((p.title||"")+" "+(p.body||"")).trim());if(s>best)best=s});
    if(best>0)scored.push({id:q.id,s:best});
  });
  scored.sort((a,b)=>a.s===b.s?(a.id<b.id?-1:1):b.s-a.s);
  return out.concat(scored.map(x=>x.id)).slice(0,n===undefined?FRESH_N:n);
}
/* 물어볼 순서. **구멍이 먼저**(준비가 아예 없는 자리가 제일 뜨겁다), 그 다음 나머지를 **섞는다**.
   ⚠ 섞는 이유: 순서가 고정이면 연습이 그 순서의 암기가 된다. 구멍은 **안 섞는다** —
     질문 목록 순서 그대로라 「어디까지 뚫렸나」가 눈에 남는다(`fillOrder` 와 같은 규율).
   ⚠ `rnd` 는 **시험이 갈아끼우라고** 있다. 안 주면 `Math.random`.
   ★ `first` = **맨 앞으로 당길 질문 id 목록**, 그 목록의 순서 그대로 (#49 H3) —
     `fillOrder` 의 `first` 와 **같은 모양**이다. 안 주면 예전 순서 그대로 돈다.
   ⚠ 없는 질문 id 는 조용히 빠진다 — 남기면 진행 표시(`k/총`)가 거짓말이 된다(`fillOrder` 와 같은 사정). */
function practiceOrder(rnd,first){
  const r=rnd||Math.random,hole=new Set(practiceGaps().map(q=>q.id)),seen=new Set();
  const pri=[];
  (first||[]).forEach(id=>{if(!seen.has(id)&&DOC.questions.some(q=>q.id===id)){seen.add(id);pri.push(id)}});
  /* ★ **기록이 질문 축보다 먼저다** (#79) — 그리고 그 안에서 **약한 것부터**(`askedOrder`).
     실제로 물어본 것이 아직 안 물어본 질문보다 뜨겁다. 질문 목록은 그 뒤에 예전 그대로 온다. */
  const logged=askedOrder(DOC.asked).filter(id=>!seen.has(id));
  logged.forEach(id=>seen.add(id));
  const head=DOC.questions.filter(q=>hole.has(q.id)&&!seen.has(q.id)).map(q=>q.id);
  const rest=DOC.questions.filter(q=>!hole.has(q.id)&&!seen.has(q.id)).map(q=>q.id);
  for(let i=rest.length-1;i>0;i--){const j=Math.floor(r()*(i+1)),t=rest[i];rest[i]=rest[j];rest[j]=t}
  return pri.concat(logged,head,rest);
}
/* 연습을 연다. 질문이 하나도 없으면 **안 열고** 그것을 한 줄로 말한다.
   ★ **새 볼트에서 0개가 기본이다** (#74 C5) — 씨앗 질문을 안 심으므로 「예상 질문이 없다」가
     정직한 첫 답이고, 질문은 면접에서 수확될 때 생긴다. */
function startPractice(rnd,first){
  const ids=practiceOrder(rnd,first);
  if(!ids.length){prac=null;notice="물어본 것이 아직 없다 — 태양에 묻거나 면접을 하면 여기 쌓인다";return false}
  prac={ids:ids,k:0,head:"",headq:"",cur:"",vol:"",curq:"",res:{},done:false};
  return true;
}
/* 연습이 기록 줄의 색(`practiceColor`)을 바꿨나 — **끝낼 때 한 번만** 저장한다.
   ⚠ 문항마다 저장하면 한 바퀴에 볼트를 열 번 다시 쓴다(`VaultStore` 의 「안 바뀌면 안 쓴다」와 같은 사정). */
let askedDirty=false;
function stopPractice(){prac=null;if(askedDirty){askedDirty=false;save()}}
/* 지금 묻고 있는 질문. ⚠ 목록은 **열 때 찍은 것**이라 낡는다 — 그새 지워진 질문은 건너뛴다
   ((옛 채우기 흐름) 와 같은 사정·같은 처방). 다 돌면 요약으로 넘어간다. */
function practiceQid(){
  if(!prac||prac.done)return null;
  const live=new Set(DOC.questions.map(q=>q.id).concat((DOC.asked||[]).map(a=>a.id)));
  while(prac.k<prac.ids.length&&!live.has(prac.ids[prac.k]))prac.k++;
  if(prac.k>=prac.ids.length){prac.done=true;return null}
  return prac.ids[prac.k];
}
/* 다음 질문으로. **답을 비운다** — 앞 답이 다음 채점에 섞이면 색이 거짓말이 된다. */
function nextPractice(){
  if(!prac)return null;
  prac.k++;prac.head="";prac.headq="";prac.cur="";prac.vol="";prac.curq="";
  return practiceQid();
}
/* 화면에 보이는 답(들린 그대로) / 채점에 넣는 답(부호 걷은 것). 면접 모드의 두 벌과 같은 갈림. */
const practiceHeard=()=>prac?(prac.head+" "+prac.cur).trim():"";
const practiceQuery=()=>prac?(prac.headq+" "+prac.curq).trim():"";

/* ★ 한 답의 채점. **`rank()` 를 그대로 쓴다** — 자도 눈금도 색도 라이브 검색과 한 벌이다.
   - 색은 **그 질문에 걸린 조각 중 최고**의 색이다. 판정선이 「준비한 조각대로 말했나」라서
     저장소 어딘가와 닮은 것만으로는 초록이 안 된다.
   - 그 질문에 걸린 조각이 하나도 없으면(구멍) **빨강**이다. 못 매기는 것이 아니라
     **준비가 없다는 것이 곧 결과**고, 그 자리가 채우기(#35)로 이어진다.
   - 저장소 1위(`top`)도 같이 돌려준다 — 다른 질문의 조각과 닮았으면 「딴 얘기를 했다」가 보인다.
   ⚠ 인자 둘은 **시험이 갈아끼우라고** 있다(`rank` 와 같은 규율). 안 주면 화면의 현재 상태를 쓴다. */
function practiceScore(answer,qid,qvec,vec){
  const t=(answer||"").trim();
  if(!t)return null;
  const r=rank(t,qvec,vec);
  if(!r.length)return null;
  /* `rank` 는 내림차순이라 **첫 개가 그 질문의 최고**다. 여기서 다시 정렬하지 않는다 */
  /* ★ 기록 줄(`a-…`)엔 칩이 **정의상** 없다 — 「그 질문에 걸린 조각」이라는 것이 없으니
     **저장소 1위**가 내 것이다. 칩으로 보면 영영 빨강이라 「약한 것부터」가 굳는다. */
  const mine=isAskedId(qid)?r:r.filter(x=>(x.p.questionIds||[]).includes(qid));
  const best=mine.length?mine[0]:null,top=r[0];
  return {c:best?best.c:"r",s:best?best.s:0,how:top.how,prepared:!!best,
          hitId:best?best.p.id:null,hitTitle:best?best.p.title:"",
          topId:top.p.id,topTitle:top.p.title,onTarget:!!best&&best.p.id===top.p.id};
}
/* 지금 답을 채점해 결과를 남긴다.
   ★ **첫 판정은 있는 자로 낸다.** 벡터를 기다리면 화면이 빈 채로 멈춘다 — 글자 자로 먼저 칠하고,
     뜻 자가 도착하면 `onDraftVector` 가 이 함수를 다시 불러 갈아끼운다(`splitDoc` 과 같은 모양).
   ⚠ **통로를 안 늘렸다.** 답 벡터는 #33 이 낸 `embedDraft` 를 **칸 이름만 달리해**(`answer`) 쓴다.
     그 칸은 이미 「아직 저장 안 된 글자의 벡터」를 위한 자리다 — 내 답이 정확히 그것이다.
   ⚠ **`kind` 는 `query` 다.** 내 답은 글로 보면 조각(passage)에 가깝지만, 여기서 재는 축은
     라이브 검색과 **같은 축**이어야 한다 — 초록선(`SIM_G_DIRECT`)이 query↔passage 에서
     재어진 값이라서다(#34). 축을 바꾸면 그 문턱이 근거를 잃는다. */
function gradePractice(){
  const qid=practiceQid();if(!qid||!prac)return null;
  const t=practiceQuery();
  const qv=(DRAFT.answer&&DRAFT.answer.t===t)?{q:t,v:DRAFT.answer.v}:null;
  const r=practiceScore(t,qid,qv,VEC);
  if(r)prac.res[qid]=r;
  /* ★ 연습이 낸 색은 **기록 줄에 남는다** (#79) — 다음 연습이 그것을 자로 쓴다(`askedOrder`).
     ⚠ **뜻 자일 때만** 적는다 (#53: 글자 자는 색을 못 낸다). 못 잰 자로 덮으면 약한 순서가 거짓이 된다.
     ⚠ 성적표가 아니다 — 남는 것은 **마지막 색 하나**고, 요약(`prac.res`)은 여전히 세션에만 산다. */
  if(r&&r.how==="뜻"&&isAskedId(qid)){
    const k=(DOC.asked||[]).findIndex(a=>a.id===qid);
    if(k>=0){DOC.asked=DOC.asked.slice();
      DOC.asked[k]=Object.assign({},DOC.asked[k],{practiceColor:r.c,practicedAt:now()});askedDirty=true}
  }
  if(t&&!qv)post("embedDraft",{slot:"answer",kind:"query",text:t});
  return r;
}
/* 요약 — **답한 문항만** 센다. 안 답하고 넘긴 것을 빨강에 넣으면 「몇 개 틀렸나」가 부풀려진다.
   `red` = 빨강이던 질문 id, **물어본 순서 그대로** (채우기가 그 순서를 이어받는다). */
function practiceSummary(){
  const res=(prac&&prac.res)||{},out={n:0,g:0,a:0,r:0,red:[]};
  ((prac&&prac.ids)||[]).forEach(id=>{
    const v=res[id];if(!v)return;
    out.n++;out[v.c]++;
    if(v.c==="r")out.red.push(id);
  });
  return out;
}
/* 저장할 때 그 조각이 들 **질문 id 목록** — 이제 **DOM 이 아니라 상태에서 온다** (#53).
   ★ 예전에는 화면의 칩 목록(`#chips .chip.on`)을 되읽었다(`preChips`+`pickedChips`).
     고르는 UI 가 걷혔으니 되읽을 것이 없다 — 그리고 되읽지 않는 편이 옳다: 이 값은
     **사람이 짚은 자리**이지 화면 상태가 아니다.
   갈래 셋:
     ① 채우기 중(`fq`) — 사람이 「이 질문에 답을 쓴다」를 띠로 보고 있는 자리. 그 하나.
     ② 조각을 고쳐 쓰는 중(`cur`) — 예전 그대로. 고쳐 쓴다고 장부가 바뀌면 안 된다.
     ③ 그 밖 — 빈 배열. 받기(#40)가 앉히는 것과 같은 모양이고, 그래도 **면접 중 순위는 산다**
       (`escore` 가 내용만 보므로). 「연결된 질문이 없으면 순위가 떨어져요」라던 경고는
       #53 이 걷었다 — 이제 그 문장이 거짓이다. */
const saveChips=(cur,fq)=>fq?[fq]:(cur?(cur.questionIds||[]).slice():[]);
/* ⚠ **장부를 화면에 적던 둘(`itemMeta`·`paintLinked`)이 걷혔다** (승격 라운드, #61 A).
   v3 이 장부(`questionIds`)를 이 화면에서 통째로 걷었고([ADR 0005](docs/adr/0005-content-direct-only-drop-the-chip-index.md)
   의 화면 층 연장), 그 자리는 **가운데 우주의 별 이웃 점등**(`canvasPaintFrom`)이 든다 — 색이 뜻 유사도 등급이다.
   ⚠ **`saveChips` 는 안 죽었다.** 장부를 **쓰는** 자리(채우기·구멍 짚기·받기 승인)는 그대로다.
     걷힌 것은 그것을 **읽어 화면에 글자로 적던** 두 함수뿐이다. */
/* ⚠ **준비도 한 줄(#46)이 죽었다** (#74 C4). 「질문 N개 중 초록 몇」은 저장소 화면의
   어휘가 아니라 **연습의 것**이다(design.md §5) — 질문을 미리 쓰지 않기로 한 순간(ADR 0006)
   머리에 셀 것이 없다. 그 자리는 이제 비어 있고, 머리글은 아이콘 넷뿐이다. */
const esc=s=>(s||"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
/* ★ 머리글 아이콘 (#74 C4 · design.md §5: *"머리글 = 아이콘만"*).
   **인라인 SVG 뿐이다** — 이 화면은 `loadHTMLString(baseURL:nil)` 이라 아이콘 폰트도
   이미지도 못 부른다(채팅 UI 제약 ②). 이모지도 안 쓴다: 기기마다 다른 그림이 떠서
   「같은 뜻」이 안 된다.
   ⚠ **글자는 툴팁에 산다** — 버튼마다 `title` + `aria-label` 이 그 낱말을 든다.
   ⚠ `currentColor` 로 칠한다 — 색은 버튼(`.ico`)이 정하고 그림은 따라온다. */
const FILE_ICON_ASSETS={
  /* Material Icon Theme 5.38.1, pinned in docs/vendor/material-icon-theme.md. */
  claude:`<svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" viewBox="0 0 16 16"><g fill="#ff7043"><path d="m14.375 6.48.49.28v.209l-.14.489-5.937 1.397-.558-1.387zm0 0"/><path d="m12.155 2.373.683.143.182.224.173.535-.072.342-3.983 5.447L7.81 7.737l3.673-4.82z"/><path d="m8.719 1.522.419-.28.349.14.349.49-.957 5.748-.65-.441-.279-.769.49-4.33z"/><path d="m4.239 1.614.43-.55L4.95 1l.558.081.275.216 2.004 4.442.724 2.11-.848.471-3.231-5.864z"/><path d="m2.154 4.665-.14-.56.42-.488.488.07h.14l2.933 2.165.908.698 1.257.978-.698 1.187-.629-.489-.419-.419-4.05-2.863z"/><path d="M1.316 8.296 1 7.946v-.31l.316-.108 3.562.21 3.491.279-.113.695-6.66-.346z"/><path d="M3.411 11.931h-.698l-.278-.32v-.382l1.186-.838 4.82-3.068.487.833z"/><path d="m4.738 13.883-.28.07-.418-.21.07-.35 4.12-5.446.558.768-3.072 4.05z"/><path d="m8.23 14.581-.21.28-.419.14-.349-.28-.21-.42L8.09 8.646l.629.07z"/><path d="M11.791 13.045v.558l-.07.21-.279.14-.489-.066-3.356-4.996 1.331-1.014 1.117 2.025.105.733z"/><path d="m13.398 12.207.07.349-.21.279-.21-.07-1.187-.838-1.815-1.606-1.397-.978.419-1.326.698.419.42.768z"/><path d="m12.49 8.645 1.746.14.419.28.279.418v.302l-.768.327-3.911-.978-1.606-.07.419-1.466 1.117.838z"/></g></svg>`,
  agents:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><path fill="#ff5252" d="M2.636 24H6v-8H2.636a.63.63 0 0 0-.636.625v6.75a.63.63 0 0 0 .636.625M26 16v8h3.364c.351 0 .636-.355.636-.7v-6.675a.63.63 0 0 0-.636-.625zM17.417 6H14.69a.63.63 0 0 0-.636.625V12H8.69a.63.63 0 0 0-.636.625L8 25.375c0 .345.305.625.637.625h14.727a.63.63 0 0 0 .636-.625v-12.75a.63.63 0 0 0-.636-.625h-5.31V6.625A.63.63 0 0 0 17.416 6m-5.363 8c1.781 0 2.674 2.154 1.414 3.414s-3.414.368-3.414-1.414a2 2 0 0 1 2-2M22 24H10v-2h12zm-1.946-10c1.781 0 2.674 2.154 1.414 3.414s-3.414.368-3.414-1.414a2 2 0 0 1 2-2"/></svg>`,
  gitignore:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><path fill="#e64a19" d="M13.172 2.828 11.78 4.22l1.91 1.91 2 2A2.986 2.986 0 0 1 20 10.81a3.25 3.25 0 0 1-.31 1.31l2.06 2a2.68 2.68 0 0 1 3.37.57 2.86 2.86 0 0 1 .88 2.117 3.02 3.02 0 0 1-.856 2.109A2.9 2.9 0 0 1 23 19.81a2.93 2.93 0 0 1-2.13-.87 2.694 2.694 0 0 1-.56-3.38l-2-2.06a3 3 0 0 1-.31.12V20a3 3 0 0 1 1.44 1.09 2.92 2.92 0 0 1 .56 1.72 2.88 2.88 0 0 1-.878 2.128 2.98 2.98 0 0 1-2.048.871 2.981 2.981 0 0 1-2.514-4.719A3 3 0 0 1 16 20v-6.38a2.96 2.96 0 0 1-1.44-1.09 2.9 2.9 0 0 1-.56-1.72 2.9 2.9 0 0 1 .31-1.31l-3.9-3.9-7.579 7.572a4 4 0 0 0-.001 5.658l10.342 10.342a4 4 0 0 0 5.656 0l10.344-10.344a4 4 0 0 0 0-5.656L18.828 2.828a4 4 0 0 0-5.656 0"/></svg>`,
  markdown:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><path fill="#42a5f5" d="m14 10-4 3.5L6 10H4v12h4v-6l2 2 2-2v6h4V10zm12 6v-6h-4v6h-4l6 8 6-8z"/></svg>`,
  swift:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#ff6e40" d="M17.087 19.721c-2.36 1.36-5.59 1.5-8.86.1a13.8 13.8 0 0 1-6.23-5.32c.67.55 1.46 1 2.3 1.4 3.37 1.57 6.73 1.46 9.1 0-3.37-2.59-6.24-5.96-8.37-8.71-.45-.45-.78-1.01-1.12-1.51 8.28 6.05 7.92 7.59 2.41-1.01 4.89 4.94 9.43 7.74 9.43 7.74.16.09.25.16.36.22.1-.25.19-.51.26-.78.79-2.85-.11-6.12-2.08-8.81 4.55 2.75 7.25 7.91 6.12 12.24-.03.11-.06.22-.05.39 2.24 2.83 1.64 5.78 1.35 5.22-1.21-2.39-3.48-1.65-4.62-1.17"/></svg>`,
  shell:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path fill="#ff7043" d="M2 2a1 1 0 0 0-1 1v10c0 .554.446 1 1 1h12c.554 0 1-.446 1-1V3a1 1 0 0 0-1-1zm0 3h12v8H2zm1 2 2 2-2 2 1 1 3-3-3-3zm5 3.5V12h5v-1.5z"/></svg>`,
  javascript:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path fill="#ffca28" d="M2 2v12h12V2zm6 6h1v4a1.003 1.003 0 0 1-1 1H7a1.003 1.003 0 0 1-1-1v-1h1v1h1zm3 0h2v1h-2v1h1a1.003 1.003 0 0 1 1 1v1a1.003 1.003 0 0 1-1 1h-2v-1h2v-1h-1a1.003 1.003 0 0 1-1-1V9a1.003 1.003 0 0 1 1-1"/></svg>`,
  typescript:`<svg xmlns="http://www.w3.org/2000/svg" xml:space="preserve" viewBox="0 0 16 16"><path fill="#0288d1" d="M2 2v12h12V2zm4 6h3v1H8v4H7V9H6zm5 0h2v1h-2v1h1a1.003 1.003 0 0 1 1 1v1a1.003 1.003 0 0 1-1 1h-2v-1h2v-1h-1a1.003 1.003 0 0 1-1-1V9a1.003 1.003 0 0 1 1-1"/></svg>`,
  python:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#0288d1" d="M9.86 2A2.86 2.86 0 0 0 7 4.86v1.68h4.29c.39 0 .71.57.71.96H4.86A2.86 2.86 0 0 0 2 10.36v3.781a2.86 2.86 0 0 0 2.86 2.86h1.18v-2.68a2.85 2.85 0 0 1 2.85-2.86h5.25c1.58 0 2.86-1.271 2.86-2.851V4.86A2.86 2.86 0 0 0 14.14 2zm-.72 1.61c.4 0 .72.12.72.71s-.32.891-.72.891c-.39 0-.71-.3-.71-.89s.32-.711.71-.711"/><path fill="#fdd835" d="M17.959 7v2.68a2.85 2.85 0 0 1-2.85 2.859H9.86A2.85 2.85 0 0 0 7 15.389v3.75a2.86 2.86 0 0 0 2.86 2.86h4.28A2.86 2.86 0 0 0 17 19.14v-1.68h-4.291c-.39 0-.709-.57-.709-.96h7.14A2.86 2.86 0 0 0 22 13.64V9.86A2.86 2.86 0 0 0 19.14 7zM8.32 11.513l-.004.004.038-.004zm6.54 7.276c.39 0 .71.3.71.89a.71.71 0 0 1-.71.71c-.4 0-.72-.12-.72-.71s.32-.89.72-.89"/></svg>`,
  json:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -960 960 960"><path fill="#f9a825" d="M560-160v-80h120q17 0 28.5-11.5T720-280v-80q0-38 22-69t58-44v-14q-36-13-58-44t-22-69v-80q0-17-11.5-28.5T680-720H560v-80h120q50 0 85 35t35 85v80q0 17 11.5 28.5T840-560h40v160h-40q-17 0-28.5 11.5T800-360v80q0 50-35 85t-85 35zm-280 0q-50 0-85-35t-35-85v-80q0-17-11.5-28.5T120-400H80v-160h40q17 0 28.5-11.5T160-600v-80q0-50 35-85t85-35h120v80H280q-17 0-28.5 11.5T240-680v80q0 38-22 69t-58 44v14q36 13 58 44t22 69v80q0 17 11.5 28.5T280-240h120v80z"/></svg>`,
  yaml:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#ff5252" d="M13 9h5.5L13 3.5zM6 2h8l6 6v12c0 1.1-.9 2-2 2H6c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2m12 16v-2H9v2zm-4-4v-2H6v2z"/></svg>`,
  pdf:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#ef5350" d="M13 9h5.5L13 3.5zM6 2h8l6 6v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2m4.93 10.44c.41.9.93 1.64 1.53 2.15l.41.32c-.87.16-2.07.44-3.34.93l-.11.04.5-1.04c.45-.87.78-1.66 1.01-2.4m6.48 3.81c.18-.18.27-.41.28-.66.03-.2-.02-.39-.12-.55-.29-.47-1.04-.69-2.28-.69l-1.29.07-.87-.58c-.63-.52-1.2-1.43-1.6-2.56l.04-.14c.33-1.33.64-2.94-.02-3.6a.85.85 0 0 0-.61-.24h-.24c-.37 0-.7.39-.79.77-.37 1.33-.15 2.06.22 3.27v.01c-.25.88-.57 1.9-1.08 2.93l-.96 1.8-.89.49c-1.2.75-1.77 1.59-1.88 2.12-.04.19-.02.36.05.54l.03.05.48.31.44.11c.81 0 1.73-.95 2.97-3.07l.18-.07c1.03-.33 2.31-.56 4.03-.75 1.03.51 2.24.74 3 .74.44 0 .74-.11.91-.3m-.41-.71.09.11c-.01.1-.04.11-.09.13h-.04l-.19.02c-.46 0-1.17-.19-1.9-.51.09-.1.13-.1.23-.1 1.4 0 1.8.25 1.9.35M7.83 17c-.65 1.19-1.24 1.85-1.69 2 .05-.38.5-1.04 1.21-1.69zm3.02-6.91c-.23-.9-.24-1.63-.07-2.05l.07-.12.15.05c.17.24.19.56.09 1.1l-.03.16-.16.82z"/></svg>`,
  image:`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path fill="#26a69a" d="M8.5 6h4l-4-4zM3.875 1H9.5l4 4v8.6c0 .773-.616 1.4-1.375 1.4h-8.25c-.76 0-1.375-.627-1.375-1.4V2.4c0-.777.612-1.4 1.375-1.4M4 13.6h8V8l-2.625 2.8L8 9.4zm1.25-7.7c-.76 0-1.375.627-1.375 1.4s.616 1.4 1.375 1.4c.76 0 1.375-.627 1.375-1.4S6.009 5.9 5.25 5.9"/></svg>`,
  text:`<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/><path fill="#afb42b" d="M19 5v9h-5v5H5V5zm0-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h10l6-6V5c0-1.1-.9-2-2-2m-7 11H7v-2h5zm5-4H7V8h10z"/></svg>`,
  default:`<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><path d="M0 0h24v24H0z"/><path fill="#42a5f5" d="M8 16h8v2H8zm0-4h8v2H8zm6-10H6c-1.1 0-2 .9-2 2v16c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8zm4 18H6V4h7v5h5z"/></svg>`
};
function workspaceFileIcon(path){
  const value=typeof path==="string"?path:"";
  const base=(value.replace(/[\\\\/]+$/g,"").split(/[\\\\/]/).pop()||"").toLowerCase();
  const named={"claude.md":"claude","claude.local.md":"claude","agents.md":"agents",".gitignore":"gitignore"};
  const exact=named[base];
  if(exact)return FILE_ICON_ASSETS[exact];
  const dot=base.lastIndexOf(".");
  const ext=dot>0?base.slice(dot):"";
  if(ext===".md"||ext===".markdown")return FILE_ICON_ASSETS.markdown;
  if(ext===".swift")return FILE_ICON_ASSETS.swift;
  if(ext===".sh"||ext===".bash"||ext===".zsh")return FILE_ICON_ASSETS.shell;
  if(ext===".js"||ext===".mjs"||ext===".cjs")return FILE_ICON_ASSETS.javascript;
  if(ext===".ts"||ext===".tsx")return FILE_ICON_ASSETS.typescript;
  if(ext===".py")return FILE_ICON_ASSETS.python;
  if(ext===".json")return FILE_ICON_ASSETS.json;
  if(ext===".yaml"||ext===".yml")return FILE_ICON_ASSETS.yaml;
  if(ext===".pdf")return FILE_ICON_ASSETS.pdf;
  if(ext===".png"||ext===".jpg"||ext===".jpeg"||ext===".gif"||ext===".webp"||ext===".svg"||ext===".bmp"||ext===".ico"||ext===".avif"||ext===".heic")return FILE_ICON_ASSETS.image;
  if(ext===".txt")return FILE_ICON_ASSETS.text;
  return FILE_ICON_ASSETS.default;
}
const ICO={
  live:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M4.5 3.2v9.6l7.6-4.8z" fill="currentColor"/></svg>`,
  practice:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><circle cx="8" cy="8" r="5.6" stroke="currentColor" stroke-width="1.5"/><circle cx="8" cy="8" r="1.7" fill="currentColor"/></svg>`,
  gear:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><circle cx="8" cy="8" r="2.3" stroke="currentColor" stroke-width="1.4"/><path d="M8 1.6v1.7M8 12.7v1.7M2.5 8H4.2M11.8 8h1.7M4.1 4.1l1.2 1.2M10.7 10.7l1.2 1.2M11.9 4.1l-1.2 1.2M5.3 10.7l-1.2 1.2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>`,
  close:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M4.2 4.2l7.6 7.6M11.8 4.2l-7.6 7.6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`,
  more:`<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><circle cx="3.5" cy="8" r="1.1"/><circle cx="8" cy="8" r="1.1"/><circle cx="12.5" cy="8" r="1.1"/></svg>`,
  plus:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M8 3.4v9.2M3.4 8h9.2" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`,
  back:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M12.6 8H3.8M7.3 3.9L3.4 8l3.9 4.1" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  file:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M4 1.8h5l3 3v9.4H4zM9 1.8v3h3" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M6 8h4M6 10.5h4" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>`,
  folder:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M1.8 4.2h4l1.2 1.4h7.2v6.2a1.8 1.8 0 0 1-1.8 1.8H3.6a1.8 1.8 0 0 1-1.8-1.8z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/></svg>`,
  folderPlus:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M1.8 4.2h4l1.2 1.4h7.2v6.2a1.8 1.8 0 0 1-1.8 1.8H3.6a1.8 1.8 0 0 1-1.8-1.8z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M8 7.6v3.5M6.25 9.35h3.5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>`,
  collapse:`<svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M5.5 2.5h8v8M2.5 5.5h8v8h-8zM4.5 9.5h4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
};
const app=document.getElementById("app");
/* ★ 창 크기를 정하는 **자리 하나** (#67 이 뽑아냈다).
   ⚠ 통로를 안 늘렸다 — 크기 옆에 `mode` 를 얹은 그 통로 그대로다(#18). Swift 는 이 이름으로
     ① 독 아이콘·창 층위(`live` 냐 아니냐) ② **자리 기억 칸**(`windowFrame.<이름>`)을 가른다.
   ★ **`canvas` 이름이 죽었다** (#67 재편). 뜻 지도가 홈의 한 칸이 되면서 그 화면만의 창
     크기도, `windowFrame.canvas` 라는 따로 기억하던 자리도 같이 죽었다 — 쌓기 창 하나가
     3단을 다 든다. 그래서 기본값이 980×660 에서 **1180×760** 으로 올라갔다.
     ⚠ 사람이 손으로 키워 둔 창은 그대로다 — Swift 가 기억한 자리를 먼저 본다(`applyMode`).
   ⚠ **부르는 자리는 `render()` 하나다** — 모드가 바뀔 때만. 홈 안의 화면 전환(설정·받기)은
     창 크기를 안 건드린다. */
function sizeWindow(){
  post("resizeWindow",mode==="live"?{w:520,h:380,mode:"live"}
    :mode==="practice"?{w:760,h:560,mode:"practice"}
    :{w:1180,h:760,mode:"stack"});
}

function render(){
  app.className=mode;
  /* ★ **창 밖으로 떨어뜨린 파일이 화면을 갈아엎지 않게** (#61 A, 왼쪽 칸 드롭의 짝).
     WebView 는 놓인 파일을 **그대로 연다** — `loadHTMLString(baseURL:nil)` 라 그 순간
     화면이 통째로 사라지고 돌아올 주소가 없다. 그래서 문서 전체에서 기본 동작을 막고,
     받는 자리(`bindDropTarget` 이 세운 과녁들)만 자기 손잡이로 먼저 처리한다.
     ⚠ **대입이지 `addEventListener` 가 아니다** — `tests/screen-load.mjs` 의 `document`
       스텁에는 그 메서드가 없다. 대입은 아무 데서나 안전하다. */
  document.ondragover=e=>e.preventDefault();
  document.ondrop=e=>e.preventDefault();
  /* ⚠ 통로를 안 늘렸다 — 크기 옆에 `mode` 를 얹었다. Swift 가 이걸로 독 아이콘·⌘Q 를 켜고 끈다 (#18).
     ★ 연습(#36)도 같은 자리로 간다. Swift 쪽은 `live` 냐 아니냐로만 갈리므로 껍데기는
       **쌓기와 같다**(불투명·일반 층위·독 아이콘 있음) — 숨을 이유가 없는 화면이다.
       자리는 모드마다 따로 기억되니 연습 창이 쌓기 창의 자리를 안 덮는다. */
  sizeWindow();
  /* ★ 정본이 아직이면 **여는 중**만 그린다 (`RECEIVED` 머리글). 창 크기·모드는 위에서 이미
     보냈으니 창 단추는 제때 켜진다 — 가리는 것은 그림 하나다. */
  if(mode==="stack"&&!RECEIVED){
    app.innerHTML=`<div id="top" class="drag hmtop"><span id="brand">Clonie</span></div>
      <div class="opening" role="status">저장소를 여는 중…</div>`;
    return;
  }
  /* 귀는 면접·연습에서만 산다 — 쌓는 동안 마이크·시스템 오디오를 물고 있을 이유가 없다.
     ⚠ **연습은 마이크만 연다.** 묻는 것이 앱이라 상대 목소리가 없고, 시스템 오디오를 열면
       화면 기록 권한을 괜히 묻는다. 여기서도 **통로를 안 늘렸다** — 기존 `startListening`
       에 어느 관을 열지를 얹었을 뿐이다(`resizeWindow` 가 `mode` 를 얹은 것과 같은 모양). */
  if(mode==="stack")post("stopListening");
  else post("startListening",{system:mode==="live"});
  mode==="live"?liveRender():mode==="practice"?practiceRender():stackRender();
}
/* ★ 모드를 바꾸는 **유일한 함수** (라운드 9 잠금). 다른 데서 `mode=` 를 직접 건드리지 않는다.
   내용은 흐려졌다 돌아오고, 창은 Swift 가 줄이며 바꾼다 — 그 두 개가 겹친 것이 전환 신호다.
   ⚠ **`mode` 는 200ms 뒤에 바뀐다.** 그 사이의 클릭은 `mode===next` 게이트를 전부 통과한다 —
     그래서 진행 중 자물쇠(`morphing`)가 따로 있다(아래). */
/* ★ 전환이 도는 중인가 (#66-4, `실측 2026-09-01`). 없을 때 면접→연습 연타로 `startListening`
   `{system:true}` 가 나가고 창이 520→760 을 두 번 춤췄다 — 연습의 선언(*시스템 오디오를 열면
   화면 기록 권한을 괜히 묻는다*)이 깨지는 자리다.
   ⚠ **먼저 누른 쪽이 이긴다.** 뒤 클릭을 큐에 쌓지 않는다 — 쌓으면 두 전환이 잇달아 돌아
     귀를 여닫는 왕복이 그대로 남는다. 사람은 도착한 화면에서 다시 누르면 된다. */
let morphing=false;
/* ★ **부작용을 세우기 전에 먼저 묻는 자리** (#66 리뷰 발견 ③). `goMode` 의 조기 반환은
   전환만 막았지 **호출부가 이미 돌려버린 부작용**은 못 되돌렸다 — morphing 중에 「쌓기로」를
   누르면 `stopPractice()` 가 연습을 지워 놓고 화면은 연습에 남았고, 「연습」을 누르면
   `startPractice()` 가 상태를 세워 놓고 화면은 쌓기에 남았다. 그러면 **「먼저 누른 쪽이
   이긴다」가 화면에서만 참이고 상태에서는 거짓**이다.
   ⚠ 판정은 한 곳(`goMode`)에 있어야 하므로 그 조건을 여기서 한 번만 쓴다 — 호출부가
     `mode`·`morphing` 을 직접 읽으면 판정이 둘이 된다. */
function canGoMode(next){return mode!==next&&!morphing}
function goMode(next){
  if(mode==="stack"&&next!=="stack"&&!leaveEditorAllowed(()=>goMode(next)))return;
  if(!canGoMode(next))return;
  /* ★ **기다리던 기록은 화면을 떠날 때 걷는다** (#79 리뷰 (c)2). 벡터는 몇 분 뒤에 올 수 있고
     그때 사람은 이미 다른 모드다 — 안 걷으면 그 옛 글자가 그제서야 기록에 적히고 저장까지 나간다.
     ⚠ `canGoMode` **뒤**다: 전환이 막힌 판(morphing)에서 걷으면 안 떠난 화면의 대기가 사라진다. */
  askLogPending=null;
  /* 면접을 끝내고 나갈 때만 옮긴다 — 면접 중에는 저장소를 안 건드린다 (#22) */
  if(mode==="live"&&next==="stack")commitHarvest();
  /* ★ **지난 면접을 안 들고 들어간다** (#66-5, `실측 2026-09-01`: 2회차에 1회차의 전사·카드가
     그대로 살아 있었다). 전 판은 harvest 계열만 비웠다 — 그런데 화면이 드는 것은 전사(`hist`
     `CUR`)와 검색어(`heardV`·`mineV`), 그리고 그것으로 고른 카드(`ORD`·`opened`·`manual`)다.
     ⚠ **나올 때가 아니라 들어갈 때 비운다.** 끝낼 때 비우면 요약·수확이 그 값을 못 읽는다. */
  if(next==="live"){
    harvest=[];harvestPending=[];askedPending=[];notice=null;
    /* 2026-09-07 합의: 준비 중 보던 항성을 자동 승계하지 않는다. 실사용은 전체 저장소로 시작한다. */
    LIVE_SUN=liveScopeDefault(liveTree(),LAST_SUN);
    resetLive();
  }
  /* 연습도 쌓기의 띠를 안 들고 들어간다 (#36). */
  if(next==="practice")notice=null;
  app.classList.add("morph");
  morphing=true;
  setTimeout(()=>{morphing=false;mode=next;render();app.classList.remove("morph")},200);
}
/* 면접 화면이 드는 것 전부를 첫 상태로. **한 자리에 모은다** — 흩어 두면 새 칸이 생길 때
   한 곳만 고쳐지고 그 칸이 다음 면접까지 산다(그것이 #66-5 의 모양이었다). */
function resetLive(){
  hist=[];curWho="them";trouble=null;
  CUR.them.c="";CUR.them.v="";CUR.me.c="";CUR.me.v="";
  heardV="";mineV="";opened=null;manual=false;
  ORD.top=null;ORD.list=[];ORD.score={};ORD.color={};ORD.passage={};ORD.how="글자";
}
/* ★ **확인 상자 한 벌** (#65 ②). 이 화면엔 네이티브 confirm 이 **없고**(`WKUIDelegate` 0건),
   있어도 못 쓴다 — 네이티브 창은 **화면 공유에 잡힌다.** 그래서 확인은 화면 안에서 난다.
   면접 「끝내기」가 갖고 있던 모양을 그대로 뽑은 것이고, 글자만 인자로 받는다.
   ⚠ **손잡이 이름은 한 벌이다**(`cyes`·`cno`). 두 벌이 되면 갈리는 날 한쪽만 고쳐진다.
   ⚠ **여는 자리와 거는 자리를 갈랐다** — 거는 것은 화면마다 한 번(`bindConfirm`),
     여는 것은 누르는 버튼마다(`openConfirm`)다. */
function confirmBox(q,yes,no){
  return `<div id="confirm"><div id="cbox"><p id="confirm-q">${esc(q)}</p>
      <div class="crow"><button class="gbtn nodrag" id="cno">${esc(no)}</button>
        <button class="gbtn p nodrag" id="cyes">${esc(yes)}</button></div></div></div>`;
}
function setConfirmCopy(q,yes,no){
  const p=document.getElementById("confirm-q"),y=document.getElementById("cyes"),n=document.getElementById("cno");
  if(p)p.textContent=q;if(y)y.textContent=yes;if(n)n.textContent=no;
}
function bindConfirm(onYes){
  const cf=document.getElementById("confirm");if(!cf)return;
  const y=document.getElementById("cyes"),n=document.getElementById("cno");
  if(n)n.onclick=()=>cf.classList.remove("on");
  if(y)y.onclick=()=>{cf.classList.remove("on");onYes()};
}
function openConfirm(){const cf=document.getElementById("confirm");if(cf)cf.classList.add("on")}
function liveRender(){
  app.innerHTML=`<div id="hist" class="drag"></div>
    <div id="cur" class="drag"><span id="curw" class="nodrag" title="눌러서 누가 말하는지 바꾼다">면접관</span>
      <div id="curbox"><div id="curtx" class="nodrag" spellcheck="false"
        data-ph="상대 질문이 여기 받아적힌다"></div></div></div>
    <div class="hsep"></div><div id="recs"></div><div id="trouble"></div>
    <div class="bottom"><span class="ld" title="듣는 중"></span>
      <button class="ibtn nodrag" id="lscope" title="오늘의 범위 — 누르면 다음 항성으로, 끝은 갤럭시"></button>
      <button class="gbtn nodrag" id="exit">끝내기</button>
      <span style="flex:1"></span>
      <button class="ibtn nodrag" id="x">✕</button></div>
    ${confirmBox("면접 모드를 끝낼까","끝낸다","계속한다")}`;
  const tx=document.getElementById("curtx");
  /* ★ 타이핑은 **브리지가 없을 때만** 열린다 (박선호 2026-08-28: *"채팅창처럼 입력이 가능하게 왜 해둔거야?"*).
     앱에서는 귀가 받아적는 자리라 사람이 칠 일이 없고, 오히려 **눌러서 포커스가 가면 전사 갱신이 멈춘다.**
     브라우저 단독에서는 이게 유일한 입력 수단이라 거기서만 연다 — `cue.html` 개발 동선이 이 길로 산다. */
  if(!bridged()){
    tx.setAttribute("contenteditable","plaintext-only");
    tx.oninput=()=>{const t=tx.textContent;CUR[curWho].c=t;CUR[curWho].v="";
      if(curWho==="them"){heardV=t;opened=null;manual=false;applyRank(true)}
      else{mineV=t;if(!manual)autoPick()}};
    document.getElementById("curw").onclick=()=>{curWho=curWho==="them"?"me":"them";paintCur()};
  }
  /* 나가는 길 하나 — 확인을 거쳐야 모드가 풀린다. 조각을 아무리 눌러도 모드는 안 바뀐다 */
  bindConfirm(()=>goMode("stack"));
  document.getElementById("exit").onclick=openConfirm;
  document.getElementById("x").onclick=()=>post("closeWindow");
  /* ★ 범위 칩 하나 — **면접 중에 바꿀 수 있는 유일한 자리**다 (#79 결재: *"켤 때 한 번 바꿀 수 있음"*).
     갤럭시 → 항성들 → 갤럭시 순환. ⚠ 범위가 바뀌면 보던 카드는 남의 항성 것일 수 있어서
     `opened`·`manual` 을 놓는다 — 안 놓으면 범위 밖 조각이 펼쳐진 채로 남는다. */
  const paintScope=()=>{const b=document.getElementById("lscope");
    if(b)b.textContent="범위: "+liveScopeName(liveTree(),LIVE_SUN)};
  document.getElementById("lscope").onclick=()=>{
    LIVE_SUN=liveScopeCycle(liveTree(),LIVE_SUN);
    opened=null;manual=false;
    paintScope();applyRank(true);
  };
  paintScope();
  paintCur();applyRank(true);
  if(trouble)onEarTrouble(trouble);
}
/* 지난 발화 두 줄 + 현재 발화. **확정 글자는 다시 안 그려도 같은 글자**고, 꼬리만 흐리다 */
function paintCur(){
  const h=document.getElementById("hist"),c=document.getElementById("cur"),tx=document.getElementById("curtx");
  if(!h||!tx)return;
  const cur=CUR[curWho];
  h.innerHTML=hist.slice(-2).map(u=>
    `<div class="hl"><span class="w">${u.who==="me"?"나":"면접관"}</span>${esc(u.text)}</div>`).join("");
  c.className="drag"+(curWho==="me"?" me":"");
  document.getElementById("curw").textContent=curWho==="me"?"나":"면접관";
  tx.dataset.ph=curWho==="me"?"답을 시작하면 하나가 펼쳐진다":"상대 질문이 여기 받아적힌다";
  if(document.activeElement===tx)return;   /* 손으로 치는 중엔 안 건드린다 — 커서가 날아간다 */
  tx.innerHTML=esc(cur.c)+(cur.v?`<span class="vol">${cur.c?" ":""}${esc(cur.v)}</span>`:"");
  const box=document.getElementById("curbox");if(box)box.scrollTop=box.scrollHeight;
}
/* 한 발화가 끝났다 — **그 관의** 현재 줄을 지난 줄로 밀어 올린다 */
function flushCur(who){
  const w=who||curWho,cur=CUR[w];if(!cur)return;
  const t=(cur.c+" "+cur.v).trim();
  if(t){hist.push({who:w,text:t});if(hist.length>6)hist=hist.slice(-6)}
  cur.c="";cur.v="";paintCur();
}
/* ★ 라운드 8 Q2-(다) — 계산은 어절마다, **재배열은 1위가 바뀔 때만.**
   `force` 는 발화가 끝났거나 화면을 새로 지을 때. 그때만 점수 표기가 새로 붙는다. */
function applyRank(force){
  /* ★ 되먹임 판정을 **여기서** 흘려보낸다 (블로커 F3). 순위를 다시 매기는 바로 그 자리라
     harvest 가 화면과 **같은 자(QVEC·VEC)** 를 쓴다 — 두 자리로 나누면 화면은 초록인데
     저장소는 구멍으로 주운 상태가 다시 생긴다. */
  resolveHarvest();
  /* ★ **범위는 여기서만 걸린다** (#73 Q20). 수확 판정(`resolveHarvest`)은 위에서 이미
     흘러갔고 그것은 **갤럭시로 잰다** — 범위 안에서 빨강이라도 다른 항성이 답하면
     「저장소가 못 덮는 질문」이 아니다. */
  const r=rank(heardV,undefined,undefined,liveScopeIds(liveTree(),LIVE_SUN)),ids=r.map(x=>x.i);
  /* 색을 점수와 **같이** 받아 둔다 — 여기서 다시 재면 어느 눈금인지 또 물어야 한다 (#34) */
  const oldPassage=ORD.passage||{};
  ORD.score={};ORD.color={};ORD.passage={};
  r.forEach(x=>{ORD.score[x.i]=x.s;ORD.color[x.i]=x.c;ORD.passage[x.i]=x.passage||null});
  ORD.how=r.length?r[0].how:scorer(heardV,QVEC,VEC);
  if(!ids.length){ORD.top=null;ORD.list=[];paintRecs();return}
  const first=ORD.top===null,swapped=!first&&ids[0]!==ORD.top;
  if(first||swapped){ORD.top=ids[0];ORD.list=ids.slice(0,3)}
  else{ORD.list=[ORD.top].concat(ids.filter(i=>i!==ORD.top)).slice(0,3)}
  /* 첫 그림은 안 흐린다 — 없던 것이 생기는 것은 교체가 아니다 */
  const passageChanged=ORD.list.some(i=>(oldPassage[i]||null)!==(ORD.passage[i]||null));
  if(first||swapped||force||passageChanged)paintRecs(swapped&&!force);
  else paintDots();   /* 카드는 그대로 두고 색만 따라온다 */
}
/* 내 말이 시작되면 맞는 조각을 편다 (라운드 8 Q3-나). **수동 클릭이 이걸 덮는다** */
function autoPick(){
  if(!mineV.trim()||!ORD.list.length)return;
  let best=null,bs=.02;
  ORD.list.forEach(i=>{const p=DOC.fragments[i];if(!p)return;
    const sc=Math.max(sim(mineV,p.title),sim(mineV,p.body||""));if(sc>bs){bs=sc;best=i}});
  if(best!==null&&best!==opened){opened=best;paintRecs()}
}
/* ★ 색만 따로 칠한다 — **재배열과 독립**이다 (#20 인수 조건 3).
   글자·순서는 1위가 바뀔 때만 갈아끼우지만(라운드 8 Q2-다), 색은 어절마다 따라온다.
   그래야 「지금 이 후보가 얼마나 위험한가」가 실시간으로 보이면서도 카드는 안 움직인다. */
function paintDots(){
  const box=document.getElementById("recs");if(!box||box.dataset.n!=="3")return;
  [...box.children].forEach((el,k)=>{
    const i=ORD.list[k],d=el.querySelector(".dot");
    if(i===undefined||!d)return;
    d.className="dot "+(ORD.color[i]||"r");
  });
}
/* 카드 셋은 **한 번만 짓고 내용만 갈아끼운다** — 매 어절 다시 지으면 화면이 끊긴다 */
function paintRecs(fade){
  const box=document.getElementById("recs");if(!box)return;
  if(!ORD.list.length){
    box.innerHTML=`<div class="empty">${heardV.trim()?"추천할 답변이 없어요":"질문을 기다리는 중…"}</div>`;
    box.dataset.n="0";return}
  if(box.dataset.n!=="3"){
    box.innerHTML=[0,1,2].map(k=>`<div class="rec" data-k="${k}"><div class="in">
      <div class="rt"></div><div class="rs"></div><div class="rb"></div></div><span class="rn">${k+1}</span></div>`).join("");
    box.dataset.n="3";
    box.querySelectorAll(".rec").forEach(el=>el.onclick=()=>{
      const i=+el.dataset.i;if(isNaN(i))return;manual=true;opened=(opened===i?null:i);paintRecs()});
  }
  paintDots();
  const fill=()=>{[...box.children].forEach((el,k)=>{
    const i=ORD.list[k],p=DOC.fragments[i];
    if(i===undefined||!p){el.style.display="none";return}
    const sc=ORD.score[i];
    el.style.display="";el.dataset.i=i;
    el.classList.toggle("open",opened===i);
    el.classList.toggle("dim",opened!==null&&opened!==i);
    el.classList.toggle("lead",k===0);
    el.querySelector(".rt").textContent=p.title;
    /* ★ **유사도 숫자를 사람에게 안 보인다** (#61 E, 박선호). 면접 중에 읽을 것은
       「이 카드가 준비된 답인가」이고 그건 **점**이 든다 — 0.884 는 사람이 아니라
       우리가 자를 검증할 때 보는 수다. 그래서 QA 노출 게이트에서만 붙인다.
       ⚠ 점(신호등)은 그대로다. 숨긴 것은 숫자 하나뿐이고 뜻은 안 사라졌다. */
    el.querySelector(".rs").innerHTML=`<span class="dot ${ORD.color[i]||"r"}"></span>`
      +((sc===undefined||!QAVIS)?"":" · "+sc.toFixed(3));
    const hit=ORD.passage&&ORD.passage[i];
    el.querySelector(".rb").textContent=(hit&&hit.sourceText)||p.body||"";
  })};
  if(!fade){ORD.seq=(ORD.seq||0)+1;fill();[...box.children].forEach(el=>el.classList.remove("fade"));return}
  /* 교체는 크로스페이드로. ⚠ 앞의 페이드가 아직 안 끝났으면 그것을 버린다 — 안 그러면 흐린 채로 굳는다 */
  const mine=ORD.seq=(ORD.seq||0)+1,slots=[...box.children];
  slots.forEach(el=>el.classList.add("fade"));
  setTimeout(()=>{if(mine!==ORD.seq)return;fill();slots.forEach(el=>el.classList.remove("fade"))},240);
}
/* ★ 연습 화면 (#36). **면접 화면의 골격을 그대로 쓴다** — 위 막대 · 한 칸짜리 답 · 신호등.
   다른 것은 큰 글씨가 「상대가 한 말」이 아니라 **앱이 묻는 질문**이라는 것뿐이다.
   ⚠ 이 함수는 **판정선 검사의 진입점**이다 (`tests/check_interview_offline.py` 의 ROOTS) —
     이름을 바꾸면 연습이 통째로 검사 밖에 남으므로 거기 목록도 같이 고쳐라. */
function practiceRender(){
  const qid=practiceQid();
  if(!qid)return practiceSummaryRender();
  /* ⚠ **`practiceGaps()` 가 아니다** — 그건 칩만 세어서, 받기가 막 앉힌 답을 「없다」고
     말한다(`practiceUnprepared` 머리글). 순서를 정하는 자리(`startPractice`)는 그대로
     `practiceGaps()` 다: 거기서 세는 것은 **칩이 빈 질문**이고 그건 여전히 참인 사실이다. */
  const q=DOC.questions.find(x=>x.id===qid)||askedById(qid)||{text:""},
        hole=practiceUnprepared(qid,DOC.fragments,VEC);
  /* ★ 기록 줄이면 **어디서 온 물음인지와 그때의 색**을 붙인다 (#79) — 「왜 이걸 또 묻나」의 답이다.
     ⚠ 색은 다시 재지 않는다. 여기 뜨는 점은 **그때** `rank()` 가 낸 것이다. */
  const A=askedById(qid);
  const src=A?`<span class="foot">${A.source==="interview"?"면접에서 들은 질문":"저장소에서 찾은 질문"} · ${
      String(A.at||"").slice(5,10).replace("-","/")}${A.color?` · <span class="dot ${A.color}"></span>그때 ${
      A.color==="g"?"초록":A.color==="a"?"주황":"빨강"}`:""}</span>`:"";
  app.innerHTML=`<div id="top" class="drag"><span id="brand">Clonie</span>
      <span id="stat">연습 · ${prac.k+1}/${prac.ids.length}</span><span style="flex:1"></span>
      <button class="gbtn nodrag" id="pend">끝내기</button>
      <button class="ibtn nodrag" id="x">✕</button></div>
    <div id="pr">
      <div><span class="fl">앱이 묻는다 · 소리 내어 답한다${
        hole?' · <span style="color:var(--warn)">이 질문엔 준비된 답변이 없다</span>':""}</span>
        <div class="pq">${esc(q.text)}</div>${src}</div>
      <div><span class="fl">내 답 · ${bridged()?"말하면 여기에 표시돼요":"직접 입력"}</span>
        <div id="pans" spellcheck="false" data-ph="${
          bridged()?"소리 내어 답하면 여기 받아적힌다":"여기에 답을 친다"}"></div></div>
      <div id="pscore"></div>
      <div class="prow"><button class="gbtn p" id="pgrade">채점</button>
        <button class="gbtn" id="pnext">다음 질문</button>
        <span style="flex:1"></span>
        <span class="foot">답변은 이 Mac에서만 처리돼요.</span></div>
      <div class="pn">준비한 답변과 얼마나 비슷한지 봅니다 — 정답을 채점하는 기능은 아니에요.</div>
    </div>`;
  const a=document.getElementById("pans");
  /* ★ 타이핑은 **브리지가 없을 때만** 열린다 — `liveRender` 와 같은 규율·같은 이유:
     앱에서는 귀가 받아적는 자리라 사람이 칠 일이 없고, 눌러서 포커스가 가면 갱신이 멈춘다.
     브라우저 단독에서는 이것이 유일한 입력 수단이라 **연습 로직 전체가 이 길로 돈다.** */
  if(!bridged()){
    a.setAttribute("contenteditable","plaintext-only");
    a.oninput=()=>{prac.head=a.textContent;prac.headq=a.textContent;prac.cur="";prac.vol="";prac.curq=""};
  }
  document.getElementById("pgrade").onclick=()=>{gradePractice();paintPractice()};
  /* 넘기기 전에 **아직 안 매겼으면 매긴다** — 안 그러면 요약에서 그 문항이 통째로 빠진다 */
  document.getElementById("pnext").onclick=()=>{
    if(!prac.res[qid])gradePractice();
    nextPractice();practiceRender()};
  document.getElementById("pend").onclick=()=>{
    if(!prac.res[qid])gradePractice();
    prac.done=true;practiceRender()};
  document.getElementById("x").onclick=()=>post("closeWindow");
  paintPractice();
}
/* 답과 채점만 **제자리에서** 고쳐 쓴다. ⚠ **다시 그리지 않는다** — 브라우저 단독에서는 `#pans`
   가 사람이 치고 있는 칸이고 통째로 갈아끼우면 그 글자와 커서가 날아간다
   (`paintCur`·`paintNotice`·`paintReady` 가 같은 이유로 같은 모양을 쓴다). */
function paintPractice(){
  if(!prac)return;
  const a=document.getElementById("pans");
  if(a&&document.activeElement!==a){
    a.innerHTML=esc(practiceHeard())
      +(prac.vol?`<span class="vol">${practiceHeard()?" ":""}${esc(prac.vol)}</span>`:"");
    /* ★ **자란 답을 따라 내려간다 — 답 칸 안에서만** (#66-8 재수리). `#pans` 가 상한을 갖고
       스스로 구르므로(그 CSS 머리글) 여기서 미는 것도 그 칸이다. `#pr` 을 밀던 전 판은
       문항까지 같이 밀어 올렸다. */
    a.scrollTop=a.scrollHeight;
  }
  const box=document.getElementById("pscore");if(!box)return;
  const qid=practiceQid(),r=qid?prac.res[qid]:null;
  if(!r){box.innerHTML="";return}
  box.innerHTML=`<div class="pres ${r.c}"><div><span class="dot ${r.c}"></span>${
      r.prepared?esc(r.hitTitle)+" · "+r.s.toFixed(3)
                :"준비한 답변이 없어요 — 연습이 끝나면 채울 수 있어요."}</div>`
    +(r.prepared&&!r.onTarget
      ?`<div class="pn" style="margin-top:6px">가장 비슷한 답변은 ${esc(r.topTitle)}입니다.</div>`:"")
    +`</div>`;
}
/* 요약 한 장 — 몇 문항 중 몇이 초록이었나, 그리고 **빨강이 어디로 이어지나** (#35). */
function practiceSummaryRender(){
  /* ⚠ **귀를 여기서 끈다.** 요약은 읽는 화면이라 답할 것이 없는데, `render()` 는 모드가 바뀔
     때만 불리므로(요약은 같은 모드다) 여기서 안 끄면 **마이크를 문 채로 요약을 읽게 된다.**
     `stopEars` 는 몇 번 불려도 안전하다(그 함수 머리글). */
  post("stopListening");
  const s=practiceSummary(),ids=(prac&&prac.ids)||[],res=(prac&&prac.res)||{};
  /* 빨강 중 **답이 아예 없는 것**을 따로 센다 — 「고쳐 쓸 것」과 갈려야 그 줄이 참이다.
     ⚠ **버튼이 아니라 문장이다** (#74 C5): 채우기 흐름이 죽어서 데려갈 자리가 없다. */
  const redGaps=s.red.filter(id=>practiceGaps().some(q=>q.id===id));
  app.innerHTML=`<div id="top" class="drag"><span id="brand">Clonie</span>
      <span id="stat">연습 끝</span><span style="flex:1"></span>
      <button class="ibtn nodrag" id="x">✕</button></div>
    <div id="pr">
      <div class="pq">${s.n}문항 중 ${s.g}개가 초록이었다</div>
      <div class="pn">주황 ${s.a} · 빨강 ${s.r}${
        s.red.length>redGaps.length?` · 빨강 중 ${s.red.length-redGaps.length}개는 답변이 이미 있다(고쳐 쓸 것)`:""}</div>
      <div>${ids.map(id=>{const v=res[id];return `<div class="sumrow"><span class="dot${
        v?" "+v.c:""}"></span><span>${esc(qtext(id))}</span>${
        v?"":'<span class="pn">· 안 답했다</span>'}</div>`}).join("")}</div>
      <div class="prow" style="margin-top:6px">
        <button class="gbtn" id="pback">저장소로</button>
        <span style="flex:1"></span><span class="foot">답변 전문은 저장하지 않아요. 입력 기록에는 마지막 연습 결과와 시각이 남아요.</span></div>
    </div>`;
  document.getElementById("x").onclick=()=>post("closeWindow");
  /* ⚠ **부작용 앞에 게이트가 선다** (#66 리뷰 발견 ③) — `stopPractice()` 가 먼저 돌면
     전환이 거부됐을 때 연습만 지워지고 화면은 요약에 남는다. */
  document.getElementById("pback").onclick=()=>{
    if(!canGoMode("stack"))return;
    stopPractice();goMode("stack")};
}

/* ★ 쌓기 홈 — **이 앱의 첫 얼굴이다** (v3, 박선호 확정 설계 2026-08-31 · 승격 라운드 #61 A).
   ★ **v4 = 3단이다** (#67 재편, 레퍼런스 = 옵시디언. 박선호 2026-09-02: *"저장소 모드 ui 구성도
     왼쪽 패널 중앙에 노드 기반 시각화, 그리고 오른쪽 패널? 옵시디언 ui를 어느정도 래퍼런스?"*):
     **왼쪽** 조각+구멍 목록(거르개 딸림) · **가운데** 뜻 지도 · **오른쪽** 고른 조각의 편집기.
     ⚠ 「확대」는 모드 전환이 아니라 **경계면을 끌어 양쪽을 접는 것**이다 — 그러면 가운데가
       `flex:1` 로 커진다. 그래서 [지도] 버튼도 `stackView==="canvas"` 도 같이 죽었다.

   ★ **v3 이 목업에서 정식으로 올라오며 달라진 것 셋** (#61 A):
     ① 해시 게이트(`MOCK`)가 걷혔다 — 이 함수가 곧 그 화면이다. 목업 스트립(볼트/씨앗/빈 판
        스위처)과 씨앗 판(`MAPSEED`)도 같이 걷혔다: 그릴 판이 언제나 **지금 볼트** 하나다.
     ② **넣는 문이 왼쪽 칸으로 내려왔다** (그릴 Q5) — 위 「새 조각」 · 아래 「파일 올리기」 ·
        칸에 **끌어다 놓으면** 받기 화면. 헤더 오른쪽은 설정·✕ 둘뿐이다.
     ③ 목업이 안 들고 있던 **제품 동선이 전부 붙었다** — 저장·지우기·채우기 흐름(#35)·
        알림 띠(#32)·볼트 사고 띠(F1)·수확 질문 정돈(#47)·구멍 ✕(#22).

   ⚠ **자를 새로 안 만들었다.** 재는 것은 `escore`(내용 직접) 하나이고 문턱도 이미 있는
     `SIM_A` 다. 색을 내는 것은 `eris` 하나뿐이고 연습은 `practiceReadiness` 로 간다 — 그 둘은
     같은 코사인·같은 초록선을 물고 있어서, 이 화면의 초록과 굵은 선은 **한 자의 두 얼굴**이다.
   ⚠ **초록 칩(`.ltag`)이 이 화면엔 없다** — 장부를 화면에서 걷은 것이 v3 의 ②다
     ([ADR 0005](docs/adr/0005-content-direct-only-drop-the-chip-index.md) 의 화면 층 연장).
   ⚠ 이 이름은 **판정선 검사의 선언된 경계**다 (`tests/check_interview_offline.py` 의 `BOUNDARY`) —
     바꾸면 거기 목록도 같이 고쳐라. 여기 아래로 붙는 것은 면접 모드로 안 세어진다. */
function stackRender(){
  vaultMenuClose(false);
  if(!VAULT_CONNECTED)return folderStartRender();
  /* ★ 수확 질문 정돈 (#47) — **이 자리가 전부다.** 여기(판정선의 선언된 경계) 아래에서만
     `tidyQuestion` 통로가 열린다. 여러 번 불려도 안전하다(`pumpTidy` 가 줄을 본다). */
  pumpTidy();
  /* ★ **설정을 떠나면 키를 도로 놔준다** (2026-08-31 설정 통합). 녹화 중에 「쌓기로」를 누르면
     `recKey` 가 `preventDefault` 를 계속 물어 **글 쓰는 키가 통째로 죽는다.** 녹화가 설정
     화면 안에서만 사는 것을 여기 한 줄이 보증한다 — 화면마다 걷는 것보다 자리가 하나다. */
  if(stackView!=="settings"){RECSLOT=null;RECMOD=null;RECCLASH=null;document.onkeydown=null}
  if(stackView==="settings")return settingsRender();
  if(stackView==="ingest")return ingestRender();
  const cur=sel!==null?DOC.fragments[sel]:null;
  /* ★ 머리글 = **아이콘만** (#74 C4 · design.md §5: *"글자는 툴팁에"*).
     ▶ 면접 · ◎ 연습 · ⚙ 설정 · ✕ 닫기. 전부 **인라인 SVG** 다 — 이 화면은
     `loadHTMLString(baseURL:nil)` 이라 바깥 자산을 하나도 못 부른다(채팅 UI 제약 ②).
     ⚠ **아이콘 폰트도 이모지도 안 쓴다**: 폰트는 자산이라 못 부르고, 이모지는 기기마다
       다른 그림이 떠서 「같은 뜻」이 안 된다.
     ⚠ **준비도 줄이 죽었다** (#74 C4) — 셀 질문이 없다. 머리에 남는 것은 동사 넷뿐이다. */
  app.innerHTML=`<div id="top" class="drag hmtop">${explorerToggleButton()}<span id="brand">Clonie</span><span id="indexstate" style="font-size:11px;color:var(--t3)">${esc(indexStateText())}</span>
      <div class="hmmid nodrag"><button class="ibtn ico act" id="golive" title="면접" aria-label="면접">${ICO.live}</button>
        <button class="ibtn ico" id="gopractice" title="연습" aria-label="연습">${ICO.practice}</button></div>
      <span style="flex:1"></span>
      <button class="ibtn ico nodrag" id="gear" title="설정" aria-label="설정">${ICO.gear}</button>
      <button class="ibtn ico nodrag" id="x" title="닫기" aria-label="닫기">${ICO.close}</button></div>
    <div id="stacknotices" role="status">${notice?`<div class="wb" id="nb">${esc(notice)}</div>`:""}</div>
    <div id="cols" class="${PANE.r?"document-open":""}">${explorerPane()}
    ${canvasPane()}
    <button class="rzr" id="rzr" data-zip="${PANE.r?0:1}"
        title="끌어서 폭을 바꿔요 — 좁히면 접혀요"></button>
    <div id="right"${PANE.r?"":' class="zip"'} style="width:${PANE.r}px">${editPanel(cur)}</div></div>`;
  bindExplorerPane();
  /* ★ 가운데 칸을 세운다 — **홈을 그릴 때마다 한 번**이다. `canvasMount` 가 SVG 알맹이를
     짓고 그 뒤로는 속성만 바뀐다(그 함수 머리글). 배치(`CANV`)는 서명이 같으면 살아 있어서
     사람이 끌어 둔 위상이 저장 한 번에 안 날아간다. */
  canvasBindPane();
  bindResizer("rzr","right","r");
  document.getElementById("golive").onclick=()=>goMode("live");
  /* 연습으로 가는 문 (#36). ⚠ **여는 데 실패하면 모드를 안 바꾼다** — 질문이 0개면
     빈 화면으로 들어가는 대신 여기 띠 한 줄로 말한다.
     ★ **새 볼트에서 0개가 이제 기본이다** (#74 C5) — 씨앗 질문을 안 심으므로 「예상 질문이
       없다」가 정직한 첫 답이고, 질문은 면접에서 수확될 때 생긴다.
     ⚠ **전환이 거부될 상황이면 `startPractice` 도 안 돈다** (#66 리뷰 발견 ③). */
  document.getElementById("gopractice").onclick=()=>{
    if(!leaveEditorAllowed())return;
    if(!canGoMode("practice"))return;
    if(startPractice())goMode("practice");else stackRender()};
  /* ★ 톱니가 여는 것이 **프론트 설정**이다 (#61 C). */
  document.getElementById("gear").onclick=openSettingsScreen;
  document.getElementById("x").onclick=()=>post("closeWindow");
  bindEditPanel(cur,saveChips(cur,null));
}
function explorerNewFolderParent(){
  const scoped=CANV&&CANV.focusPath;
  if(scoped&&VAULT_FOLDERS.includes(scoped))return scoped;
  const current=sel!==null?DOC.fragments[sel]:null,path=current&&PATHS[current.id]||"";
  const slash=path.lastIndexOf("/");
  return slash<0?"":path.slice(0,slash);
}
function explorerToggleButton(){
  return `<button class="ibtn ico nodrag" id="toggleexplorer" aria-controls="left" aria-expanded="${PANE.l>0}" aria-label="${PANE.l>0?"탐색기 접기":"탐색기 펼치기"}" title="${PANE.l>0?"탐색기 접기":"탐색기 펼치기"}"><svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><rect x="2" y="2.5" width="12" height="11" rx="1.5" stroke="currentColor"/><path d="M6 3v10" stroke="currentColor"/></svg></button>`;
}
function paintExplorerToggle(){
  const b=document.getElementById("toggleexplorer");if(!b)return;
  const label=PANE.l>0?"탐색기 접기":"탐색기 펼치기";
  b.setAttribute("aria-expanded",String(PANE.l>0));b.setAttribute("aria-label",label);b.title=label;
}
function explorerToggle(){paneApply("l",PANE.l>0?0:EXPLORER_WIDTH);canvasFit()}
function explorerExpandAll(){LZIP={};paintHomeList()}
function explorerCollapseAll(){
  const tree=vaultTree(DOC.fragments||[],PATHS||{},null,VAULT_FOLDERS,VAULT_ENTRIES);
  const next={};
  vaultRows(tree,{}).filter(r=>r.folder).forEach(r=>{next[r.path]=true});
  LZIP=next;paintHomeList();
}
function vaultNewDocument(parent){
  if(!leaveEditorAllowed(()=>vaultNewDocument(parent)))return;
  const base=parent||"";
  vaultDialog("새 문서",`<p class="foot">${esc(base||"저장소")}</p><input id="vname" aria-label="파일 이름" placeholder="파일 이름" value="">`,"만들기",()=>{
    let name=document.getElementById("vname").value.trim();if(!name)return;
    if(!/\.(md|markdown)$/i.test(name))name+=".md";
    vaultRequest({action:"createFile",path:[base,name].filter(Boolean).join("/")});
  });
}
function vaultNewFolder(parent){
  if(!leaveEditorAllowed(()=>vaultNewFolder(parent)))return;
  const base=parent||"";
  vaultDialog("새 폴더",'<input id="vname" aria-label="폴더 이름" placeholder="이름">',"만들기",()=>{
    const name=document.getElementById("vname").value.trim();if(!name)return;
    vaultRequest({action:"createFolder",path:[base,name].filter(Boolean).join("/")});
  });
}
function explorerPane(){
  const name=(SYS.vault||"").split("/").filter(Boolean).pop()||"저장소";
  return `<div id="left"${PANE.l?"":' class="zip"'} style="width:${PANE.l}px">
    <div id="lefttop"><div class="vaulttitle"><div class="vaultheading" id="vaultheading" title="${esc(SYS.vault)}">${esc(name)}</div>
      <button class="ibtn ico" id="vaultmenu" title="저장소 폴더 변경" aria-label="저장소 폴더 변경">${ICO.folder}</button></div>
      <div class="ltools" role="toolbar" aria-label="탐색기 도구">
        <button class="ibtn ico" id="nw" title="새 문서" aria-label="새 문서">${ICO.file}</button>
        <button class="ibtn ico" id="newfolder" title="새 폴더" aria-label="새 폴더">${ICO.folderPlus}</button>
        <button class="ibtn ico" id="collapseall" title="모두 접기" aria-label="모두 접기">${ICO.collapse}</button>
        <button class="ibtn ico" id="expandall" title="모두 펼치기" aria-label="모두 펼치기"><svg viewBox="0 0 16 16" fill="none" aria-hidden="true"><path d="M3 6l5-4 5 4M3 10l5 4 5-4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
        <button class="ibtn" id="vaultundo" aria-label="파일 작업 되돌리기" ${VAULT_LAST_OPERATION?"":"disabled"}>↶</button>
      </div>
      <div class="lrow"><input id="lfind" type="search" aria-label="파일 찾기" placeholder="파일 찾기" value="${esc(LFIND)}"></div>
      <span class="lhits" id="lhits"></span></div>
    <div id="leftlist" role="tree" aria-label="파일 탐색기"></div>

    </div><button class="rzr" id="rzl" data-zip="${PANE.l?0:1}" title="탐색기 너비 조절"></button>`;
}
function bindExplorerPane(){
  paintHomeList();bindResizer("rzl","left","l");bindExplorerRoot();
  document.getElementById("nw").onclick=()=>vaultNewDocument(explorerNewFolderParent());
  const nf=document.getElementById("newfolder");
  if(nf)nf.onclick=()=>vaultNewFolder(explorerNewFolderParent());
  const ca=document.getElementById("collapseall");
  if(ca)ca.onclick=explorerCollapseAll;
  const undo=document.getElementById("vaultundo");if(undo)undo.onclick=()=>{if(VAULT_LAST_OPERATION)vaultRequest({action:"undo",operationID:VAULT_LAST_OPERATION})};
  const ea=document.getElementById("expandall");if(ea)ea.onclick=explorerExpandAll;
  const toggle=document.getElementById("toggleexplorer");if(toggle)toggle.onclick=explorerToggle;
  const lf=document.getElementById("lfind");
  if(lf)lf.oninput=()=>{LFIND=lf.value;paintHomeList()};
  const vaultMenu=document.getElementById("vaultmenu");
  if(vaultMenu)vaultMenu.onclick=requestVaultFolder;

}
function requestVaultFolder(){
  if(VAULT_CONNECTED&&!leaveEditorAllowed(requestVaultFolder))return;
  if(!pickTake(PICKING,"vault"))return;
  paintPicking("vaultmenu","vault");paintPicking("connectvault","vault");
  post("openSystem",{what:"vault"});
  setTimeout(()=>{pickFree(PICKING,"vault");paintPicking("vaultmenu","vault");paintPicking("connectvault","vault")},PICK_FREE_MS);
}
/* 파일 정리: 디스크 확인 전에는 문서·경로를 먼저 바꾸지 않는다. */
function leaveEditorAllowed(next){
  clearEditorAutosave();
  if(!vaultHasDraft())return true;
  if(next){
    EDITOR_NAVIGATION=next;
    if(!SAVE_FLIGHT){
      const draft=takeEditorDraft();
      if(draft&&(draft.titleDirty||draft.bodyDirty)){
        if(!saveEditorValue("manual")){EDITOR_NAVIGATION=null;return false}
      }else save();
      resumeEditorNavigation();
    }
    return false;
  }
  /* Even a failed save must leave a visible way to recover. */
  paneOpen("r");
  onIndexNotice("변경 내용을 저장해 주세요.");
  const button=document.getElementById("sv");if(button)button.focus();return false;
}
function resumeEditorNavigation(drain=false){
  if(!EDITOR_NAVIGATION||SAVE_FLIGHT||SAVE_PENDING)return;
  if(vaultHasDraft()){if(drain)leaveEditorAllowed(EDITOR_NAVIGATION);return;}
  const next=EDITOR_NAVIGATION;EDITOR_NAVIGATION=null;next();
}
function saveEditorValue(origin="manual"){
  const ti=document.getElementById("ti"),bo=document.getElementById("bo");
  if(!ti||!bo)return false;
  const title=ti.value.trim();if(!title){onIndexNotice("문서 제목을 입력해 주세요.");ti.focus();setEditorSaveState("dirty");return false}
  const cur=sel===null?null:DOC.fragments[sel],stamp=now();
  if(cur){cur.title=title;cur.body=bo.value;cur.updatedAt=stamp;delete cur.seed}
  else{DOC.fragments.push({id:uid("f"),title,body:bo.value,questionIds:[],createdAt:stamp,updatedAt:stamp});sel=DOC.fragments.length-1}
  if(origin!=="auto")ti.value=title;
  save(origin);return true;
}
function vaultHasDraft(){
  const d=takeEditorDraft();
  return !!(SAVE_FLIGHT||SAVE_PENDING||changedFragmentIDs(VAULT_BASE,DOC).length||
    (d&&(d.titleDirty||d.bodyDirty)));
}
function vaultRequest(command,confirmed){
  if(VAULT_ACTION)return false;
  if(!bridged()){onIndexNotice("파일 정리는 앱에서 폴더를 연결한 뒤 사용할 수 있어요.");return false}
  if(vaultHasDraft()){onIndexNotice("편집 중인 내용을 저장한 뒤 파일을 정리해 주세요.");return false}
  if(!VAULT_REVISION)return false;
  const requestID=++VAULT_ACTION_SEQ;
  const revision=command.expectedRevision||VAULT_REVISION;
  VAULT_ACTION={requestID:requestID,command:command,revision:revision};
  post("vaultAction",Object.assign({},command,{requestID:requestID,revision:revision,phase:confirmed?"apply":"preview"}));
  const b=document.getElementById("vsubmit");if(b){b.disabled=true;b.textContent="확인 중…"}
  return true;
}
function onVaultAction(result){
  if(!result||!VAULT_ACTION||result.requestID!==VAULT_ACTION.requestID)return;
  const command=Object.assign({},VAULT_ACTION.command,{expectedRevision:VAULT_ACTION.revision});VAULT_ACTION=null;
  const b=document.getElementById("vsubmit");if(b){b.disabled=false;b.textContent="적용"}
  if(result.error){onIndexNotice(result.error);const e=document.getElementById("verror");if(e)e.textContent=result.error;return}
  if(result.preview){
    if(!(result.impacts||[]).length){vaultRequest(command,true);return}
    vaultDialog("링크 영향 확인",`<p>이동하면 다음 링크의 대상 경로가 달라져요. 링크는 자동으로 고치지 않아요.</p><ul>${result.impacts.map(x=>`<li>${esc(x.markdownPath)} · ${esc(x.reference)}</li>`).join("")}</ul>`,"계속 이동",()=>vaultRequest(command,true));return;
  }
  if(command.action==="openEntry")return;
  VAULT_LAST_OPERATION=command.action==="undo"?null:result.operationID||null;const undo=document.getElementById("vaultundo");if(undo)undo.disabled=!VAULT_LAST_OPERATION;
  vaultDialogClose();onIndexNotice("파일 정리를 적용했어요.");
  if(result.createdID){
    openWorkspaceDocument(result.createdID);
    const body=document.getElementById("bo");if(body)body.focus();
  }
}
function vaultMenuClose(restoreFocus=true){
  const M=VAULT_MENU;if(!M)return;
  VAULT_MENU=null;
  if(document.removeEventListener){
    document.removeEventListener("pointerdown",M.outside,true);
    document.removeEventListener("click",M.outside,true);
    document.removeEventListener("keydown",M.keydown,true);
  }
  if(M.menu&&M.menu.remove)M.menu.remove();
  if(restoreFocus&&M.trigger&&M.trigger.focus)M.trigger.focus({preventScroll:true});
}
function vaultDialogClose(){const e=document.getElementById("vaultdialog");if(e)e.remove()}
function vaultDialog(title,body,button,submit){
  vaultMenuClose(false);
  vaultDialogClose();
  const box=document.createElement("div");box.id="vaultdialog";box.className="vaultdialog";
  box.innerHTML=`<div class="vaultsheet" role="dialog" aria-modal="true" aria-label="${esc(title)}"><h3>${esc(title)}</h3>${body}<p id="verror" role="status"></p><div class="vaultbuttons"><button id="vcancel" class="gbtn">취소</button>${button?`<button id="vsubmit" class="gbtn">${esc(button)}</button>`:""}</div></div>`;
  app.appendChild(box);document.getElementById("vcancel").onclick=()=>{if(!VAULT_ACTION)vaultDialogClose()};
  if(button)document.getElementById("vsubmit").onclick=submit;
  box.onkeydown=ev=>{
    if(ev.key==="Escape"&&!VAULT_ACTION){ev.preventDefault();vaultDialogClose()}
    if(ev.key==="Tab"){
      const fields=Array.from(box.querySelectorAll("input,select,button")).filter(e=>!e.disabled&&e.getClientRects().length);
      const first=fields[0],last=fields[fields.length-1];
      if(ev.shiftKey&&document.activeElement===first){ev.preventDefault();last.focus()}
      else if(!ev.shiftKey&&document.activeElement===last){ev.preventDefault();first.focus()}
    }
  };
  const field=box.querySelector("input,select,button");if(field)field.focus();
}
/* 파일 조작은 기존 리비전·미리보기·복구 브리지를 사용한다. */
function vaultMenuPosition(menu,anchor){
  const ar=app&&app.getBoundingClientRect?app.getBoundingClientRect():{left:0,top:0,width:0,height:0};
  const width=ar.width||app.clientWidth||(typeof window!=="undefined"?window.innerWidth:0)||menu.offsetWidth||220;
  const height=ar.height||app.clientHeight||(typeof window!=="undefined"?window.innerHeight:0)||menu.offsetHeight||120;
  const mw=menu.offsetWidth||Math.min(220,Math.max(176,width-16));
  const mh=menu.offsetHeight||Math.max(40,(menu.children||[]).length*34+10);
  const gap=6;
  let left=width-mw-12,top=height-mh-12;
  if(anchor&&typeof anchor.x==="number"&&typeof anchor.y==="number"){
    left=anchor.x-ar.left;top=anchor.y-ar.top;
  }else if(anchor&&anchor.element&&anchor.element.getBoundingClientRect){
    const r=anchor.element.getBoundingClientRect();
    left=r.left-ar.left;top=r.top-ar.top;
    if(anchor.placement==="above")top=r.top-ar.top-mh-gap;
    else if(anchor.placement==="bottom")top=r.bottom-ar.top+gap;
    else if(anchor.placement!=="below")left=r.right-ar.left+gap;
  }
  const pad=8;
  left=Math.max(pad,Math.min(left,Math.max(pad,width-mw-pad)));
  top=Math.max(pad,Math.min(top,Math.max(pad,height-mh-pad)));
  menu.style.left=Math.round(left)+"px";menu.style.top=Math.round(top)+"px";
}
function vaultFileMenu(row,anchor){
  if(!leaveEditorAllowed(()=>vaultFileMenu(row,anchor)))return;
  vaultMenuClose(false);
  const folder=row&&row.folder,kind=folder?"Folder":"File";
  const actions=[];
  if(!row)actions.push({text:"저장소 폴더 변경…",run:requestVaultFolder});
  if(row&&row.path){
    actions.push({text:"이름 변경",run:()=>vaultNameDialog(row)});
    actions.push({text:"이동…",run:()=>vaultMoveDialog(row)});
    if(!folder)actions.push({text:workspaceFile(row.id)?.p.entry?"외부 앱으로 열기":"편집",run:()=>workspaceOpen(row.id)});
  }
  if(!row||folder){
    actions.push({text:"새 문서",run:()=>vaultNewDocument(row?row.path:"")});
    actions.push({text:"새 폴더",run:()=>vaultNewFolder(row?row.path:"")});
  }
  if(!row){
    if(VAULT_LAST_OPERATION)actions.push({text:"파일 작업 되돌리기",run:()=>vaultRequest({action:"undo",operationID:VAULT_LAST_OPERATION})});
  }
  const menu=document.createElement("div");menu.id="vaultcontextmenu";menu.className="vaultpopover";
  menu.setAttribute("role","menu");menu.setAttribute("aria-label",row?`${row.path} 파일 작업`:"저장소 메뉴");
  menu.innerHTML=actions.map(a=>`<button type="button" role="menuitem" tabindex="-1">${esc(a.text)}</button>`).join("");
  menu.style.visibility="hidden";app.appendChild(menu);
  const trigger=anchor&&anchor.trigger&&anchor.trigger.focus?anchor.trigger:null;
  const M={menu:menu,trigger:trigger,items:Array.from(menu.querySelectorAll('[role="menuitem"]')),outside:null,keydown:null};
  VAULT_MENU=M;
  M.outside=ev=>{
    if(!VAULT_MENU||VAULT_MENU.menu!==menu)return;
    const target=ev&&ev.target;
    if(target&&menu.contains&&menu.contains(target))return;
    vaultMenuClose();
  };
  M.keydown=ev=>{
    if(!VAULT_MENU||VAULT_MENU.menu!==menu)return;
    if(ev.key==="Escape"){ev.preventDefault();vaultMenuClose();return}
    if(ev.key==="Tab"){vaultMenuClose();return}
    if(!(ev.target&&menu.contains&&menu.contains(ev.target)))return;
    const items=M.items;if(!items.length)return;
    const current=document.activeElement,index=Math.max(0,items.indexOf(current));
    if(ev.key==="ArrowDown"||ev.key==="ArrowUp"||ev.key==="Home"||ev.key==="End"){
      ev.preventDefault();
      const next=ev.key==="Home"?0:ev.key==="End"?items.length-1:Math.max(0,Math.min(items.length-1,index+(ev.key==="ArrowDown"?1:-1)));
      items[next].focus({preventScroll:true});
    }else if(ev.key==="Enter"){
      ev.preventDefault();items[index].click();
    }
  };
  if(document.addEventListener){
    document.addEventListener("pointerdown",M.outside,true);
    document.addEventListener("click",M.outside,true);
    document.addEventListener("keydown",M.keydown,true);
  }
  M.items.forEach((item,i)=>item.onclick=()=>{if(VAULT_MENU&&VAULT_MENU.menu===menu){vaultMenuClose();actions[i].run()}});
  vaultMenuPosition(menu,anchor);
  menu.style.visibility="visible";
  if(M.items[0])M.items[0].focus({preventScroll:true});
}
function vaultNameDialog(row){
  const name=row.path.split("/").pop();
  vaultDialog("이름 변경",`<input id="vname" aria-label="파일 이름" value="${esc(name)}">`,"변경",()=>{
    const next=document.getElementById("vname").value.trim();if(!next)return;
    vaultRequest({action:"renameEntry",name:next,path:row.path});
  });
}
function vaultMoveDialog(row){
  const folders=VAULT_FOLDERS.filter(p=>!row.folder||(p!==row.path&&!p.startsWith(row.path+"/")));
  vaultDialog("이동",`<select id="vfolder" aria-label="이동할 폴더"><option value="">저장소</option>${folders.map(p=>`<option value="${esc(p)}">${esc(p)}</option>`).join("")}</select>`,"이동",()=>{
    vaultRequest({action:"moveEntry",folder:document.getElementById("vfolder").value,path:row.path});
  });
}
function vaultTrashDialog(){
  const entries=VAULT_TRASH.filter(t=>!t.legacy);
  vaultDialog("휴지통",entries.length?entries.map((t,i)=>`<div class="row"><span>${esc(t.originalPath||t.storedRelativePath)}</span><button class="gbtn" id="vrestore${i}">복구</button></div>`).join(""):'<p>비어 있습니다</p>',null);
  entries.forEach((t,i)=>document.getElementById("vrestore"+i).onclick=()=>vaultRequest({action:"restore",trashID:t.id}));
}
function bindVaultRows(box){
  const rows=Array.from(box.querySelectorAll(".hmit"));
  const data=el=>{
    if(!el)return null;
    if(el.dataset.fold!==undefined)return {folder:true,path:el.dataset.fold,id:el.dataset.id};
    return {folder:false,path:el.dataset.path,id:el.dataset.id};
  };
  rows.forEach((el,i)=>{
    const more=el.querySelector(".filemore");
    if(more)more.onclick=ev=>{ev.stopPropagation();const row=data(el);if(row?.folder)vaultFileMenu(row,{element:ev.currentTarget,trigger:ev.currentTarget,placement:"right"});else if(row)workspaceOpen(row.id)};
    el.setAttribute("tabindex","0");el.setAttribute("role","treeitem");
    const row=data(el);el.setAttribute("aria-level",String((row.path||"").split("/").length));
    if(row.folder)el.setAttribute("aria-expanded",String(!el.classList.contains("zip")));
    else el.setAttribute("aria-selected",String(el.classList.contains("sel")));
    const focusPath=path=>{
      const e=Array.from(box.querySelectorAll(".hmit")).find(x=>data(x)?.path===path);if(e)e.focus();
    };
    el.oncontextmenu=ev=>{ev.preventDefault();vaultFileMenu(data(el),{x:ev.clientX,y:ev.clientY,trigger:el,placement:"pointer"})};
    el.onkeydown=ev=>{
      if(ev.target&&ev.target!==el&&ev.target.closest(".filemore,.tw"))return;
      if(ev.key==="ArrowDown"||ev.key==="ArrowUp"){ev.preventDefault();const next=rows[i+(ev.key==="ArrowDown"?1:-1)];if(next)next.focus()}
      else if(ev.key==="Home"||ev.key==="End"){ev.preventDefault();rows[ev.key==="Home"?0:rows.length-1]?.focus()}
      else if(ev.key==="ArrowRight"){
        ev.preventDefault();const r=data(el);
        if(r?.folder&&LZIP[r.path]){delete LZIP[r.path];paintHomeList();focusPath(r.path)}
        else if(r?.folder&&data(rows[i+1])?.path.startsWith(r.path+"/"))rows[i+1].focus();
      }
      else if(ev.key==="ArrowLeft"){
        ev.preventDefault();const r=data(el);if(!r)return;
        if(r.folder&&!LZIP[r.path]){LZIP[r.path]=true;paintHomeList();focusPath(r.path)}
        else focusPath(r.path.split("/").slice(0,-1).join("/"));
      }
      else if(ev.key==="Enter"){ev.preventDefault();el.onclick(ev)}
      else if(ev.key==="F2"){ev.preventDefault();const r=data(el);if(r)vaultNameDialog(r)}
    };
    el.draggable=true;
    el.ondragstart=ev=>{const r=data(el);if(!r||vaultHasDraft()){ev.preventDefault();return}ev.dataTransfer.setData("application/x-clonie-file",JSON.stringify(r));ev.dataTransfer.effectAllowed="move"};
    if(!data(el)?.folder)return;
    el.ondragover=ev=>{if(Array.from(ev.dataTransfer.types||[]).includes("application/x-clonie-file")){ev.preventDefault();el.classList.add("dragover")}};
    el.ondragleave=()=>el.classList.remove("dragover");
    el.ondrop=ev=>{
      ev.preventDefault();el.classList.remove("dragover");
      let r;try{r=JSON.parse(ev.dataTransfer.getData("application/x-clonie-file"))}catch(e){return}
      const folder=data(el).path;
      explorerMove(r,folder);
    };
  });
}

function explorerMove(row,folder){
  if(!row||!row.path||row.path.split("/").slice(0,-1).join("/")===folder)return false;
  if(row.folder&&(folder===row.path||folder.startsWith(row.path+"/")))return false;
  return vaultRequest({action:"moveEntry",folder:folder,path:row.path});
}
function bindExplorerRoot(){
  const root=document.getElementById("vaultheading");if(!root)return;
  root.ondragover=ev=>{if(Array.from(ev.dataTransfer.types||[]).includes("application/x-clonie-file")){ev.preventDefault();root.classList.add("dragover")}};
  root.ondragleave=()=>root.classList.remove("dragover");
  root.ondrop=ev=>{
    ev.preventDefault();root.classList.remove("dragover");
    let row;try{row=JSON.parse(ev.dataTransfer.getData("application/x-clonie-file"))}catch(e){return}
    explorerMove(row,"");
  };
}

function speechModelText(){return SPEECH_MESSAGE||{unknown:"상태 확인 중…",required:"모델 준비 필요",unsupported:"이 Mac에서 사용할 수 없어요",loading:"모델 준비 중…",ready:"준비됨",error:"모델 준비에 실패했어요"}[SPEECH_STATE]||""}
function paintSpeechModel(){
  const e=document.getElementById("speechstate"),b=document.getElementById("speechprepare");
  if(e)e.textContent=speechModelText();
  if(b){b.disabled=["unknown","loading","ready","unsupported"].includes(SPEECH_STATE);b.textContent=SPEECH_STATE==="loading"?"준비 중…":SPEECH_STATE==="error"?"다시 준비":"모델 준비"}
}
function onSpeechModelState(state,message){SPEECH_STATE=state;SPEECH_MESSAGE=message||"";paintSpeechModel()}
function indexStateText(){return {indexing:"검색 준비 중…",ready:"",unavailable:"검색 모델을 불러올 수 없어요",error:"검색 준비에 실패했어요"}[INDEX_STATE]||""}
function onIndexState(state){INDEX_STATE=state;const e=document.getElementById("indexstate");if(e){e.textContent=indexStateText();e.title=state==="indexing"?"파일을 읽고 있어요. 준비 중에도 문서를 보거나 수정할 수 있어요.":""}}
function folderStartRender(){
  app.innerHTML=`<div id="top" class="drag hmtop"><span id="brand">Clonie</span>
    <span style="flex:1"></span><button class="ibtn ico nodrag" id="x" title="닫기" aria-label="닫기">${ICO.close}</button></div>
    <div id="folderstart" style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px">
      <button class="gbtn p" id="connectvault">폴더 연결…</button>
      <span class="foot" id="foldererror">${esc(vaultTrouble||"")}</span>
    </div>`;
  document.getElementById("connectvault").onclick=requestVaultFolder;
  document.getElementById("x").onclick=()=>post("closeWindow");
  paintPicking("connectvault","vault");
}
/* ★ 오른쪽 상세 판 — **한 벌뿐이다.** 3단의 오른쪽 칸이 곧 이것이고, 왼쪽 트리에서 골라도
   가운데 별을 눌러도 **같은 판**이 열린다.
   ⚠ **새 판을 안 지었다.** 지도가 자기 상세 판을 가지면 저장·지우기가 **두 벌**이 되고,
     다음에 한쪽만 고쳐진다 — 이 파일이 이미 두 번 그렇게 데었다.
   ★ **설명 문장 0** (#74 C3 · design.md §5). 걷힌 것: 라벨 둘(`.fl` 「한 줄 요약」·「내용」) ·
     그림을 가리키던 한 줄(`#hmhint`) · 채우기 띠(`.fbar`) · 「지금 채우기」.
     남는 것은 **칸 둘·버튼 둘**이고, 무엇을 쓰는 칸인지는 placeholder 가 든다.
   ⚠ **볼트 사고 띠는 남는다** — 사고는 어휘 밖이다(`paintVaultTrouble`). */
function editPanel(cur){
  return `<div class="dochead">
      <div class="docidentity"><span class="docpath">${cur?esc(PATHS[cur.id]||cur.title):"새 문서"}</span>
        <span id="docsavestate" class="docsavestate" role="status" aria-live="polite">${esc(editorSaveStateText(EDITOR_SAVE_STATE))}</span></div>
      <button class="ibtn ico" id="docmore" aria-haspopup="menu" aria-label="문서 메뉴" title="문서 메뉴">${ICO.more}</button>
      <button class="ibtn ico" id="closedoc" aria-label="문서 닫기" title="문서 닫기">${ICO.close}</button></div>
    <div><input id="ti" aria-label="문서 제목" placeholder="제목" value="${cur?esc(cur.title):""}"></div>
    <div class="docbody"><textarea id="bo" aria-label="문서 내용" placeholder="">${cur?esc(cur.body):""}</textarea>
      ${sourceButtons(cur)}</div>`;
}
function closeWorkspaceDocument(){
  if(!leaveEditorAllowed(()=>closeWorkspaceDocument()))return false;
  canvasRemember();paneApply("r",0);paintCanvasNavigation();return true;
}
function openWorkspaceDocument(id){
  if(PANE.r>0&&sel!==null&&DOC.fragments[sel]?.id===id)return true;
  if(!leaveEditorAllowed(()=>openWorkspaceDocument(id)))return false;
  const i=DOC.fragments.findIndex(p=>p.id===id);if(i<0)return false;
  const parent=(PATHS[id]||"").split("/").slice(0,-1).join("/");if(parent!==WORKSPACE_SCOPE)workspaceEnterFolder(parent);
  if(sel!==i||PANE.r===0)canvasRemember();
  sel=i<0?null:i;WORKSPACE_SELECTED_ID=id;revealWorkspaceFile(id);paneOpen("r");
  if(CANV?.els){CANV.follow=null;CANV.glide=null;CANV.nodes.forEach(n=>CANV.els.node[n.id].setAttribute("class",canvasNodeClass(n.id)))}
  if(stackView==="settings"){stackView="edit";stackRender()}else{canvasPaintPanel();paintHomeList()}
  treeScrollSel();return true;
}

/* 본문 속 Markdown 링크 중 볼트 파일 상대경로만 상세 판 아래에 놓는다.
   웹 주소·이미지·숨은 경로·지원하지 않는 형식은 여기서부터 버튼이 아니다. 네이티브는 눌렀을 때
   실제 파일·symlink·실행 권한을 다시 검사한다(`VaultReferenceResolver`). */
const SOURCE_EXTS=new Set(["md","markdown","txt","pdf","docx","hwpx"]);
function markdownLinkTarget(raw){
  let s=(raw||"").trim();
  if(s.startsWith("<")){
    const e=s.indexOf(">");if(e<0)return null;s=s.slice(1,e);
  }else{
    /* 공백 뒤 따옴표는 Markdown의 선택 title이다. 공백 든 경로는 `<…>`나 `%20`으로 온다. */
    s=s.split(/\s+(?=["'])/,1)[0];
  }
  return s||null;
}
function sourceReferencePath(fromPath,raw){
  let ref=markdownLinkTarget(raw),from=(fromPath||"").normalize("NFC");
  if(!ref||!from||ref.startsWith("/")||ref.startsWith("~")||ref.includes("\\")
      ||/^[A-Za-z][A-Za-z0-9+.-]*:/.test(ref))return null;
  ref=ref.split(/[?#]/,1)[0];
  try{ref=decodeURIComponent(ref)}catch(e){return null}
  if(!ref||ref.startsWith("/")||ref.startsWith("~")||ref.includes("\\")
      ||/^[A-Za-z][A-Za-z0-9+.-]*:/.test(ref))return null;
  const out=from.split("/");out.pop();
  for(const part of ref.normalize("NFC").split("/")){
    if(!part)return null;
    if(part===".")continue;
    if(part===".."){if(!out.length)return null;out.pop();continue}
    if(part.startsWith("."))return null;
    out.push(part);
  }
  if(!out.length)return null;
  const ext=(out[out.length-1].split(".").pop()||"").toLowerCase();
  return SOURCE_EXTS.has(ext)?out.join("/"):null;
}
function markdownSourceLinks(body,fromPath,paths){
  if(!fromPath)return [];
  const byPath=new Map(Object.entries(paths||{}).map(([id,path])=>[
    (path||"").normalize("NFC").toLowerCase(),id]));
  const out=[],re=/(?<!!)\[([^\]\n]+)\]\(([^)\n]+)\)/g;
  let m;
  while((m=re.exec(body||""))){
    const reference=markdownLinkTarget(m[2]),path=sourceReferencePath(fromPath,reference);
    if(!path)continue;
    const ext=path.split(".").pop().toLowerCase();
    out.push({label:m[1],reference,path,
      targetID:(ext==="md"||ext==="markdown")?byPath.get(path.toLowerCase())||null:null});
  }
  return out;
}
function sourceLinksFor(cur){return cur?markdownSourceLinks(cur.body,PATHS[cur.id],PATHS):[]}
function sourceButtons(cur){
  const links=sourceLinksFor(cur);
  return links.length?`<div class="srefs">${links.map((link,i)=>
    `<button class="sref" id="sref${i}" title="${esc(link.path)}">${esc(link.label)}</button>`
  ).join("")}</div>`:"";
}
function openSourceReference(link,fromPath){
  const draft=takeEditorDraft();
  if(draft&&(draft.titleDirty||draft.bodyDirty)){
    onVaultTrouble("수정한 내용을 저장한 뒤 출처를 여세요.");return;
  }
  if(link.targetID){
    openWorkspaceDocument(link.targetID);return;
  }
  post("openSystem",{what:"source",fromPath,reference:link.reference});
}
function bindSourceButtons(cur){
  sourceLinksFor(cur).forEach((link,i)=>{
    const button=document.getElementById(`sref${i}`);
    if(button)button.onclick=()=>openSourceReference(link,PATHS[cur.id]);
  });
}
function editorManualSave(){
  clearEditorAutosave();
  if(!saveEditorValue("manual"))return false;
  stackRender();return true;
}
function editorMenu(anchor){
  vaultMenuClose(false);
  const cur=sel===null?null:DOC.fragments[sel],actions=[];
  if(cur)actions.push({text:"이름 변경",run:()=>{
    const run=()=>vaultNameDialog({id:cur.id,path:PATHS[cur.id],folder:false});
    if(leaveEditorAllowed(run))run();
  }});
  if(cur)actions.push({text:"관련 자료",run:()=>{
    const run=()=>canvasNavigateFile(cur.id);
    if(leaveEditorAllowed(run))run();
  }});
  actions.push({text:"수동 저장",run:editorManualSave});
  if(EDITOR_SAVE_STATE==="failed")actions.push({text:"다시 저장",run:editorManualSave});
  const menu=document.createElement("div");menu.id="doccontextmenu";menu.className="vaultpopover";
  menu.setAttribute("role","menu");menu.setAttribute("aria-label","문서 메뉴");
  menu.innerHTML=actions.map(a=>`<button type="button" role="menuitem" tabindex="-1">${esc(a.text)}</button>`).join("");
  menu.style.visibility="hidden";app.appendChild(menu);
  const trigger=anchor&&anchor.trigger&&anchor.trigger.focus?anchor.trigger:null;
  const M={menu:menu,trigger:trigger,items:Array.from(menu.querySelectorAll('[role="menuitem"]')),outside:null,keydown:null};
  VAULT_MENU=M;
  M.outside=ev=>{
    if(!VAULT_MENU||VAULT_MENU.menu!==menu)return;
    const target=ev&&ev.target;
    if(target&&menu.contains&&menu.contains(target))return;
    vaultMenuClose();
  };
  M.keydown=ev=>{
    if(!VAULT_MENU||VAULT_MENU.menu!==menu)return;
    if(ev.key==="Escape"){ev.preventDefault();vaultMenuClose();return}
    if(ev.key==="Tab"){vaultMenuClose();return}
    if(!(ev.target&&menu.contains&&menu.contains(ev.target)))return;
    const items=M.items;if(!items.length)return;
    const current=document.activeElement,index=Math.max(0,items.indexOf(current));
    if(ev.key==="ArrowDown"||ev.key==="ArrowUp"||ev.key==="Home"||ev.key==="End"){
      ev.preventDefault();
      const next=ev.key==="Home"?0:ev.key==="End"?items.length-1:Math.max(0,Math.min(items.length-1,index+(ev.key==="ArrowDown"?1:-1)));
      items[next].focus({preventScroll:true});
    }else if(ev.key==="Enter"){ev.preventDefault();items[index].click()}
  };
  if(document.addEventListener){
    document.addEventListener("pointerdown",M.outside,true);
    document.addEventListener("click",M.outside,true);
    document.addEventListener("keydown",M.keydown,true);
  }
  M.items.forEach((item,i)=>item.onclick=()=>{if(VAULT_MENU&&VAULT_MENU.menu===menu){vaultMenuClose();actions[i].run()}});
  vaultMenuPosition(menu,anchor);
  menu.style.visibility="visible";
  if(M.items[0])M.items[0].focus({preventScroll:true});
}
/* 그 판의 손잡이 전부. **판을 다시 그린 쪽이 곧바로 이것을 부른다** — 안 부르면 저장 버튼이
   조용히 죽는다(#66-1 이 그 모양이었다). */
function bindEditPanel(cur,pre){
  /* ★ 볼트 사고 띠 (블로커 F1). 렌더가 오른쪽 칸을 새로 지었으니 **띠도 다시 앉힌다** —
     들고 있던 말이 렌더 한 번에 사라지면 「저장이 안 됐다」가 조용해진다. */
  paintVaultTrouble();
  bindSourceButtons(cur);
  const close=document.getElementById("closedoc");if(close)close.onclick=closeWorkspaceDocument;
  const back=document.getElementById("docback");if(back)back.onclick=canvasGoBack;
  const forward=document.getElementById("docforward");if(forward)forward.onclick=canvasGoForward;
  const more=document.getElementById("docmore");if(more)more.onclick=ev=>editorMenu({element:ev.currentTarget,trigger:ev.currentTarget,placement:"bottom"});
  const ti=document.getElementById("ti"),bo=document.getElementById("bo");
  const remember=()=>{
    if(cur){holdDirty([cur.id],VAULT_REVISION);syncDirtyRevisionPins()}
    setEditorSaveState("dirty");if(!EDITOR_COMPOSING)scheduleEditorAutosave();
  };
  if(ti)ti.oninput=remember;
  if(bo)bo.oninput=remember;
  const compositionStart=()=>{EDITOR_COMPOSING=true;clearEditorAutosave()};
  const compositionEnd=()=>{EDITOR_COMPOSING=false;remember()};
  if(ti){ti.oncompositionstart=compositionStart;ti.oncompositionend=compositionEnd}
  if(bo){bo.oncompositionstart=compositionStart;bo.oncompositionend=compositionEnd}
  const editorKey=ev=>{
    if((ev.metaKey||ev.ctrlKey)&&ev.key.toLowerCase()==="s"){ev.preventDefault();editorManualSave()}
    if(ev.key==="Escape"){ev.preventDefault();closeWorkspaceDocument()}
  };
  if(ti)ti.onkeydown=editorKey;
  if(bo)bo.onkeydown=editorKey;
  /* 예전 화면 계약을 유지한다 — 실제 헤더에는 저장 버튼이 없고, 최소 DOM 시험만
     `sv.onclick()`으로 수동 저장을 호출한다. */
  const sv=document.getElementById("sv");if(sv)sv.onclick=editorManualSave;
  paintEditorSaveState();
  const d=document.getElementById("del");if(d)d.onclick=()=>{DOC.fragments.splice(sel,1);sel=null;save();stackRender()};
}
/* ★ 왼쪽 칸 = **폴더 트리다** (#74 C2 · design.md §5, 레퍼런스 = 옵시디언 탐색기).
   항성 행(접기/펴기) → 행성 행 → 위성 행(들여쓰기). 작은 중심도 폴더라 행성과 같은 층에
   접히는 행으로 앉는다.
   ⚠ **쉴 때 점이 없다** (design.md §2: 무채색 = 쉼). 점은 **검색이 켜졌을 때만** 붙고,
     그 색은 지도가 이미 낸 것을 그대로 읽는다(`CANV.last`) — 여기서 다시 재면 그것이
     곧 두 번째 자다.
   ⚠ **걷힌 것**: 구멍 행 · 「이어서 채우기」 · 「색인이 아직 없어서…」 한 줄. 앞의 둘은
     질문 어휘고(ADR 0006), 마지막은 준비도 점이 죽어서 말할 대상이 없다. */
/* 접힌 폴더 — **세션에만 산다.** 파일에 안 남긴다: 볼트가 바뀌면 그 키가 통째로 낡는다.
   `{경로:true}` = 접힘. 기본은 전부 펴짐이다(처음 여는 사람이 빈 칸을 보면 안 된다). */
let LZIP={};
/* 트리를 **한 줄씩 편 것** — 순수 함수라 `node --test` 가 잠근다.
   ⚠ 접힘은 인자로 받는다(전역을 안 읽는다) — 그래야 시험이 갈아끼운다. */
function vaultRows(tree,zip){
  const Z=zip||{},out=[];
  const walk=(dir,depth,parent)=>{
    Object.keys(dir.dirs||{}).sort().forEach(name=>{
      const path=parent?parent+"/"+name:name;
      out.push({k:"sun",id:path,path:path,t:name,depth:depth,parent:parent||null,folder:true,zip:!!Z[path]});
      if(!Z[path])walk(dir.dirs[name],depth+1,path);
    });
    (dir.files||[]).slice().sort((a,b)=>a.path.localeCompare(b.path)).forEach(f=>{
      out.push({k:"planet",id:f.p.id,path:f.path,t:f.file,depth:depth,parent:parent||null,folder:false,zip:false});
    });
  };
  if(tree&&tree.filesystem)walk(tree.filesystem,0,"");
  return out;
}
/* 검색 중에는 접힘을 무시하고 일치한 항목의 조상을 함께 남긴다. */
function explorerFilter(rows,q){
  const v=String(q||"").normalize("NFC").trim().toLowerCase();if(!v)return rows;
  const paths=new Set();
  rows.filter(r=>(r.path+" "+(r.t||"")).normalize("NFC").toLowerCase().includes(v)).forEach(r=>{
    let path=r.path;while(path){paths.add(path);const i=path.lastIndexOf("/");path=i<0?"":path.slice(0,i)}
  });
  return rows.filter(r=>paths.has(r.path));
}
/* 행에 붙는 조각(제목·인덱스) — **트리는 id 만 들고 글자는 문서가 든다.**
   두 벌로 들면 저장 한 번에 한쪽이 낡는다. */
function vaultRowFrag(row){
  if(row.k!=="planet"&&row.k!=="moon")return null;
  const i=DOC.fragments.findIndex(p=>p.id===row.id);
  return i<0?null:{i:i,p:DOC.fragments[i]};
}
/* ★ 목록 거르개 — **순수 함수라 `node --test` 가 잠근다** (#67 재편).
   ⚠ **자가 아니다.** 소문자로 낮춰 「들어 있나」만 본다 — 뜻으로 재는 것은 가운데 지도의
     질문 칸 하나뿐이고, 여기서 또 재면 목록과 지도가 **다른 순서**를 말하게 된다.
   ⚠ 폴더 행은 **이름으로** 걸린다 — 폴더가 검색에서 통째로 빠지면 「폴더는 못 찾는다」가
     조용한 규칙이 된다. */
function listFilter(rows,q){
  const v=(q||"").trim().toLowerCase();
  if(!v)return rows||[];
  return (rows||[]).filter(r=>((r.t||"")+" "+(r.body||"")).toLowerCase().includes(v));
}
/* ★ 왼쪽 칸을 **제자리에서** 짓는다 (#61 A · 셀프 실기 수리).
   ⚠ **왜 따로 뺐나**: 벡터는 저장·기동 뒤 **비동기로** 온다(`receiveVectors`). 그때 화면을
     통째로 다시 그리면 사람이 치던 글이 날아간다.
   ⚠ 편집기(`#ti`·`#bo`)는 **안 건드린다** — 이 함수가 손대는 것은 왼쪽 칸 하나뿐이다. */
function paintHomeList(){
  const box=document.getElementById("leftlist");if(!box)return;
  /* ★ **판을 여기서 세운다** — 트리를 두 벌로 들면 한쪽이 낡는다 (`canvasUniverse` 는
     서명이 같으면 들고 있던 판을 그대로 돌려준다). 전 판은 `CANV` 를 그냥 읽었는데,
     `stackRender` 가 이 함수를 **가운데 칸보다 먼저** 불러서 문서가 갈린 직후 한 번은
     **옛 트리로 그려졌다** — 새 볼트를 열어도 왼쪽이 옛 목록이던 자리다. */
  const active=document.activeElement,focused=active&&active.closest&&active.closest(".hmit");
  const focusPath=focused&&box.contains&&box.contains(focused)?focused.getAttribute("title"):null;
  const focusMore=!!(focusPath&&active.classList.contains("filemore"));
  const L=canvasUniverse();
  /* 켜진 색은 **지도가 낸 그것**이다 — 없으면(쉼) 점이 아예 안 붙는다 */
  const lit=L.last?L.last.by:null;
  const all=vaultRows(L.tree,LFIND.trim()?{}:LZIP).map(r=>{
    const f=vaultRowFrag(r);
    return Object.assign({},r,f?{i:f.i,t:(PATHS[f.p.id]||"").split("/").pop()||f.p.title,body:f.p.body||"",seed:isSeed(f.p)}:{body:""});
  });
  const rows=explorerFilter(all,LFIND);
  /* 몇 개가 걸렸나 — **거르개를 쓸 때만** 뜬다. 안 쓸 때 총계를 적으면 목록이 이미 말하는
     것을 글자로 한 번 더 말하는 자리가 된다. */
  const hb=document.getElementById("lhits");
  if(hb)hb.textContent=LFIND.trim()?`일치 ${all.filter(r=>(r.path+" "+r.t).normalize("NFC").toLowerCase().includes(LFIND.normalize("NFC").trim().toLowerCase())).length}`:"";
  const current=sel!==null?DOC.fragments[sel]:null;
  if(hb&&LFIND.trim()&&current&&!rows.some(r=>r.id===current.id)){
    hb.innerHTML+=` <button id="revealcurrent" class="ibtn" title="${esc(PATHS[current.id]||current.title)}">선택한 파일 표시</button>`;
    const reveal=document.getElementById("revealcurrent");
    if(reveal)reveal.onclick=()=>{LFIND="";const input=document.getElementById("lfind");if(input)input.value="";paintHomeList();treeScrollSel()};
  }
  const dotOf=id=>{
    if(!lit)return "";
    const it=lit[id];
    if(!it||!it.lit)return "";
    /* 못 잰 이웃(`"n"`)은 **신호등이 아니다** — 무채색 점으로 물러선다(`.dot.hmn`) */
    return `<span class="dot ${it.c==="n"?"hmn":it.c}"></span>`;
  };
  const treeIconOf=r=>`<span class="treeicon" aria-hidden="true">${r.folder?ICO.folder:(typeof workspaceFileIcon==="function"?workspaceFileIcon(r.path):ICO.file)}${r.folder?"":dotOf(r.id)}</span>`;
  box.innerHTML=(rows.length?rows.map(r=>{
      const pad=`style="padding-left:${8+r.depth*20}px;min-width:${220+r.depth*20}px"`;
      const twisty=r.folder?`<button class="tw" aria-label="${esc(r.t)} ${r.zip?"펼치기":"접기"}" aria-expanded="${!r.zip}">${r.zip?"▸":"▾"}</button>`:`<span class="tw empty" aria-hidden="true"></span>`;
      /* ★ 항성 줄은 **범위 지정의 문**이기도 하다 (#75 4) — 지금 범위면 그렇다고 보인다.
         화살표(`.tw`)는 접기, 줄의 나머지는 범위 + 글라이드. 아래 손잡이가 그 둘을 가른다. */
      if(r.folder)return `<div class="hmit fold${r.zip?" zip":""}`
        +`${(L.focusPath===r.path||(!L.focusPath&&L.focusID===r.id))?" scoped":""}" data-fold="${esc(r.path)}"`
        +` data-k="${r.k}" data-id="${esc(r.id)}" ${pad}`
        +` title="${esc(r.path)}">${twisty}${treeIconOf(r)}`
        +`<span class="hmtx">${esc(r.t)}</span><button class="filemore" title="${esc(r.t)} 작업" aria-label="${esc(r.t)} 작업">···</button></div>`;
      return `<div class="hmit${workspaceSelectedID()===r.id?" sel":""}" data-i="${r.i}" data-id="${esc(r.id)}" data-path="${esc(r.path)}" ${pad}`
        +` title="${esc(r.path)}">${twisty}${treeIconOf(r)}<span class="hmtx">${esc(r.t)}</span>`
        +`${r.seed?'<span class="seedtag">예시</span>':""}<button class="filemore fileedit" title="${esc(r.t)} 편집" aria-label="${esc(r.t)} ${r.i===undefined?"외부 앱으로 열기":"편집"}">${r.i===undefined?"열기":"편집"}</button></div>`;
    }).join("")
    /* ★ 빈 상태 — **한 줄뿐이다.** 넣는 문은 이 칸의 위아래 버튼이 이미 들고 있다.
       ⚠ **「비었다」와 「거르개가 다 걸렀다」를 가른다** — 같은 말을 하면 찾다가 못 찾은
         사람이 **볼트가 비었다고 읽는다.** */
    :(LFIND.trim()&&all.length
      ?`<div class="hmez">「${esc(LFIND.trim())}」에 걸리는 것이 없어요</div>`
      :`<div class="hmez">문서가 없습니다</div>`));
  /* 폴더 행 — **누른 자리가 동사를 가른다** (#75 4). 화살표는 접기, 항성 줄의 나머지는
     **범위 지정 + 카메라 글라이드**다. 작은 중심(폴더)은 잴 것이 없어 접기뿐이다.
     ⚠ 접기를 화살표로 좁힌 것이 이번 변경이다 — 줄 전체가 접기였으면 새 동사를 걸 자리가 없다. */
  box.querySelectorAll(".hmit.fold").forEach(el=>{
    const zip=()=>{
      const k=el.dataset.fold;
      if(LZIP[k])delete LZIP[k];else LZIP[k]=true;
      paintHomeList();
    };
    const toggle=el.querySelector(".tw");if(toggle)toggle.onclick=ev=>{ev.stopPropagation();zip()};
    el.onclick=ev=>{
      const tw=ev&&ev.target&&ev.target.closest?ev.target.closest(".tw"):null;
      if(tw)return zip();
      if(stackView==="settings"){stackView="edit";stackRender()}
      canvasScopeFolder(el.dataset.fold);
    };
  });
  /* 조각 행 — 고르면 **그 별에서 파동**이 나가고 **카메라가 그 별로 간다** (#75 4).
     문이 둘(목록·별)이어도 그림은 하나다. */
  box.querySelectorAll(".hmit:not(.fold)").forEach(el=>el.onclick=()=>{
    canvasNavigateFile(el.dataset.id);
  });
  bindVaultRows(box);
  if(focusPath){
    const row=Array.from(box.querySelectorAll(".hmit")).find(el=>el.getAttribute("title")===focusPath);
    const target=focusMore&&row?row.querySelector(".filemore"):row;
    if(target)target.focus({preventScroll:true});
  }

}
/* ══ 뜻 지도 (#67) — 점 하나 = md 조각 하나, 물어보면 그 뜻의 점이 켜진다 ════════════
   박선호 2026-09-02: *"점 형태의 여러 md 파일들이 캔버스에 있고, 검색하면 해당되는 점들이 빛나는."*

   ★ **자를 하나도 안 만들었다.** 순위·색·문턱은 전부 `rank()`·`eris`·`risk`·`SIM_A`·`RISK_*`
     그대로고, 이 절이 더한 것은 **어디에 앉히고 어떻게 켜나**뿐이다. 그래서 지도와 라이브
     카드가 같은 질문에 같은 순서를 낸다 — 갈리면 그건 결함이지 화면 차이가 아니다.
   ★ **질문은 안 그린다** (#67 확정 ②). 질문은 준비도 줄(`paintReady`)과 구멍 뒤에서만 산다.
   ★ **절 소켓(상황·한 일·결과·한계)은 이번 이식에서 뺐다** — 자동으로 가르는 것이 아직 없어
     빈 칸만 넷 뜬다. 실험은 시제품에 남아 있다(#67 코멘트).
   ⚠ **판정선 뒤다.** 이 화면은 `stackRender` 아래에서만 열리고 면접 진입점에서 안 닿는다
     (`tests/check_interview_offline.py` 의 `BOUNDARY`). 그 경계를 넘기지 마라.
   ⚠ 통로를 **안 늘렸다.** 자유 질문의 뜻 벡터는 이미 있는 `embedDraft`(`kind:"query"`,
     #33)가 굽는다 — `ContentGraph.embedDraft` 가 `embed(query:)` 를 부르므로 라이브 검색과
     **같은 축**이고, 그래야 초록선(`SIM_G_DIRECT`)이 근거를 잃지 않는다(`gradePractice` 와 같은 규율).
   ══════════════════════════════════════════════════════════════════════════ */
/* 배치가 사는 월드. **화면 크기와 무관하다** — 보이는 크기는 `canvasFit` 이 맞춘다 */
const CV_W=1000, CV_H=640;
const CV_R=10, CV_RLIT=10;   /* 목업 v4: 켜져도 안 자란다 — 밝기(opacity)가 일치도를 든다 */
/* 태양의 반지름 (#70 확정 ④ — *"중앙 orb 크게"*). 별(`CV_R`)의 네 배가 넘어야 「같은 종류의
   점 하나」가 아니라 **다른 것**으로 읽힌다. 선은 이 밖에서 시작한다(`canvasPlace`). */
const CV_ORB=27;
/* 강조하는 상위 몇 개 — **라이브 카드와 같은 셋**이다(`paintRecs` 의 `[0,1,2]`).
   ⚠ 1위 하나만 강조하면 「저장소가 정답 하나를 안다」는 그림이 된다. 실제로 사람이 고르는
     것은 카드 셋이고, 지도도 그 셋을 같이 밝힌다. */
const CV_TOP=3;

/* ★ 지도에 앉는 조각 — **`rank()` 가 재는 것과 같은 무리여야 한다.** 씨앗은 순위에서 빠지므로
   (블로커 F2) 그리면 **영영 안 켜지는 점**이 남고, 그러면 범례의 「점 하나 = 내 답변 하나」가
   거짓이 된다. 목록 뷰는 「예시」 딱지로 가르고 여기는 안 그린다 — 고칠 문은 그 목록이다. */
const canvasFrags=()=>(DOC.fragments||[]).filter(p=>!isSeed(p));
/* 자의 눈금 한 벌 — **`how` 하나에서 나온다.** 둘을 따로 들고 다니면 한 줄만 고쳐져 갈린다. */
const canvasScale=how=>how==="뜻"?{green:1,amber:SIM_A}:{green:RISK_G,amber:RISK_A};
/* ══ 우주 (#74 B) — **자리는 구조, 불은 뜻** (ADR 0006) ═══════════════════════════
   ★ 전 판(#67)은 자리도 뜻이 정했다(힘 시뮬 + 사이드카). 그것이 죽었다: 별의 자리는
     이제 **볼트 폴더**가 정하고, 뜻은 **불**만 든다. 그래서 여기 있는 것 전부가
     **순수 함수**이고 `node --test` 가 잠근다(`tests/universe.test.mjs`).
   ⚠ **난수도 시간도 없다.** 같은 볼트·같은 경로면 언제나 같은 그림이다 — 그래야
     「내가 놔둔 자리」가 세션을 건너 산다(사이드카 없이).
   ⚠ 같이 죽은 것: 힘 시뮬 넉 장(씨앗 배치·쌍 만들기·예산·흔들기) · 끌어 둔 자리 표 ·
     그것을 세우던 배치 함수 · 사이드카 통로 셋. **옛 이름을 여기 안 적는다** — 걷힘을
     세는 검사(#74 AC7)가 주석을 안 가려서, 적으면 그 자리가 안 걷힌 것으로 세어진다. */

/* FNV-1a 32bit. **UTF-16 코드 단위를 두 바이트(하위·상위)로** 먹인다 — 한글 경로가
   그냥 `charCodeAt` 로 들어가면 상위 바이트가 통째로 버려져 「프로젝트 X」와
   「프로젝트 Y」가 같은 해시가 될 수 있다. 인코딩을 여기 못 박아 두는 이유가 그것이다. */
function fnv1a(s){
  const t=String(s===undefined||s===null?"":s);
  let h=0x811c9dc5>>>0;
  for(let i=0;i<t.length;i++){
    const c=t.charCodeAt(i);
    h=Math.imul(h^(c&0xff),0x01000193)>>>0;
    h=Math.imul(h^((c>>>8)&0xff),0x01000193)>>>0;
  }
  return h>>>0;
}
/* 경로 → 궤도 위의 각도. 3600 등분이라 **한 바퀴가 0.1도 눈금**이다 (#74 B). */
const hashAngle=path=>(fnv1a(path)%3600)/3600*2*Math.PI;
/* 확장자를 뗀 이름. 폴더 note·위성 판정이 이걸로 짝을 맞춘다 — **대소문자는 그대로** 본다
   (맥의 파일계는 안 가리지만 볼트가 리눅스로 건너갈 수 있고, 가리는 쪽이 놀람이 적다). */
const baseName=f=>String(f||"").replace(/\.[^.\/]+$/,"");

/* ★ 한 폴더의 아이들 — **규칙 하나를 재귀로 돌린다** (#74 B).
   그 폴더 바로 아래 md = 아이 · 아이와 **같은 basename** 의 폴더 = 그 아이의 위성 ·
   이름이 안 맞는 폴더 = **작은 중심**(파일 없음, 벡터 없음) + 그 안이 그 중심의 위성.
   ⚠ 항성 폴더에서 부르면 아이 = 행성이고, 행성·중심 폴더에서 부르면 아이 = 위성이다 —
     **깊이의 라벨만 다르고 규칙은 같다**(design.md §1: *"이름 넷은 깊이의 라벨일 뿐"*).
   ⚠ **폴더 note 를 따로 표현하지 않는다.** 항성 폴더 `X/` 아래의 `X.md` 는 그냥 행성이고,
     그래서 항성 평균에도 그냥 든다 — 새 개념을 안 만든 것이 이 규칙의 값이다. */
function folderBodies(dir,prefix){
  const kids=(dir.files||[]).slice().sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0)
    .map(f=>({id:f.p.id,path:f.path,name:baseName(f.file),seed:isSeed(f.p),moons:[],centers:[]}));
  const centers=[];
  Object.keys(dir.dirs||{}).sort().forEach(name=>{
    const path=prefix?prefix+"/"+name:name,b=folderBodies(dir.dirs[name],path);
    centers.push({id:path,path:path,name:name,moons:b.kids,centers:b.centers});
  });
  return {kids:kids,centers:centers};
}
/* ★ 볼트 구조 → 우주 한 판 (#74 B · design.md §1).
   최상위 폴더 = 항성 · 그 아래 md = 행성 · 위는 `folderBodies` 가 재귀로 든다.

   **경로를 못 정하면 그 조각은 `__root`(미분류 항성)의 행성이다** — 규칙 하나다.
   못 정하는 경우 넷: ① id 가 `paths` 에 없음 ② `paths` 자체가 없음(브라우저 단독·아티팩트)
   ③ `/` 로 시작하거나 `..`·`.` 를 품음 ④ 폴더 없이 파일명뿐(진짜 루트 md).
   ⚠ ②가 **선언된 갈림**이다: 브라우저 단독에서는 전부 미분류 항성 하나가 되고, 그것이
     고장이 아니라 정상이다(경로는 Swift 만 안다).
   ⚠ 씨앗은 **트리에 든다.** 빠지는 것은 항성 평균(`sunVector`) 하나다 — 트리에서 빼면
     왼쪽 폴더 트리에서도 사라져 사람이 그 한 장을 영영 못 고친다.
   - Returns: `{id:"__galaxy", name, suns:[…]}` · 항성은 **이름 정렬 순**(각도가 그 순서다) */
function workspaceEntryID(e){return "@file/"+e.id+"/"+e.path}
function workspaceFiles(){
  const files=(DOC.fragments||[]).map(p=>({p,path:PATHS[p.id]||(p.title||p.id)+".md"}));
  const known=new Set(files.map(x=>x.path));
  for(const e of VAULT_ENTRIES){
    if(e.kind==="folder"||known.has(e.path))continue;
    files.push({p:{id:workspaceEntryID(e),title:e.path.split("/").pop(),entry:e},path:e.path});
  }
  return files;
}
function workspaceFile(id){return workspaceFiles().find(f=>f.p.id===id)||null}
function workspaceSelectedID(){return WORKSPACE_SELECTED_ID||(sel!==null&&DOC.fragments[sel]?.id)||null}
function workspaceOpen(id){
  const f=workspaceFile(id);if(!f)return;
  if(!f.p.entry)return openWorkspaceDocument(id);
  if(f.p.entry.manageable===false)return onIndexNotice("이 항목은 탐색과 파일 정리 대상에서 제외됩니다.");
  vaultRequest({action:"openEntry",path:f.path});
}
function vaultTree(fragments,paths,vaultName,folders,entries){
  if(entries){const knownPaths=new Set(Object.values(paths||{}));const extra=entries.filter(e=>e.kind!=="folder"&&!knownPaths.has(e.path));paths=Object.assign({},paths);fragments=(fragments||[]).slice();extra.forEach(e=>{const id=workspaceEntryID(e);paths[id]=e.path;fragments.push({id,title:e.path.split("/").pop(),entry:e})})}
  const P=paths||{},root={dirs:Object.create(null),files:[]},loose=[];
  (fragments||[]).filter(Boolean).forEach(p=>{
    const raw=P[p.id];
    const segs=typeof raw==="string"?raw.split("/"):[];
    const ok=typeof raw==="string"&&raw.charAt(0)!=="/"&&segs.length>1
      &&!segs.some(s=>s===""||s===".."||s===".");
    if(!ok){
      loose.push(p);
      const file=typeof raw==="string"&&segs.length===1&&raw&&raw!=="."&&raw!==".."?raw:(p.title||p.id)+".md";
      root.files.push({p:p,file:file,path:file});return;
    }
    let cur=root;
    for(let i=0;i<segs.length-1;i++){
      if(!cur.dirs[segs[i]])cur.dirs[segs[i]]={dirs:Object.create(null),files:[]};
      cur=cur.dirs[segs[i]];
    }
    cur.files.push({p:p,file:segs[segs.length-1],path:raw});
  });
  (folders||[]).forEach(path=>{
    const segs=String(path).split("/");
    if(segs.some(x=>!x||x==="."||x===".."))return;
    let cur=root;
    segs.forEach(name=>{if(!Object.prototype.hasOwnProperty.call(cur.dirs,name))cur.dirs[name]={dirs:Object.create(null),files:[]};cur=cur.dirs[name]});
  });
  const suns=Object.keys(root.dirs).sort().map(name=>{
    const b=folderBodies(root.dirs[name],name);
    return {id:name,name:name,path:name,planets:b.kids,centers:b.centers};
  });
  /* 미분류 항성은 **파일이 없다** — 폴더가 아니라 「루트에 굴러다니는 것들의 가상 중심」이다.
     각 조각의 각도는 그래서 경로가 아니라 `__root/<id>` 에서 나온다. */
  const looseID=suns.some(s=>s.id==="__root")?"__root/":"__root";
  if(loose.length)suns.push({id:looseID,name:"미분류",path:looseID,virtual:true,centers:[],
    planets:loose.slice().sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0)
      .map(p=>({id:p.id,path:"__root/"+p.id,name:p.title||p.id,seed:isSeed(p),moons:[],centers:[]}))});
  suns.sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0);
  return {id:"__galaxy",name:vaultName||"",suns:suns,filesystem:root};
}
/* 한 항성 아래 **모든 몸**(행성·위성·중심 안까지), 깊이 우선. 중심 자체는 안 든다 —
   중심은 파일이 아니라 폴더라 벡터도 조각 id 도 없다. */
function sunMembers(sun){
  const out=[];
  const walk=node=>{
    (node.planets||node.moons||[]).forEach(k=>{out.push(k);walk(k)});
    (node.centers||[]).forEach(c=>walk(c));
  };
  if(sun)walk(sun);
  return out;
}
/* ★ 면접 범위 넷 (#73 Q20 · ADR 0006 「늘어남: 면접 범위」). 전부 순수 — `node --test` 가 잠근다.
   ⚠ **자를 안 만든다.** 여기서 나오는 것은 `rank` 에 넘길 **후보 집합**뿐이고, 점수·색·눈금은
     그대로다. 「범위 안에서 빨강」은 여전히 빨강이다.
   ⚠ 못 찾은 항성은 **갤럭시로 물러선다** — 볼트가 갈려 그 폴더가 사라졌을 때 면접이 빈 화면이
     되면 안 된다(면접 중에 고칠 수 없는 자리다). */
function liveScopeDefault(tree,last){
  return null; // 사용자가 실사용 화면에서 명시적으로 범위를 좁힐 수 있다.
}
function liveScopeIds(tree,sunId){
  if(!sunId)return null;
  const sun=(((tree||{}).suns)||[]).find(s=>s.id===sunId);
  if(!sun)return null;
  return new Set(sunMembers(sun).map(m=>m.id));
}
/* 갤럭시 → 항성들(트리 순서 = 이름 정렬) → 다시 갤럭시. 항성이 없으면 갤럭시에 머문다. */
function liveScopeCycle(tree,sunId){
  const suns=((tree||{}).suns)||[];
  if(!suns.length)return null;
  const k=suns.findIndex(s=>s.id===sunId);
  return k<0?suns[0].id:(k+1<suns.length?suns[k+1].id:null);
}
function liveScopeName(tree,sunId){
  if(!sunId)return "갤럭시";
  const sun=(((tree||{}).suns)||[]).find(s=>s.id===sunId);
  return sun?sun.name:"갤럭시";
}
/* 면접이 보는 트리 한 판. **캐시 없다** — 면접 중에는 문서가 안 바뀌고, 캐시를 두면
   「언제 버리나」가 새 규칙으로 생긴다. */
const liveTree=()=>vaultTree(DOC.fragments||[],PATHS||{},null,VAULT_FOLDERS,VAULT_ENTRIES);
/* 조각 id → 그 조각이 사는 항성 id. 없으면 `null`. */
function sunOfFragment(tree,id){
  const suns=((tree||{}).suns)||[];
  for(let i=0;i<suns.length;i++)if(sunMembers(suns[i]).some(m=>m.id===id))return suns[i].id;
  return null;
}

/* ── 궤도 ────────────────────────────────────────────────────────────────────
   ★ **몸 크기는 층이다** (design.md §5: *"위성이 행성보다 커지지 않는다"*). */
const BODY_R={sun:18,center:8,planet:10,moon:6};
/* 고리가 못 앉으면 **넓힌다. 각도는 그대로** — 각도가 구조(경로)에서 나온 값이라
   그것을 흔들면 「같은 볼트면 같은 그림」이 깨진다. 8px 씩 최대 20번. */
const RING_GROW=8,RING_TRIES=20,RING_PAD=4;
/* 같은 고리의 **형제끼리만** 본다 — 각도 순으로 돌며 이웃 쌍마다 현이 반지름 합보다 긴가.
   ⚠ `asin` 의 인자가 1 을 넘으면 그 고리에는 앉을 자리가 없다는 뜻이라 **어긴 것으로 센다**
     (NaN 비교는 조용히 통과한다 — 그게 이 검사가 죽는 모양이다). */
function ringOk(R,items){
  if(!(R>0))return false;
  if((items||[]).length<2)return true;
  const s=items.slice().sort((a,b)=>a.ang-b.ang);
  for(let i=0;i<s.length;i++){
    const a=s[i],b=s[(i+1)%s.length];
    const d=i===s.length-1?(b.ang-a.ang+2*Math.PI):(b.ang-a.ang);
    const need=(a.r+b.r+RING_PAD)/R;
    if(!(need<1))return false;
    if(!(d>=2*Math.asin(need)))return false;
  }
  return true;
}
/* 한 쌍 사이에 **최소로 필요한 각도.** 못 앉을 만큼 좁으면 `null` — 부르는 쪽이 고리를 넓힌다 */
function ringNeed(R,a,b){
  const q=(a.r+b.r+RING_PAD)/R;
  return q<1?2*Math.asin(q):null;
}
/* ★ **고리 앉히기는 두 단계다** (#74 B, `실측 2026-09-02` 뒤 보강).
   ① 스펙 그대로 — 8px 씩 최대 20번 넓히며 **해시 각도를 한 도도 안 건드린다.**
      이 단계에서 앉으면 자리는 온전히 구조에서 나온 것이다.
   ② 그래도 안 앉으면 — **간격만 벌린다.** 해시 **순서**와 첫 몸의 각도는 그대로 두고,
      필요한 최소 간격에 비례해 나머지를 다시 나눈다.

   ⚠ **왜 ②가 필요한가** (`실측 2026-09-02`, AC5 의 그 30개 몸): 한 항성에 행성 10개면
     고리는 190px 이고, 20번 넓혀도 350px 이다. 그 위에서 필요한 최소 간격은 0.137rad 인데
     **균등 해시 10개의 최소 간격 기댓값은 2π/n² ≈ 0.063rad** 이라 절반 이상 어긴다 —
     실측에서 두 행성이 15.3px 떨어져 앉았고 필요한 것은 20px 이었다. 즉 ①만으로는
     「겹치지 않는다」가 **성립하지 않는다.** 스펙의 「최대 20회」는 무한 루프를 막는 뚜껑이지
     겹침을 허용한다는 말이 아니라고 읽었다 — 그 판단이 여기 이 갈래다.
   ⚠ ②도 **결정론이다**: 난수도 시간도 안 쓴다. 같은 볼트면 같은 그림이라는 규약이 산다.
   ⚠ ②의 앵커는 **해시 순서의 첫 몸**이다 — 그 각도가 남아야 「구조가 자리를 정한다」가
     완전히 거짓이 되지 않는다. */
function ringFit(R,items){
  let r=R;
  for(let t=0;t<RING_TRIES&&!ringOk(r,items);t++)r+=RING_GROW;
  if(ringOk(r,items)||(items||[]).length<2)return r;
  const s=items.slice().sort((a,b)=>a.ang-b.ang||(a.path<b.path?-1:a.path>b.path?1:0));
  /* 필요한 간격의 **합**이 한 바퀴 안에 들 때까지 넓힌다 — 그때가 앉을 수 있는 최소 고리다 */
  const sum=R2=>{
    let t=0;
    for(let i=0;i<s.length;i++){
      const g=ringNeed(R2,s[i],s[(i+1)%s.length]);
      if(g===null)return null;
      t+=g;
    }
    return t;
  };
  /* 고정 400회의 8px 성장으로는 큰 항성계의 최소 간격 합에 못 닿는다.
     먼저 유한한 상한을 찾고, 그 안을 다시 이분 탐색해 필요한 반지름만 쓴다. */
  const TWO_PI=2*Math.PI,FALLBACK_TRIES=32;
  let low=r,high=r,total=sum(r),feasible=Number.isFinite(total)&&total<=TWO_PI;
  for(let t=0;t<FALLBACK_TRIES&&!feasible;t++){
    low=high;
    const next=Math.max(high+RING_GROW,high*2);
    if(!Number.isFinite(next)||next<=high)break;
    high=next;total=sum(high);feasible=Number.isFinite(total)&&total<=TWO_PI;
  }
  if(feasible){
    for(let t=0;t<FALLBACK_TRIES;t++){
      const mid=Math.ceil(((low+high)/2)/RING_GROW)*RING_GROW;
      if(!(mid>low&&mid<high))break;
      const mt=sum(mid);
      if(Number.isFinite(mt)&&mt<=TWO_PI){high=mid;total=mt}else low=mid;
    }
    r=high;
  }
  const gaps=[];
  let tot=0;
  for(let i=0;i<s.length;i++){const g=ringNeed(r,s[i],s[(i+1)%s.length])||0;gaps.push(g);tot+=g}
  /* 남는 공간은 **비례 배분** — 그래야 좁은 쌍만 붙어 있고 나머지가 뭉치는 그림이 안 난다.
     비정상 입력으로 합을 못 재면 기존 각도를 보존하고 NaN을 퍼뜨리지 않는다. */
  const k=Number.isFinite(tot)&&tot>0?Math.max(1,TWO_PI/tot):1;
  let a=s[0].ang;
  s.forEach((it,i)=>{it.ang=a;a+=gaps[i]*k});
  return r;
}
/* 한 중심체의 아이들을 그 둘레에 앉힌다. **행성과 작은 중심은 같은 고리**다 (#74 B) —
   중심은 행성 하나의 자리를 쓴다. 위성은 한 단계 고리로 모으며 깊은 경로도 그대로 보존한다. 반지름 식(70+ 대 26+)이
   고리끼리 안 겹치게 갈라 둔다. */
function orbitPlace(node,parent,bodies,kind,ringOf){
  const kids=(node.planets||node.moons||[]),cs=(node.centers||[]);
  let all=kids.map(k=>({node:k,kind:kind,r:BODY_R[kind]}))
    .concat(cs.map(c=>({node:c,kind:"center",r:BODY_R.center})));
  if(kind==="moon"){
    all=[];
    const collect=n=>{
      (n.moons||[]).forEach(k=>{all.push({node:k,kind:"moon",r:BODY_R.moon});collect(k)});
      (n.centers||[]).forEach(c=>{all.push({node:c,kind:"center",r:BODY_R.center});collect(c)});
    };
    collect(node);
  }
  if(!all.length)return;
  all.forEach(a=>{a.ang=hashAngle(a.node.path);a.path=a.node.path});
  const R=ringFit(ringOf(all.length),all);
  all.forEach(a=>{
    const b={id:a.node.id,kind:a.kind,parent:parent.id,path:a.node.path,name:a.node.name||"",
      seed:!!a.node.seed,r:a.r,ring:R,ang:a.ang,cx:parent.x,cy:parent.y,
      x:parent.x+Math.cos(a.ang)*R,y:parent.y+Math.sin(a.ang)*R};
    bodies.push(b);
    if(kind!=="moon")orbitPlace(a.node,b,bodies,"moon",m=>26+6*m);
  });
}
/* 한 항성계가 차지하는 반지름 — **그 항성에서 제일 먼 몸까지.** 항성 고리를 정하는 데 든다 */
function sunSpan(sun){
  const probe=[],anchor={id:sun.id,x:0,y:0};
  orbitPlace(sun,anchor,probe,"planet",m=>70+12*m);
  let far=BODY_R.sun;
  probe.forEach(b=>{far=Math.max(far,Math.hypot(b.x,b.y)+b.r)});
  return far;
}
/* ★ 트리 → 좌표. **결정론이다** (#74 B AC5). 항성은 갤럭시 중심 둘레에 **인덱스 균등**,
   그 아래는 전부 경로 해시 각도다.
   ⚠ 시간이 안 들어간다 — 공전(움직임)은 이번 덩이 밖이다(#74 Out of Scope).

   ★ **항성 고리는 스펙 식의 하한이지 그 값이 아니다** (`실측 2026-09-02` 실화면 뒤 보강).
     스펙은 `220 + 40·(항성 수-1)` 이라고만 했는데, 그러면 **행성이 갤럭시 중심을 덮는다**:
     조각 6장짜리 항성의 행성 고리는 겹침 보정 뒤 262 이고 항성 고리는 260 이라, 중심을
     향한 행성 하나가 **커맨드 센터(태양) 위에 그대로 앉았다** — 진짜 포인터로 태양을 눌렀더니
     `f4/planet` 이 잡혔다(포인터 착지 좌표로 실측, memory `qa-must-click-with-real-pointer`).
     그래서 항성 고리에 조건을 하나 더 건다: **어느 항성계도 커맨드 센터를 안 먹는다.**
   ⚠ 항성끼리의 겹침도 **몸이 아니라 계**로 잰다 — 항성 둘이 18px 만 떨어져 있어도 그 아래
     행성 스무 개가 서로를 통과하면 그림이 무너진다.
   - Returns: `{bodies:[{id,kind,x,y,parent,r,path,ring,ang,cx,cy}], center:{x,y}}` */
function orbitLayout(tree,opts){
  const o=opts||{};
  const cx=o.cx===undefined?CV_W/2:o.cx,cy=o.cy===undefined?CV_H/2:o.cy;
  const suns=((tree||{}).suns)||[],n=suns.length,bodies=[];
  /* 겹침은 **계 반지름**으로 잰다 — 항성 하나가 아니라 그 아래 전부가 차지하는 넓이다 */
  const items=suns.map((s,i)=>({node:s,kind:"sun",r:sunSpan(s),path:s.path||s.id,
    ang:n?2*Math.PI*i/n:0}));
  /* 커맨드 센터가 안 먹히는 하한 — 제일 넓은 계도 중심에서 이만큼 비켜 있어야 한다 */
  const clear=items.reduce((a,it)=>Math.max(a,it.r),0)+CV_ORB+28;
  /* ★ **항성이 하나면 그 하나가 곧 갤럭시다** (`실측 2026-09-02` 박선호 실앱: 폴더 없는 볼트에서
     미분류 항성이 가운데, 태양이 220 아래 따로 떠 큰 원을 그렸다). 반지름 0 — 태양 자리에 겹치고
     몸은 안 그린다(`solo`). 견줄 항성이 생기는 순간(폴더 하나) 제 궤도로 나간다. */
  const R=n===1?0:ringFit(Math.max(220+40*Math.max(0,n-1),clear),items);
  items.forEach(it=>{
    const b={id:it.node.id,kind:"sun",parent:null,path:it.node.path||it.node.id,virtual:!!it.node.virtual,solo:n===1,
      name:it.node.name,seed:false,r:BODY_R.sun,ring:R,ang:it.ang,cx:cx,cy:cy,
      x:cx+Math.cos(it.ang)*R,y:cy+Math.sin(it.ang)*R};
    bodies.push(b);
    orbitPlace(it.node,b,bodies,"planet",m=>70+12*m);
  });
  return {bodies:bodies,center:{x:cx,y:cy}};
}

/* ── 공전 (#75) — **자리는 구조, 시간은 위상** ───────────────────────────────
   ★ #74 가 자리를 구조에서 뽑았고 여기서 그 위에 **시간**만 얹는다. 배치(`orbitLayout`)는
     한 글자도 안 바뀐다 — 각도가 그 기준각(`base`)에서 시작해 돌 뿐이다. 그래서 공전을
     꺼도(reduced-motion) 그림은 #74 의 그 그림이다.
   ⚠ **여기 있는 것은 전부 순수 함수다** — rAF 루프(`canvasTick`)가 매 프레임 부르는 계산이고,
     `node --test`(`tests/orbit.test.mjs`)가 잠근다. 루프 자체는 브라우저가 잰다.
   ⚠ 값은 design.md §4 가 같은 수를 든다. 갈리면 그건 표류다. */
/* 한 바퀴에 몇 초 — **안쪽이 빠르다**(케플러 느낌). 항성 6분 · 행성 3분 · 위성 1.5분.
   ⚠ 작은 중심은 행성과 **같은 고리**라 같은 주기다 — 다르면 같은 고리 위 두 몸이 서로를 통과한다. */
const ORBIT_PERIOD={sun:360,center:180,planet:180,moon:90};
/* 스치면 그 계가 1/4 속도 · 켜지면 2배로 시작해 2.5초에 걸쳐 제 속도로 (design.md §4) */
const ORBIT_HOVER=.25,ORBIT_BOOST=2,ORBIT_BOOST_MS=2500;
/* ★ 각도 = **기준각 + 흘러간 시간의 위상.** 결정론·주기적이다.
   ⚠ 나머지 연산으로 접는다 — `t` 와 `t+period` 가 **같은 부동소수**를 내야 「한 바퀴 뒤
     같은 자리」가 참이 된다. 음수 `t` 도 접힌다(rAF 시각이 t0 보다 앞설 수 있다). */
function orbitAngle(base,t,period){
  const P=period>0?period:1,u=((((t||0)%P)+P)%P)/P;
  return (base||0)+2*Math.PI*u;
}
/* 몸 하나의 속도 배수 — **호버(계 단위)와 가속(몸 단위)이 곱해진다.**
   `boostAge` = 켜진 뒤 지난 ms(안 켜졌으면 `null`). 2.5초가 지나면 정확히 1로 돌아온다. */
function orbitFactor(hover,boostAge){
  const h=hover?ORBIT_HOVER:1;
  /* ⚠ `null>=0` 은 **참**이다(0 으로 강제된다) — 안 켜진 몸이 조용히 2배로 도는 자리라
     `null`·`undefined` 를 먼저 걷어낸다. */
  if(boostAge===null||boostAge===undefined||!(boostAge>=0)||boostAge>=ORBIT_BOOST_MS)return h;
  const k=1-boostAge/ORBIT_BOOST_MS;
  return h*(1+(ORBIT_BOOST-1)*k*k);
}
/* 카메라 글라이드 — **400ms · ease-out** (#75 4). 파동의 감속(`1-(1-u)²`)과 같은 곡선이다:
   움직임 어휘를 하나로 둔다 (design.md §4). */
const GLIDE_MS=400;
const cvEase=u=>{const c=Math.max(0,Math.min(u||0,1));return 1-(1-c)*(1-c)};
/* 뷰 변환 한 걸음 — **순수 보간.** 원본을 안 건드린다(프레임마다 부르는 자리다) */
function glideVT(from,to,u){
  const e=cvEase(u);
  return {k:from.k+(to.k-from.k)*e,x:from.x+(to.x-from.x)*e,y:from.y+(to.y-from.y)*e};
}
/* 그 몸을 판 한가운데 놓는 뷰 변환. **줌은 들고 있던 것 그대로** — 글라이드는 옮기기지 확대가 아니다 */
function glideTarget(b,w,h,k){
  const z=k>0?k:1;
  return {k:z,x:w/2-b.x*z,y:h/2-b.y*z};
}
/* ★ 루프가 자는 조건 — **넷이다.** 순수 함수라 시험이 그 넷을 그대로 잰다
   (`document.hidden`·`matchMedia` 를 흉내내기 시작하면 화면 코드를 복제하게 된다).
   ⚠ 모르면 **멈추는 쪽**이다 — 인자가 없으면 잔다.
   - Returns: 자는 이유 한 낱말 · 깨어 있어야 하면 `""` */
function canvasSleepWhy(s){
  const o=s||{};
  if(o.hidden)return "hidden";
  if(o.reduced)return "reduced-motion";
  if(!o.shown)return "not-shown";
  if(!o.moving)return "idle";
  return "";
}
/* 몸 → 그 몸이 속한 항성 id(항성 자신이면 자기). **호버 슬로우가 계 단위**라 이게 필요하다.
   ⚠ 깊이를 여덟으로 막는다 — 부모 고리가 어쩌다 순환하면 프레임 하나가 영영 안 끝난다. */
function bodySun(by,id){
  let n=by?by[id]:null,g=0;
  while(n&&n.kind!=="sun"&&n.parent&&g++<8)n=by[n.parent];
  return (n&&n.kind==="sun")?n.id:null;
}
/* 폴더 하나를 **조상까지 편다** — 접힌 부모 안의 항성은 펴 봐야 안 보인다 (#75 4).
   ⚠ 원본을 안 고친다: 그리는 중에 전역이 갈리면 한 화면이 두 말을 한다. */
function treeReveal(zip,path){
  const out=Object.assign({},zip||{});
  let cur="";
  String(path||"").split("/").forEach(s=>{cur=cur?cur+"/"+s:s;delete out[cur]});
  return out;
}

/* ── 두 단계 검색 (#74 B · ADR 0006) ─────────────────────────────────────────
   ★ **자를 새로 안 만들었다.** 코사인은 `cosv`, 눈금은 `SIM_G_DIRECT`, 색은 `eris` —
     라이브 검색이 쓰는 그것 그대로다. 더한 것은 **무엇을 재느냐**(항성 평균)뿐이다. */
/* 항성 하나의 뜻 = **그 안 조각 벡터의 정규화 평균.** 씨앗은 빼고 위성·폴더 note 는 넣는다.
   ⚠ 잴 것이 하나도 없으면 `null` — 그 항성은 목록에서 빠지고 화면에서 무채색이다.
     글자 자로 안 내려간다(눈금이 다르다, #34). */
function sunVector(sunId,tree,vec){
  const sun=(((tree||{}).suns)||[]).find(s=>s.id===sunId);
  const fv=((vec||{}).frags)||{};
  if(!sun)return null;
  let acc=null,n=0;
  sunMembers(sun).forEach(m=>{
    if(m.seed)return;
    const v=fv[m.id];
    if(!v||!v.length)return;
    if(!acc)acc=new Float32Array(v.length);
    if(acc.length!==v.length)return;
    for(let i=0;i<v.length;i++)acc[i]+=v[i];
    n++;
  });
  if(!n||!acc)return null;
  let s=0;
  for(let i=0;i<acc.length;i++)s+=acc[i]*acc[i];
  s=Math.sqrt(s);
  if(!(s>0))return null;
  for(let i=0;i<acc.length;i++)acc[i]/=s;
  return acc;
}
/* ★ **항성 한 개의 점수 — 자가 사는 자리는 이 함수 하나다** (#74, 실측 뒤 격리).
   `rule` 이 갈래 이름이고 **기본은 `"max"`** 이다 (박선호 결정 2026-09-02, 스펙 B3 의
   항성 단계를 대체한다 — 옵시디언 식 **상대 순위**, 항성 색은 최고 멤버의 등급):

   | `rule` | 항성 점수 | 자동 진입 |
   |---|---|---|
   | `"max"` (기본) | 그 항성 **최고 멤버**의 정규화 점수 — 색은 **길잡이**다 | 없다. 사람이 누른다 |
   | `"centroid"` | 항성 평균 벡터와의 코사인 ÷ 초록선 (스펙 B3 원안) | `SUN_MARGIN` 차이면 자동 |

   ★ **왜 갈아탔나** (`실측 2026-09-02`, `tests/fixtures/universe_two_suns.json`, 같은 벡터):
     평균(`centroid`)은 AC1-3 을 못 넘겼다 — 정답 1위 항성 **5/8** · 상위 3 안 **4/8** ·
     밖 질의가 초록 아님 **0/2** 이고 밖 질의 둘 다 자동 진입했다. 최고 멤버·평균 빼기도
     정답 2~3/8 로 더 나빴다. 원인은 e5 의 **눌린 눈금**이다: 항성 평균이 「면접 말투」라는
     공통 방향을 모아서 거의 모든 항성이 초록이 된다.
   ⚠ **수를 손으로 맞춰서 통과시키지 않았다.** 자를 바꾸는 것은 결정 사항이고(ADR 0006
     다시 열 조건 ①: 외부 판정자), 그때 갈아끼우는 자리가 **이 함수 하나**가 되도록
     갈래 이름을 인자로 뽑아 뒀다. `SUN_MARGIN` 은 `"centroid"` 갈래에서만 산다.
   - Returns: 정규화 점수(1.0 = 초록선) · 못 재면 `null` */
const SUN_MARGIN=0.08;
function sunScore(qv,sunId,tree,vec,rule){
  const how=rule||"max";
  const sun=(((tree||{}).suns)||[]).find(s=>s.id===sunId);
  if(!qv||!vec||!sun)return null;
  if(how==="max"){
    /* 그 항성 최고 멤버 — **`escore` 그대로다.** 갤럭시 전체 순위(`rank`)가 쓰는 그 자라,
       항성 색과 그 아래 별의 색이 **같은 눈금**에서 나온다. */
    let best=null;
    sunMembers(sun).forEach(m=>{
      if(m.seed)return;
      const n=escore(m,qv,vec);
      if(n===null)return;
      if(best===null||n>best)best=n;
    });
    return best;
  }
  if(how!=="centroid")return null;
  const v=sunVector(sunId,tree,vec);
  if(!v)return null;
  const c=cosv(qv,v);
  return c===null?null:c/SIM_G_DIRECT;
}
/* ★ 1단 — **갤럭시 전체를 한 번에 재고, 항성 색은 길잡이로 든다** (박선호 결정 2026-09-02).
   순위 자체는 `rank()`(평면)가 내고, 이 함수가 더하는 것은 **어느 항성이 뜨거운가**뿐이다.
   ⚠ **자동 진입이 없다** — `scoped` 는 사람이 항성을 눌렀을 때만 값이 된다.
     `"centroid"` 갈래에서만 `margin ≥ SUN_MARGIN` 으로 자동 진입한다(그 갈래는 지금 안 쓴다).
   ⚠ **질의 벡터가 없으면 이 단계를 통째로 건너뛴다** — `measured:false` 로 말하고,
     부르는 쪽이 지금까지의 평면 글자 검색으로 돌아간다(선언된 갈림, `cvhow` 가 적는다).
   - Returns: `{suns:[{id,s,c}], scoped:항성id|null, margin, measured, rule}` */
function searchGalaxy(q,qvec,tree,vec,rule){
  const how=rule||"max";
  const qv=(qvec&&qvec.v&&qvec.q===q)?qvec.v:null;
  if(!qv||!vec)return {suns:[],scoped:null,margin:0,measured:false,rule:how};
  const rows=[];
  (((tree||{}).suns)||[]).forEach(s=>{
    const n=sunScore(qv,s.id,tree,vec,how);
    if(n===null||n!==n)return;
    rows.push({id:s.id,s:n,c:eris(n)});
  });
  rows.sort((a,b)=>b.s-a.s||(a.id<b.id?-1:a.id>b.id?1:0));
  const margin=rows.length>1?rows[0].s-rows[1].s:0;
  /* ★ **항성이 하나면 규칙과 상관없이 진입한다** — 고를 것이 없는데 사람에게 누르라고 하면
     새 볼트(미분류 항성 하나)의 첫 질문이 행성 하나 안 켜고 끝난다(`실측 2026-09-02` 아티팩트).
     margin 자동 진입은 centroid 규칙에만 남는다(현실 볼트 실측: max 규칙엔 근거가 없다). */
  const scoped=rows.length===1?rows[0].id
    :(how==="centroid"&&rows.length>1&&margin>=SUN_MARGIN?rows[0].id:null);
  return {suns:rows,scoped:scoped,margin:margin,measured:true,rule:how};
}
/* ★ 2단 — **그 항성 안에서.** `rank()` 가 낸 줄을 그 항성의 조각으로 거른 것뿐이다.
   ⚠ 자를 안 바꾼다 — 거르기만 한다. 그래서 항성 안 순서와 라이브 카드의 순서가 같다. */
function searchSun(q,qvec,sunId,tree,vec){
  const sun=(((tree||{}).suns)||[]).find(s=>s.id===sunId);
  if(!sun)return [];
  const ids={};
  sunMembers(sun).forEach(m=>{ids[m.id]=true});
  return rank(q,qvec,vec).filter(x=>Object.prototype.hasOwnProperty.call(ids,x.p.id));
}

/* 배치를 다시 세워야 하나 — **조각 목록과 그 경로**가 서명이다 (#74 B).
   ⚠ 전 판은 색인된 조각 수도 서명이었다 — 자리가 뜻에서 나왔기 때문이다. 이제 안 본다:
     색인이 도착해도 **별은 안 움직인다.** 움직이면 그것이 곧 「자리는 구조」의 거짓말이다. */
const canvasSig=(fragments,paths)=>(fragments||[]).map(p=>p.id+">"+(((paths||{})[p.id])||"")).join("|");
/* 한 판을 세운다. 서명이 같으면 **살려 둔다** — 사람이 끌어 둔 위상이 저장 한 번에 안 날아가게. */
/* 서명은 **여기 한 자리**에서만 잰다 — 묻는 쪽과 짓는 쪽이 다른 무리를 쓰면 씨앗 한 장에
   판이 매번 다시 지어진다(#74·#75 리뷰). 무리 = 씨앗 포함 `DOC.fragments`. */
const canvasSigNow=()=>canvasSig(DOC.fragments||[],PATHS)+"/folders:"+VAULT_FOLDERS.join("|")+"/entries:"+VAULT_ENTRIES.map(e=>e.id+":"+e.path).join("|")+"/scope:"+WORKSPACE_SCOPE;
function workspaceFolderID(path){return "@folder/"+path}
/* A fixed projection keeps map controls two dimensional. Nested, separated ellipses
   encode file orbits; folders are stationary destinations beyond this system. */
function workspaceOrbitPoint(n,angle){
  const tilt=(n.tilt||0)+(n.viewRoll||0),c=Math.cos(tilt),s=Math.sin(tilt);
  const x=Math.cos(angle)*n.ring,y=Math.sin(angle)*n.ring*(n.flatten||1);
  const z=n.fixed?0:(Math.sin(angle)*.97+Math.sin(angle+(n.orbitIndex||0))*.25)*n.ring;
  const scale=n.perspectiveBase?Math.max(.45,1+z/(n.perspectiveBase*1.85)):1;
  return {x:(x*c-y*s)*scale,y:(x*s+y*c)*scale,z,scale};
}
function workspaceOrbitAngle(n,x,y){
  const tilt=(n.tilt||0)+(n.viewRoll||0),c=Math.cos(tilt),s=Math.sin(tilt);
  return Math.atan2((-x*s+y*c)/(n.flatten||1),x*c+y*s);
}
function workspaceOrbitPath(n){
  const still=Object.assign({},n,{viewRoll:0});
  return Array.from({length:73},(_,i)=>{const p=workspaceOrbitPoint(still,i/72*2*Math.PI);return `${i?"L":"M"}${p.x.toFixed(2)} ${p.y.toFixed(2)}`}).join(" ")+" Z";
}
function workspaceScene(tree,path){
  let dir=tree.filesystem;
  for(const segment of (path||"").split("/").filter(Boolean)){dir=dir?.dirs?.[segment];if(!dir)return null}
  const center={x:CV_W/2,y:CV_H/2},bodies=[];
  const id=path?workspaceFolderID(path):"@workspace-root";
  if(path)bodies.push({id,kind:"sun",path,name:path.split("/").pop(),parent:null,r:26,ring:0,ang:0,cx:center.x,cy:center.y,x:center.x,y:center.y});
  const folders=Object.keys(dir.dirs||{}).sort();
  const files=(dir.files||[]).slice().sort((a,b)=>a.path.localeCompare(b.path));
  const rings=[];
  let capacity=0;
  for(let i=0;i<Math.max(1,files.length)&&(capacity<files.length||i<Math.min(3,files.length));i++){
    const radius=160+i*104,cap=Math.max(4,Math.floor(2*Math.PI*radius*.62/76));
    rings.push({radius,cap,files:[]});capacity+=cap;
  }
  let cursor=0;
  files.forEach(f=>{while(rings[cursor%rings.length].files.length>=rings[cursor%rings.length].cap)cursor++;rings[cursor++%rings.length].files.push(f)});
  const outer=rings.length?rings[rings.length-1].radius:160;
  const starRadius=Math.max(outer+150,folders.length*84/(2*Math.PI*.72));
  const place=(n,ring,ang,extra)=>{
    Object.assign(n,{parent:path?id:null,ring,ang,cx:center.x,cy:center.y},extra);
    const p=workspaceOrbitPoint(n,ang);n.x=center.x+p.x;n.y=center.y+p.y;n.depth=p.z;
    bodies.push(n);
  };
  folders.forEach((name,i)=>place({id:workspaceFolderID(path?path+"/"+name:name),path:path?path+"/"+name:name,name,kind:"sun",r:18},starRadius,2*Math.PI*i/Math.max(1,folders.length)-.65,{fixed:!!path,flatten:.72,tilt:-.18,period:ORBIT_PERIOD.sun}));
  const dense=files.length>36;
  rings.forEach((ring,j)=>ring.files.forEach((f,i)=>place({id:f.p.id,path:f.path,name:f.file,kind:"planet",r:14},ring.radius,2*Math.PI*i/ring.files.length+j*1.37,{flatten:dense?.62:.28+(j%3)*.15,tilt:dense?-.18:-.5+(j%3)*.44,period:dense?100+j*65:34+j*14,orbitIndex:j,perspectiveBase:dense?0:outer})));
  return {bodies,center};
}
function canvasUniverse(){
  /* ★ **씨앗도 트리에 든다** (matt Spec 리뷰 2026-09-02). `canvasFrags()` 는 씨앗을 빼는 무리라
     여기서 쓰면 새 볼트의 예시 한 장이 왼쪽 트리에서도 사라져 사람이 영영 못 고친다.
     씨앗이 빠지는 자리는 **벡터 평균과 순위**(`sunVector`·`rank`)이지 그림이 아니다. */
  const F=DOC.fragments||[],sig=canvasSigNow();
  if(CANV&&CANV.sig===sig&&CANV.vault===SYS.vault)return CANV;
  const previous=CANV&&CANV.vault===SYS.vault?CANV:null;
  /* ⚠ **옛 판의 루프를 먼저 끊는다** (matt Standards 리뷰 #75). 안 끊으면 저장·받기마다 새 판이
     생기는데 옛 프레임이 새 판을 읽고 다시 예약해 루프가 둘, 셋으로 는다 — CPU 0 이 거짓이 된다. */
  canvasStop();
  const tree=vaultTree(F,PATHS,null,VAULT_FOLDERS,VAULT_ENTRIES);
  let lay=workspaceScene(tree,WORKSPACE_SCOPE);if(!lay){WORKSPACE_SCOPE="";lay=workspaceScene(tree,"")}
  const by={};
  lay.bodies.forEach(b=>{by[b.id]=b});
  /* ★ 공전이 몸마다 드는 것 넷 (#75). **배치는 안 건드린다** — `base` 가 `orbitLayout` 이 낸
     그 각도이고, 시계(`clk`)가 0 인 첫 프레임은 #74 의 그 그림이다.
     `phase` = 사람이 끌어 놓은 위상 · `boost` = 켜진 시각(0 = 안 켜짐) ·
     `sun` = 그 몸의 계(호버 슬로우가 계 단위다) · `reach` = 갤럭시 중심에서 닿는 최대 거리. */
  lay.bodies.forEach(b=>{
    b.base=b.ang;b.phase=0;b.clk=0;b.boost=0;
    b.sun=WORKSPACE_SCOPE||"@workspace-root";b.period=b.period||ORBIT_PERIOD.planet;
    if(!b.ring)b.fixed=true;
    const p=b.parent?by[b.parent]:null;
    b.reach=(p?p.reach:0)+b.ring;
  });
  CANV={sig:sig,vault:SYS.vault,tree:tree,nodes:lay.bodies,by:by,gc:lay.center,scoped:null,
        vt:{k:1,x:0,y:0},els:null,last:null,wave:null,src:null,
        /* 공전 루프가 드는 것 — 프레임 id · 지난 프레임 시각 · 스치고 있는 몸 · 카메라 글라이드 */
        anim:{raf:0,last:0},hover:null,glide:null};
  if(previous){
    const folders=new Set(vaultRows(tree,{}).filter(r=>r.folder).map(r=>r.path));
    const valid=frame=>!frame.path||folders.has(frame.path);
    const current={id:previous.focusID||null,path:previous.focusPath||null,scoped:previous.scoped||null,follow:previous.follow||null,vt:previous.vt};
    CANV.navStack=(previous.navStack||[]).filter(valid);
    CANV.forwardStack=(previous.forwardStack||[]).filter(valid);
    CANV.relatedID=workspaceFile(previous.relatedID)?previous.relatedID:null;
    const kept=valid(current)?current:(CANV.navStack.pop()||{id:null,path:null,scoped:null,vt:previous.vt});
    CANV.focusID=kept.id;CANV.focusPath=kept.path;
    CANV.scoped=tree.suns.some(n=>n.id===kept.scoped)?kept.scoped:null;
    CANV.vt=Object.assign({},kept.vt);CANV.follow=kept.follow||null;CANV.restoreVT=true;
  }
  CANV.focusPath=WORKSPACE_SCOPE||null;CANV.focusID=WORKSPACE_SCOPE?workspaceFolderID(WORKSPACE_SCOPE):null;CANV.scoped=WORKSPACE_SCOPE||null;
  return CANV;
}
/* 그림에 앉는 **조각 몸**(행성·위성)만. 항성·작은 중심은 파일이 아니라 폴더다 */
const canvasStars=L=>(((L||{}).nodes)||[]).filter(n=>n.kind==="planet"||n.kind==="moon");

/* ★ 한 판의 「어느 몸이 어떤 모습이 되나」 — **순수 함수**라 `node --test` 가 잠근다.
   색(`c`)도 점수(`s`)도 `rank()`/`searchSun()` 이 준 것을 **그대로 나른다.** 여기서 다시 안 잰다.
   ★ **빨강은 어디서도 안 켜진다** (박선호 결정 2026-09-02, 실측 볼트 61장 뒤).
     `lit = c !== "r"` 이 **범위 안에서도** 그대로다 — 스펙의 「항성 안은 전부 켠다」는 걷혔다.
     빨강 = 반응 없음(가라앉음 `.24`)이고, 그래야 켜진 것이 곧 「답이 있다」로 읽힌다.
   ★ **범위(항성)가 하는 일은 하나다**: 그 항성 밖을 **통째로 가라앉힌다**(색을 안 낸다).
   ⚠ 빈 상태 판정 = **초록도 주황도 하나도 없나**. 자를 다시 안 잰다 — `eris` 가 낸 색을 읽는다.
   ⚠ 결과는 **근원에서 가까운 차례**다. 파동이 그 순서로 켠다 — 손으로 준 딜레이가 아니다. */
function canvasPlan(res,stars,center,topN,opt){
  const scope=(opt&&opt.scope)||null;
  const inScope=id=>!scope||Object.prototype.hasOwnProperty.call(scope,id);
  /* 빈 상태 = **범위 안에 초록도 주황도 없다.** 1위 하나만 보던 전 판과 결론은 같고,
     범위가 생긴 뒤에도 참이려면 「범위 안에서」라는 말이 붙어야 한다. */
  const empty=!(res||[]).some(x=>x.c!=="r"&&inScope(x.p.id));
  const by={};
  (res||[]).forEach((x,k)=>{by[x.p.id]={c:x.c,s:x.s,k:k}});
  const top={};
  if(!empty)(res||[]).filter(x=>inScope(x.p.id)).slice(0,topN).forEach((x,k)=>{top[x.p.id]=k+1});
  const items=(stars||[]).map(n=>{
    const x=by[n.id]||null,c=x?x.c:"r";
    const sc=inScope(n.id);
    /* ⚠ **강조는 켜진 것 중에서만** 나온다 — 가라앉은 몸에 테를 두르면 화면이
       「이것도 답이다」라고 말한다. */
    const lit=sc&&!empty&&c!=="r";
    return {id:n.id,kind:n.kind,c:c,s:x?x.s:null,rank:x?x.k:null,
            lit:lit,scope:sc,top:lit?(top[n.id]||0):0,
            dist:Math.hypot(n.x-center.x,n.y-center.y)};
  }).sort((a,b)=>a.dist-b.dist);
  const map={};
  items.forEach(it=>{map[it.id]=it});
  return {empty:empty,items:items,by:map,scoped:scope?(opt.sunId||null):null,suns:(opt&&opt.suns)||null};
}
/* ★ 질의 구슬에서 몸으로 뻗는 선 하나 — **굵기와 색이 곧 그 몸의 등급이다.**
   ⚠ **새 자도 새 문턱도 안 만들었다**: 색은 `rank()` 가 준 `c` 그대로, 굵기는
     주황선~초록선 사이의 자리 `t` 다.
   ⚠ **빨강을 선에 안 칠한다** — 가라앉은 것은 가라앉게 둔다. 선이 드는 뜻은
     그 몸이 이미 든 뜻과 같다(새 어휘가 아니라 채색의 연장). */
function beamStyle(c,s,green,amber){
  if(c==="r"||s===null||s===undefined||!(green>amber))return {s:"var(--t4)",w:.6,o:0};
  const t=Math.max(0,Math.min((s-amber)/(green-amber),1)),r=x=>Math.round(x*100)/100;
  return {s:c==="g"?"var(--acc)":"var(--warn)",w:r(.8+2.2*t),o:r(.26+.44*t)};
}
/* ★ 몸의 밝기 = 일치도 (목업 `paintNode`). 켜진 것 .55+.45·t · 안 켜진 것 .24 ·
   **고른 것은 .7 아래로 안 잠긴다**(놓치면 안 되니까) · 쉴 때 1.
   반지름은 안 건드린다 — 크기는 **층**(항성>행성>위성)이라 측정이 그것을 흔들면 층이 거짓말이 된다. */
const isSelId=id=>workspaceSelectedID()===id;
const litOpacity=(lit,t,id)=>lit?String(Math.round((.55+.45*Math.max(0,Math.min(t,1)))*100)/100):(isSelId(id)?".7":".24");
/* 사람에게 보이는 수 — **원값이 아니라 준비선 대비 %** 다 (#67 확정 ⑤ · #61 E). */
const readyPct=(s,green)=>Math.round(s/green*100);

/* ── 그리기 ─────────────────────────────────────────────────────────────── */
/* `prefers-reduced-motion` — **함수 안에서 묻는다.** 최상위에서 물으면 `matchMedia` 가 없는
   자리(`tests/screen-load.mjs`)에서 화면 전체가 안 떠진다. */
const cvReduced=()=>{try{return matchMedia("(prefers-reduced-motion: reduce)").matches}catch(e){return false}};
/* ★ **지금 자리가 아니라 궤도가 상자를 정한다** (#75). 공전이 붙기 전에는 순간 좌표의
   경계 상자였는데, 그러면 몸이 돌 때마다 상자가 숨쉬고 **다음 「화면 맞춤」마다 줌이 튄다** —
   같은 볼트가 프레임에 따라 다른 크기로 뜨는 자리다. 그래서 **각 몸이 닿을 수 있는 최대
   거리**(`reach` = 부모 고리들의 합)로 잰다: 상자가 시간에 안 흔들린다.
   ★ **갤럭시 중심의 태양도 판 안이다** (#70) — 별이 한둘이어도 커맨드 센터가 안 밀려난다. */
function canvasBox(){
  const L=CANV,G=(L&&L.gc)||{x:CV_W/2,y:CV_H/2};
  if(!L||!L.nodes.length)return {x:0,y:0,w:CV_W,h:CV_H};
  let rx=CV_ORB+16,ry=CV_ORB+16;
  L.nodes.forEach(n=>{
    const a=n.ring,b=a*(n.flatten||1),pad=n.r+32;
    if(n.perspectiveBase){rx=Math.max(rx,a*1.66+pad);ry=Math.max(ry,a*1.15+pad)}
    else{const c=Math.cos(n.tilt||0),s=Math.sin(n.tilt||0);rx=Math.max(rx,Math.hypot(a*c,b*s)+pad);ry=Math.max(ry,Math.hypot(a*s,b*c)+pad)}
  });
  return {x:G.x-rx,y:G.y-ry,w:rx*2,h:ry*2};
}
/* 파동과 구슬이 나는 자리 = **갤럭시 중심.** 궤도가 그 둘레라 이 점이 곧 우주의 원점이다. */
function canvasCenter(){const L=CANV;return (L&&L.gc)?{x:L.gc.x,y:L.gc.y}:{x:CV_W/2,y:CV_H/2}}
/* 몸 하나의 class — **상태에서 매번 다시 짓는다.** 켜기와 고르기가 각자 class 를 더하면
   한쪽이 다른 쪽을 지운다(`setAttribute("class")` 는 통째로 덮는다). */
function canvasNodeClass(id){
  const L=CANV,b=L?L.by[id]:null,it=(L&&L.last)?L.last.by[id]:null;
  const kind=b?b.kind:"planet";
  const base="cvn k"+kind+(isSelId(id)?" sel":"");
  /* 항성은 **1단(항성 검색)의 색**을 든다 — 그 아래 별들과 다른 자에서 온 색이라 자리를 갈라 뒀다 */
  if(kind==="sun"){
    const su=(L&&L.last&&L.last.suns)?L.last.suns[id]:null;
    return base+(L&&L.focusID===id?" scoped":"")
      +(su?(su.c==="g"?" lit-g":su.c==="a"?" lit-a":" lit-r"):"");
  }
  if(kind==="center")return base+(L&&L.focusID===id?" scoped":"");
  return base+(!it||it.self?"":((it.top?" top"+(it.top>1?" k"+it.top:""):"")
    +(it.lit?(it.c==="g"?" lit-g":it.c==="a"?" lit-a":" lit-r"):" dim")));
}
function canvasApplyVT(){
  const L=CANV;if(!L||!L.els)return;
  L.els.root.setAttribute("transform",`translate(${L.vt.x} ${L.vt.y}) scale(${L.vt.k})`);

}
/* 몸을 궤도 위에 다시 앉힌다 — **각도와 부모 좌표에서 좌표를 다시 낸다.**
   끌기가 바꾸는 것은 `ang` 하나이고 `ring` 은 안 건드린다(#74 C1: *"위상만"*). */
function canvasReflow(){
  const L=CANV;if(!L)return;
  const G=L.gc||{x:CV_W/2,y:CV_H/2};
  L.nodes.forEach(n=>{
    const p=n.parent?L.by[n.parent]:null;
    n.cx=p?p.x:G.x;n.cy=p?p.y:G.y;
    n.viewRoll=n.fixed||!n.perspectiveBase?0:(L.viewRoll||0);
    const pos=workspaceOrbitPoint(n,n.ang);
    n.x=n.cx+pos.x;n.y=n.cy+pos.y;n.depth=pos.z;n.displayScale=pos.scale;
  });
}
/* 선의 양 끝을 조금씩 잘라 둔다 — 구슬과 몸의 발광에 안 닿게 */
function canvasPlace(){
  const L=CANV;if(!L||!L.els)return;
  const C=canvasCenter();
  L.els.orb.setAttribute("transform",`translate(${C.x} ${C.y})`);
  /* ★ 파동과 빔의 **근원**은 둘 중 하나다 — 갤럭시의 태양(질문) 또는 고른 별(`L.src`).
     태양은 근원이 별이어도 제자리다: 커맨드 센터는 안 움직인다. */
  const S=L.src?L.by[L.src]:null,O=S?{x:S.x,y:S.y}:C,sr=S?15:34;
  L.els.ripple.setAttribute("cx",O.x);L.els.ripple.setAttribute("cy",O.y);
  /* ★ **고리도 따라간다** (#75) — 항성이 갤럭시를 돌면 그 항성의 행성 고리도 같이 움직여야
     한다. 안 옮기면 고리만 제자리에 남아 「폴더 = 중심체」라는 그림이 그 순간 거짓말이 된다.
     ⚠ `cx`/`cy` 가 아니라 **`transform`** 이다 — 프레임마다 미는 것은 그 하나로 모은다. */
  for(const k in L.els.ring){
    const p=L.els.ringAt[k]?L.by[L.els.ringAt[k]]:null,px=p?p.x:C.x,py=p?p.y:C.y;
    const tilt=L.els.ringTilt?.[k]?(L.viewRoll||0):0;
    L.els.ring[k].setAttribute("transform",`translate(${px.toFixed(1)} ${py.toFixed(1)}) rotate(${tilt*180/Math.PI})`);
  }
  L.nodes.forEach(n=>{
    const scale=n.kind==="planet"?.92*(n.displayScale||1):1;
    L.els.node[n.id].setAttribute("transform",`translate(${n.x} ${n.y}) scale(${scale})`);
    const surface=L.els.spin?.[n.id];
    if(surface){const phase=(n.clk||0)*.13+(n.orbitIndex||0);surface.setAttribute("transform",`rotate(-18) scale(${Math.cos(phase).toFixed(3)} 1)`)}
    const b=L.els.beam[n.id];
    if(!b)return;
    const dx=n.x-O.x,dy=n.y-O.y,d=Math.hypot(dx,dy)||1,ux=dx/d,uy=dy/d;
    b.setAttribute("x1",(O.x+ux*sr).toFixed(1));
    b.setAttribute("y1",(O.y+uy*sr).toFixed(1));
    b.setAttribute("x2",(n.x-ux*14).toFixed(1));b.setAttribute("y2",(n.y-uy*14).toFixed(1));
  });
  if(L.els.bodies){
    const sorted=L.nodes.slice().sort((a,b)=>(a.depth||0)-(b.depth||0));
    const order=sorted.map(n=>n.id).join("|");
    if(order!==L.els.depthOrder){sorted.forEach(n=>L.els.bodies.appendChild(L.els.node[n.id]));L.els.depthOrder=order}
  }
}
function canvasFit(animate=false){
  const L=CANV,board=document.getElementById("cvb");
  /* ⚠ `els` 까지 본다 — 안 지어진 판(`canvasMount` 의 선언된 갈림)에는 맞출 것이 없다 */
  if(!L||!L.els||!board)return;
  const r=board.getBoundingClientRect(),B=canvasBox(),pad=46;
  if(!(r.width>0&&r.height>0))return;
  if(L.follow&&L.by[L.follow.id]){
    L.follow=Object.assign({},L.follow,{w:r.width,h:r.height});
    const scale=L.follow.id===L.focusID?canvasScopeScale(L,L.follow.id,r.width,r.height):(L.follow.scale||L.vt.k);
    if(L.glide){L.glide.w=r.width;L.glide.h=r.height;L.glide.targetScale=scale;return;}
    L.vt=glideTarget(L.by[L.follow.id],r.width,r.height,scale);
    canvasApplyVT();return;
  }
  const k=Math.max(.03,Math.min((r.width-pad*2)/B.w,(r.height-pad*2)/B.h,1.6));
  const to={k,x:r.width/2-(B.x+B.w/2)*k,y:r.height/2-(B.y+B.h/2)*k};
  if(animate&&!cvReduced()&&!document.hidden){
    L.glide={from:Object.assign({},L.vt),to,t0:performance.now(),duration:GLIDE_MS};canvasWake();return;
  }
  if(L.glide?.to){L.glide.to=to;return;}
  L.vt=to;
  canvasApplyVT();
}
/* SVG 알맹이를 **한 번 짓고**, 그 뒤로는 속성만 바꾼다 — 그래야 CSS 전환이 산다
   (매번 다시 지으면 전환이 매번 처음부터 시작해 아무것도 안 움직인 것처럼 보인다). */
function canvasMount(){
  const L=canvasUniverse(),board=document.getElementById("cvb");
  const previousVT=L.els||L.restoreVT?Object.assign({},L.vt):null;
  /* ⚠ **판이 진짜 SVG 일 때만 짓는다.** 아래가 전부 `createElementNS` 를 쓰는데, 네임스페이스를
     못 물어보는 판(= `tests/screen-load.mjs` 의 최소 DOM)에서는 그 첫 줄에서 죽는다.
     ★ 이 한 줄이 **선언된 갈림**이다: 지도는 안 뜨고 나머지 홈은 그대로 돈다. */
  if(!board||!board.namespaceURI)return null;
  /* ⚠ 네임스페이스를 **판에서 물어본다.** 글자로 적으면 그 리터럴이 판정선 검사의
     낱말표(`JS_NET`)와 겹친다 — 그 지뢰를 안 심는다. */
  const NS=board.namespaceURI;
  const el=(t,a)=>{const e=document.createElementNS(NS,t);for(const k in (a||{}))e.setAttribute(k,a[k]);return e};
  /* 다시 지으면 leave 이벤트가 안 온다 — 호버 슬로우가 붙지 않게 여기서 푼다(matt Spec 리뷰 #75 C2) */
  if(CANV){CANV.hover=null}canvasTipOff();
  board.innerHTML="";
  const sky=el("svg",{width:"100%",height:"100%",viewBox:"0 0 1200 800",preserveAspectRatio:"xMidYMid slice",class:"ambient"});
  const defs=el("defs"),glow=el("radialGradient",{id:"skyglow"});
  glow.appendChild(el("stop",{offset:"0%","stop-color":"white","stop-opacity":".65"}));
  glow.appendChild(el("stop",{offset:"100%","stop-color":"white","stop-opacity":"0"}));
  defs.appendChild(glow);
  const gradient=(id,stops,attrs={})=>{
    const g=el("radialGradient",Object.assign({id},attrs));
    stops.forEach(([offset,color,opacity])=>g.appendChild(el("stop",{offset,"stop-color":color,"stop-opacity":opacity})));
    defs.appendChild(g);
  };
  gradient("stellar-corona",[["0%","#fff8ee",.9],["16%","#ffd3a3",.6],["42%","#ffb979",.18],["100%","#ffb979",0]]);
  gradient("stellar-core",[["0%","#fffdf8",1],["55%","#ffe4c4",1],["100%","#eaa36a",1]]);
  gradient("planet-surface",[["0%","#f4faff",1],["38%","#c5e0ff",1],["72%","#82a9d0",1],["100%","#36516d",1]],{cx:"28%",cy:"24%",r:"78%"});
  gradient("moon-surface",[["0%","#ffffff",1],["35%","#e5e9ee",1],["80%","#9ca8b9",1],["100%","#566171",1]],{cx:"28%",cy:"22%",r:"82%"});
  gradient("galaxy-glow",[["0%","#f8f4e9",.9],["10%","#d8e2f1",.45],["35%","#8ba4c7",.12],["100%","#759ac9",0]]);
  sky.appendChild(defs);
  let noise=7319;
  const rnd=()=>{noise=(noise*16807)%2147483647;return (noise-1)/2147483646};
  for(let j=0;j<340;j++){
    const x=rnd()*1200,y=rnd()*800,r=.25+Math.pow(rnd(),5)*.85,a=.15+rnd()*.45;
    sky.appendChild(el("circle",{cx:x,cy:y,r:r,opacity:a}));
    if(r>.8)sky.appendChild(el("circle",{cx:x,cy:y,r:r*5,opacity:.35,class:"glow"}));
  }
  board.appendChild(sky);
  const root=el("g"),gr=el("g"),gb=el("g"),gw=el("g"),gn=el("g");
  board.appendChild(root);root.appendChild(gr);root.appendChild(gb);root.appendChild(gw);root.appendChild(gn);
  const ripple=el("circle",{class:"ripple",r:"0",opacity:"0",fill:"none",
    stroke:"var(--t2)","stroke-width":"1.6"});
  /* ★ 태양 = 커맨드 센터 (#70 확정 ④) — **언제나 있고, 누르는 것이 질문의 문**이다.
     ⚠ 신호등 색을 안 쓴다: 준비도가 아니라 「내가 던지는 자리」다.
     ⚠ 글리프는 **임시**다 — 로고가 정해지면 그 자리다. */
  const orb=el("g",{id:"orbg","pointer-events":"none","aria-hidden":"true"});
  /* 로고 확정 전의 중앙 별무리. 파일/검색 결과 개수를 뜻하지 않는 장식이다. */
  orb.style.display=WORKSPACE_SCOPE?"none":"";
  orb.appendChild(el("ellipse",{rx:"200",ry:"110",fill:"url(#galaxy-glow)",opacity:".3"}));
  for(let j=0;j<140;j++){
    const t=rnd()*Math.PI*5,r=Math.pow(rnd(),1.7)*190,a=t+Math.floor(rnd()*3)*Math.PI*2/3;
    orb.appendChild(el("circle",{cx:Math.cos(a+r*.018)*r,cy:Math.sin(a+r*.018)*r*.52,
      r:.6+rnd()*1.6,fill:j%5===0?"#d7e7fb":"#eef2f7",opacity:.25+rnd()*.6}));
  }
  gw.appendChild(ripple);gw.appendChild(orb);
  L.els={root:root,orb:orb,ripple:ripple,bodies:gn,sky:sky,node:{},beam:{},ring:{},ringAt:{},ringTilt:{},tring:{},spin:{}};
  /* 궤도 고리 — **아주 옅은 원 하나**. 자리가 구조에서 나온다는 것을 이 선이 말한다
     (design.md §1: *"폴더 = 중심체, 그 안의 것은 그것을 돈다"*). 뜻을 안 든다 — 색이 없다. */
  const rings={};
  L.nodes.forEach(n=>{
    if(n.fixed||!n.ring)return;
    const key=(n.parent||"__galaxy")+"@"+Math.round(n.ring);
    if(rings[key])return;
    /* ⚠ 원점에 짓고 **`transform` 으로 민다** — 중심체가 공전하면 고리도 따라가야 하고(#75),
       프레임마다 미는 속성을 하나로 모으면 그 자리가 `canvasPlace` 한 곳이 된다. */
    rings[key]=el("path",{class:"orbit",d:workspaceOrbitPath(n),fill:"none"});
    L.els.ringAt[key]=n.parent||null;
    L.els.ringTilt[key]=!!n.perspectiveBase;
    gr.appendChild(rings[key]);
  });
  L.els.ring=rings;
  L.nodes.forEach(n=>{
    if(n.kind==="planet"||n.kind==="moon"){
      const b=el("line",{class:"beam",opacity:"0","stroke-width":"1",stroke:"var(--t4)"});
      gb.appendChild(b);L.els.beam[n.id]=b;
    }
    const g=el("g",{class:"cvn"});
    g.appendChild(el("circle",{class:"hit",r:String(n.r+10)}));
    /* ⚠ 선택 헤일로와 순위 테는 **반지름이 갈려 있다** — 한 몸에 둘이 겹칠 수 있어서,
       같은 자리에 그리면 둘 중 하나가 안 읽힌다 (그 CSS 머리글) */
    g.appendChild(el("circle",{class:"selhalo",r:String(n.r+10)}));
    const tr=el("circle",{class:"ring",r:String(n.r+5)});
    g.appendChild(tr);L.els.tring[n.id]=tr;   /* 상위 3 테 — 켜져 있는 동안 돈다 (#75 3) */
    if(n.kind==="sun"){
      g.appendChild(el("circle",{class:"corona",r:String(n.r*2.2),fill:"url(#stellar-corona)","pointer-events":"none"}));
      g.appendChild(el("circle",{class:"surface",r:String(n.r),fill:"url(#stellar-core)","pointer-events":"none"}));
    }else if(n.kind==="planet"||n.kind==="moon"){
      g.appendChild(el("circle",{class:"surface",r:String(n.r),fill:`url(#${n.kind==="moon"?"moon":"planet"}-surface)`,"pointer-events":"none"}));
      const spin=el("g",{"pointer-events":"none",opacity:".3"});
      spin.appendChild(el("ellipse",{rx:String(n.r*.53),ry:String(n.r*.87),fill:"none",stroke:"#f3f9ff","stroke-width":"1.3"}));
      spin.appendChild(el("ellipse",{rx:String(n.r*.23),ry:String(n.r*.87),fill:"none",stroke:"#729dc3","stroke-width":"1"}));
      g.appendChild(spin);L.els.spin[n.id]=spin;
    }
    g.appendChild(el("circle",{class:"d",r:String(n.r),fill:"var(--t3)"}));
    g.appendChild(el("circle",{class:"shine",r:String(n.r*.13),cx:"0",cy:"0"}));
    g.dataset.f=n.id;g.dataset.kind=n.kind;
    g.setAttribute("role","button");g.setAttribute("tabindex","0");
    g.setAttribute("aria-label",n.name||(DOC.fragments.find(p=>p.id===n.id)||{}).title||"문서");
    g.onclick=ev=>{if(ev.detail===0){if(n.kind==="sun")canvasScopeSun(n.id);else canvasNavigateFile(n.id)}};
    g.onkeydown=ev=>{if(ev.key==="Enter"||ev.key===" "){
      ev.preventDefault();if(n.kind==="sun"||n.kind==="center")canvasScopeSun(n.id);
      else if(ev.key==="Enter")workspaceOpen(n.id);else canvasSelect(n.id);
    }};
    /* ★ 스치면 **그 계가 느려진다** (#75 2 · design.md §3) — 툴팁과 같은 손잡이에 얹는다.
       ⚠ 끌고 있을 때도 `hover` 는 세운다: 느려진 계를 잡아 끌다 놓으면 그대로 느린 채여야
         「스치면 느리다」가 참이다. 툴팁만 끌기 중에 안 뜬다. */
    g.onpointerenter=()=>{const C=CANV;if(C){C.hover=n.id;canvasWake()}if(!(C&&C.drag))canvasTip(n)};
    g.onpointerleave=()=>{const C=CANV;if(C)C.hover=null;canvasTipOff()};
    gn.appendChild(g);L.els.node[n.id]=g;
  });
  canvasPlace();if(previousVT){L.vt=previousVT;canvasApplyVT()}else canvasFit();L.restoreVT=false;
  paintCanvasNavigation();
  L.nodes.forEach(n=>L.els.node[n.id].setAttribute("class",canvasNodeClass(n.id)));
  return L;
}
/* 천체의 이름표 대신 탐색기의 실제 경로를 일시 강조한다. */
function canvasTip(n){canvasHoverFile(n)}
function canvasTipOff(){canvasHoverFile(null)}
/* Hover is transient: never select, expand, scroll, or rebuild the tree. */
function canvasHoverFile(n){
  const box=document.getElementById("leftlist");if(!box)return;
  const rows=Array.from(box.querySelectorAll(".hmit"));
  rows.forEach(row=>row.classList.remove("cosmic-hover"));
  if(!n)return;
  const path=PATHS[n.id]||n.path||"";
  const exact=rows.find(row=>row.dataset.fold!==undefined?row.dataset.fold===path:(row.dataset.id||DOC.fragments[+row.dataset.i]?.id)===n.id);
  const ancestor=!exact&&rows.filter(row=>row.dataset.fold&&path.startsWith(row.dataset.fold+"/")).sort((a,b)=>b.dataset.fold.length-a.dataset.fold.length)[0];
  const match=exact||ancestor;if(match)match.classList.add("cosmic-hover");
}

/* ── 파동 ────────────────────────────────────────────────────────────────
   고리 하나가 중앙에서 퍼지고 **반지름이 점을 지나칠 때** 그 점이 켜진다.
   ⚠ 중간에 취소되면 **남은 것을 즉시 전부 적용**한다 — 안 그러면 반쯤 켜진 채로 굳는다.
   ⚠ rAF 는 **창이 숨으면 안 돈다.** 그러면 점이 영영 안 켜지므로 타이머가 뒤를 받는다. */
function canvasWaveCancel(){
  const L=CANV;if(!L||!L.wave)return;
  const w=L.wave;L.wave=null;
  clearTimeout(w.net);
  w.pending.forEach(p=>p.apply());
  if(L.els){L.els.ripple.setAttribute("opacity","0");L.els.ripple.setAttribute("r","0")}
}
/* ⚠ **제 프레임을 안 잡는다** (#75). 전 판은 파동이 자기 rAF 를 돌렸는데, 공전이 붙으면서
   루프가 둘이 된다 — 그러면 「가만히 있으면 CPU 0」을 두 자리에서 지켜야 한다.
   미는 것은 `canvasTick` 하나이고 여기는 **상태만 세운다**(`tests/orbit.test.mjs` 가 잠근다). */
function canvasWave(plan){
  const L=CANV;if(!L||!L.els)return;
  canvasWaveCancel();
  const maxD=Math.max(1,...plan.map(p=>p.dist));
  L.wave={net:0,pending:plan.slice(),t0:performance.now(),
          R:maxD*1.15+56,dur:520+Math.min(240,maxD*.42)};
  const st=L.wave;
  st.net=setTimeout(()=>{if(L.wave===st)canvasWaveCancel()},st.dur+700);
  canvasWake();
}
/* 파동 한 프레임 — 반지름이 몸을 지나칠 때 그 몸이 켜진다 */
function canvasWaveStep(t){
  const L=CANV,st=L&&L.wave;if(!st||!L.els)return;
  /* ⚠ `u` 를 **아래로도** 조인다 — rAF 의 시각이 `t0` 보다 앞서면 `r` 이 음수가 되어
     `<circle>` 이 콘솔에 빨간 줄을 남긴다 (시제품에서 실측: "-0.7"). */
  const u=Math.max(0,Math.min(1,(t-st.t0)/st.dur)),r=cvEase(u)*st.R;
  L.els.ripple.setAttribute("r",r.toFixed(1));
  L.els.ripple.setAttribute("opacity",(.34*(1-u)*(1-u)).toFixed(3));
  st.pending=st.pending.filter(p=>{if(r>=p.dist){p.apply();return false}return true});
  if(u<1)return;
  st.pending.forEach(p=>p.apply());st.pending=[];clearTimeout(st.net);L.wave=null;
  L.els.ripple.setAttribute("opacity","0");L.els.ripple.setAttribute("r","0");
}

/* ══ 공전 루프 (#75) — **한 루프가 전부를 민다** ══════════════════════════════
   박선호 2026-09-02: *"공전 애니매이션은 넣어줄래? 뭔가 살아있다는 느낌"*.
   ★ 한 프레임에 도는 것 넷: **공전**(각도) · **파동** · **카메라 글라이드** · **상위 3 테**.
     넷이 각자 rAF 를 잡으면 「자고 있나」를 네 자리에서 지켜야 한다 — 그래서 하나다
     (`tests/orbit.test.mjs` 가 rAF 부르는 자리를 잠근다).
   ★ **미는 것은 `transform` 뿐이다.** class 와 색 이름은 여기서 안 건드린다 — 미는 것은 속성(transform·불투명도·반지름·선 좌표·dashoffset)뿐 — 그것은
     칠하는 자리(`canvasPaint`)의 것이고, 프레임마다 만지면 CSS 전환이 매 프레임 처음부터
     다시 시작한다.
   ⚠ **자는 조건 넷**(`canvasSleepWhy`): 창 숨김 · reduced-motion · 판이 안 보임 ·
     움직일 것이 없음. 프레임 안에서 매번 다시 묻는다 — 깨우는 자리를 다 세는 것보다,
     한 프레임 더 돌고 자는 쪽이 안 새는 길이다.
   ⚠ 자면서 **파동을 흘려보낸다** — 반쯤 켜진 채로 굳으면 그것이 곧 거짓 측정이다.
   ══════════════════════════════════════════════════════════════════════════ */
/* 우주가 지금 화면에 있나 — 쌓기 홈의 가운데 칸 하나뿐이다 */
const canvasShown=()=>{
  if(mode!=="stack"||stackView!=="edit")return false;
  if(PANE.r===0)return true;
  try{return matchMedia("(min-width:1000px)").matches}catch(e){return false}
};
function canvasAsleep(L){
  let hid=false;try{hid=!!document.hidden}catch(e){}
  return canvasSleepWhy({hidden:hid,reduced:cvReduced(),shown:canvasShown(),
    moving:!!(L&&L.els&&(L.nodes.some(n=>!n.fixed)||L.glide||L.wave))});
}
/* 깨운다 — **이미 돌고 있으면 아무 일도 안 한다.** 부르는 자리가 여럿이라 그 멱등이 값이다 */
function canvasWake(){
  const L=CANV;if(!L||!L.anim)return;
  if(canvasAsleep(L)){canvasStop();return}
  if(L.anim.raf)return;
  L.anim.last=performance.now();
  L.anim.raf=requestAnimationFrame(canvasTick);
}
function canvasStop(){
  const L=CANV;if(!L||!L.anim||!L.anim.raf)return;
  cancelAnimationFrame(L.anim.raf);L.anim.raf=0;
}
function canvasTick(t){
  const L=CANV;
  if(!L||!L.anim)return;
  L.anim.raf=0;
  if(canvasAsleep(L)){if(L.wave)canvasWaveCancel();return}
  /* ⚠ `dt` 를 50ms 로 막는다 — 탭이 뒤에 있다 돌아오면 한 프레임에 몇 분이 흘러 별이 순간이동한다 */
  const dt=Math.max(0,Math.min(.05,(t-L.anim.last)/1000));
  L.anim.last=t;
  L.viewClock=(L.viewClock||0)+dt;L.viewRoll=Math.sin(L.viewClock*.15)*.25;
  if(L.els.sky)L.els.sky.setAttribute("x",(Math.sin(L.viewClock*.09)*8).toFixed(2));
  const hv=L.hover?(L.by[L.hover]||{}).sun:null;
  L.nodes.forEach(n=>{
    if(n.fixed)return;
    /* 잡고 있는 별은 손이 각도를 든다 — 시계도 안 흐른다(놓은 자리에서 이어 돈다) */
    if(L.drag&&L.drag.node===n)return;
    const travel=L.travelUntil>t&&n.sun===L.travelSystem?1+35*Math.pow((L.travelUntil-t)/2600,2):1;
    n.clk+=dt*travel*orbitFactor(travel===1&&!!hv&&n.sun===hv,n.boost?t-n.boost:null);
    n.ang=orbitAngle(n.base+n.phase,n.clk,n.period||ORBIT_PERIOD[n.kind]||ORBIT_PERIOD.planet);
  });
  canvasReflow();canvasPlace();
  canvasWaveStep(t);
  canvasGlideStep(t);canvasFollowStep();
  canvasSpinRings(t);
  L.anim.raf=requestAnimationFrame(canvasTick);
}
/* 상위 3 테는 **켜져 있는 동안 돈다** (#75 3). 자전이 아니다 — 테의 점선만 흐른다.
   ⚠ 도는 몸을 매 프레임 다시 고르지 않는다: 계획(`L.last`)이 갈릴 때만 목록을 다시 짓는다. */
const RING_SPIN=22;
function canvasSpinRings(t){
  const L=CANV,P=L.last;
  if(!P){L.spinFor=null;L.spin=null;return}
  if(L.spinFor!==P){L.spinFor=P;L.spin=(P.items||[]).filter(x=>x.top>0).map(x=>x.id)}
  if(!L.spin||!L.spin.length)return;
  const off=(-(t/1000)*RING_SPIN).toFixed(1);
  L.spin.forEach(id=>{const r=L.els.tring[id];if(r)r.setAttribute("stroke-dashoffset",off)});
}
/* ★ 카메라를 그 몸으로 민다 (#75 4) — **트리와 우주가 서로를 가리키는 자리.**
   ⚠ reduced-motion 이면 **즉시 간다**: 결과 화면은 같고 도중만 없다(design.md §3). */
function canvasGlideTo(id,targetScale){
  const L=CANV,b=L&&L.by[id],board=document.getElementById("cvb");
  if(!L||!b||!board||!L.els)return;
  const r=board.getBoundingClientRect();
  if(!(r.width>0&&r.height>0))return;
  L.follow={id:id,w:r.width,h:r.height,scale:targetScale||L.vt.k};
  if(cvReduced()||document.hidden){
    L.glide=null;
    const to=glideTarget(b,r.width,r.height,targetScale||L.vt.k);
    L.vt.k=to.k;L.vt.x=to.x;L.vt.y=to.y;canvasApplyVT();return;
  }
  /* 판 크기는 **여기서 한 번** 잰다 — 매 프레임 `getBoundingClientRect` 는 방금 쓴 속성 뒤라
     강제 레이아웃이다(matt Standards 리뷰 #75). 글라이드 400ms 안에 창이 바뀌는 일은 무시한다. */
  L.glide={from:{k:L.vt.k,x:L.vt.x,y:L.vt.y},id:id,targetScale:targetScale||L.vt.k,t0:performance.now(),w:r.width,h:r.height};
  canvasWake();
}
/* ⚠ 목표를 **매 프레임 다시 낸다** — 몸이 도는 중이라 400ms 전의 자리로 가면 끝났을 때
   그 별은 이미 딴 데 있다. 끝 프레임에서 목표와 정확히 같아진다(`glideVT` 의 그 단언). */
function canvasGlideStep(t){
  const L=CANV,g=L&&L.glide;if(!g)return;
  const b=L.by[g.id];
  if(!g.to&&(!b||!(g.w>0&&g.h>0))){L.glide=null;return}
  const u=Math.min(1,(t-g.t0)/(g.duration||(L.travelUntil>t?1100:GLIDE_MS)));
  const vt=glideVT(g.from,g.to||glideTarget(b,g.w,g.h,g.targetScale),u);
  L.vt.k=vt.k;L.vt.x=vt.x;L.vt.y=vt.y;canvasApplyVT();
  if(u>=1)L.glide=null;
}
/* 확대 중심은 공전 중에도 화면 중앙을 유지한다. 수동 팬·줌은 추적을 푼다. */
function canvasFollowStep(){
  const L=CANV,f=L&&L.follow;if(!f||L.glide||L.drag)return;
  const b=L.by[f.id];if(!b){L.follow=null;return}
  const vt=glideTarget(b,f.w,f.h,L.vt.k);
  L.vt.x=vt.x;L.vt.y=vt.y;canvasApplyVT();
}
/* ★ 켜진 몸은 잠깐 빨라진다 (#75 3) — **반응이 색으로만 오면 「살아 있다」가 안 읽힌다.** */
function canvasBoost(ids){
  const L=CANV;if(!L)return;
  const t=performance.now();
  (ids||[]).forEach(id=>{const n=L.by[id];if(n)n.boost=t});
  canvasWake();
}
/* 그 몸이 속한 **계 전체.** 이웃이 전부 빨강이라 켜지는 것이 없어도 계는 반응한다 (#75 5) */
function canvasBoostSystem(id){
  const L=CANV,b=L&&L.by[id];if(!b)return;
  canvasBoost(L.nodes.filter(n=>n.sun===b.sun||n.id===id).map(n=>n.id));
}

/* ── 불 끄기 · 불 켜기 ──────────────────────────────────────────────────── */
function canvasLightsOff(){
  const L=CANV;if(!L)return;
  if(L.els)canvasWaveCancel();
  L.last=null;L.src=null;
  if(!L.els)return;
  canvasPlace();
  L.nodes.forEach(n=>{
    const g=L.els.node[n.id],d=g.querySelector(".d");
    g.setAttribute("class",canvasNodeClass(n.id));
    d.setAttribute("fill",isSelId(n.id)?"var(--t1)":"var(--t3)");d.setAttribute("opacity","1");
    const b=L.els.beam[n.id];if(b)b.setAttribute("opacity","0");
  });
  L.els.orb.classList.remove("asking");   /* 불이 꺼지면 「묻는 중」 표정도 내린다 (목업 lightsOff) */
  /* ⚠ **태양은 안 끈다** (#70 확정 ④) — 커맨드 센터라 불이 꺼져도 거기 있어야 한다. */
  const rb=document.getElementById("cvrank");if(rb)rb.classList.remove("show");
  /* 불이 꺼지면 왼쪽 트리의 점도 걷힌다 — 쉴 때 점이 없다(design.md §2) */
  paintHomeList();
}
/* ★ 한 판을 칠한다 — **두 단계다** (#74 B · ADR 0006).
   ① 갤럭시: `rank()` 가 전체를 한 번에 재고, **항성 색은 그 항성 최고 멤버의 등급**이다
      (길잡이 — 어느 항성이 뜨거운가). **자동 진입은 없다**(박선호 결정 2026-09-02).
   ② 항성 안: 사람이 항성을 누르면 `searchSun` 이 낸 줄로 그 항성의 별을 켠다.
      **범위 안은 빨강도 켜진다** — 빨강 = 이 주제인데 약하다 = 채울 자리(design.md §2).
      다른 항성의 별은 가라앉는다.
   ⚠ 질의 벡터가 없으면 ①을 **건너뛰고** 지금까지의 평면 글자 검색으로 돈다(선언된 갈림).
   ⚠ **`opt.wave` 일 때만** 파동이 퍼진다 — 저장·선택 뒤의 다시 칠하기는 조용해야 한다. */
function canvasPaint(q,qv,how,opt){
  const L=CANV;if(!L||!L.els)return null;
  const stars=canvasStars(L);
  const sunId=L.focusPath||null;
  L.scoped=sunId;
  let res=rank(q,qv,VEC),scope=null;
  if(sunId){res=res.filter(row=>(PATHS[row.p.id]||"").startsWith(sunId+"/"));scope={};res.forEach(row=>{scope[row.p.id]=true})}
  const sunBy={};
  if(how==="뜻")L.nodes.filter(n=>n.kind==="sun").forEach(n=>{
    const best=res.find(row=>(PATHS[row.p.id]||"").startsWith(n.path+"/"));
    if(best)sunBy[n.id]={id:n.id,s:best.s,c:best.c};
  });
  const sc=canvasScale(how),green=sc.green,amber=sc.amber;
  const C=canvasCenter();
  const P=canvasPlan(res,stars,C,CV_TOP,{scope:scope,sunId:sunId,suns:sunBy});
  L.last=P;L.src=null;             /* 질문의 근원은 갤럭시의 태양이다 */
  canvasWaveCancel();
  const wave=!!(opt&&opt.wave)&&!cvReduced();
  const plan=P.items.map(it=>({dist:it.dist,apply:()=>{
    const g=L.els.node[it.id],d=g.querySelector(".d");
    g.setAttribute("class",canvasNodeClass(it.id));
    const t=(green>amber&&it.s!==null)?(it.s-amber)/(green-amber):0;
    d.setAttribute("fill",it.lit
      ?(it.c==="g"?"var(--acc)":it.c==="a"?"var(--warn)":"var(--risk)")
      :(isSelId(it.id)?"var(--t1)":"var(--t3)"));
    d.setAttribute("opacity",litOpacity(it.lit,t,it.id));
    const st=beamStyle(it.c,it.s,green,amber),b=L.els.beam[it.id];
    if(!b)return;
    b.setAttribute("stroke",st.s);b.setAttribute("stroke-width",String(st.w));
    b.setAttribute("opacity",String(P.empty?(st.o*.6).toFixed(3):st.o));
  }}));
  /* 항성은 파동을 안 기다린다 — **1단의 답**이라 별보다 먼저 서 있어야 읽힌다 */
  const paintSuns=()=>L.nodes.filter(n=>n.kind==="sun").forEach(n=>{
    const g=L.els.node[n.id],d=g.querySelector(".d"),su=sunBy[n.id];
    g.setAttribute("class",canvasNodeClass(n.id));
    d.setAttribute("fill",su?(su.c==="g"?"var(--acc)":su.c==="a"?"var(--warn)":"var(--risk)"):"var(--t3)");
    d.setAttribute("opacity",su?"1":".45");
  });
  canvasPlace();
  if(wave){
    /* 파동이 지나가기 전엔 검색 전 모습으로 되돌려 둔다 — 그래야 「파동이 켰다」가 보인다 */
    stars.forEach(n=>{
      const g=L.els.node[n.id],d=g.querySelector(".d");
      g.setAttribute("class","cvn k"+n.kind+(isSelId(n.id)?" sel":""));
      d.setAttribute("fill",isSelId(n.id)?"var(--t1)":"var(--t3)");d.setAttribute("opacity","1");
      const b=L.els.beam[n.id];if(b)b.setAttribute("opacity","0");
    });
    paintSuns();
    canvasWave(plan);
  }else{paintSuns();plan.forEach(p=>p.apply())}
  /* ★ 켜진 몸은 잠깐 빨라진다 (#75 3) — 파동이 켠 그 몸들이다 */
  if(P.items.some(it=>it.lit))canvasBoost(L.nodes.map(n=>n.id));
  canvasRankBox(q,P,res,how,green,amber,sunId);
  /* ★ **왼쪽 트리의 점도 같이 켠다** (#74 C2, `실측 2026-09-02` 실화면). 쉴 때 점이 없고
     검색 중에만 붙는데, 그 점을 짓는 것은 `paintHomeList` 라 여기서 안 부르면 지도만 켜지고
     **트리는 영영 무채색**이다 — 한 화면이 두 말을 하는 자리. 색은 지도가 낸 것을 그대로 읽는다. */
  paintHomeList();
  return P;
}
/* 순위 상자 — 라이브 카드와 **같은 셋**, 같은 규율. 원값(0.884 류)은 QA 게이트 뒤다 (#61 E) */
function canvasRankBox(q,P,res,how,green,amber,sunId){
  const box=document.getElementById("cvrank");if(!box)return;
  const node=CANV&&CANV.focusID&&CANV.by[CANV.focusID];
  const scope=node?(CANV.focusPath||node.name||node.path):"저장소 전체";
  const head=`<h4>추천 미리보기 <span class="preview-scope">${esc(scope)}</span></h4><div class="cq">${esc(q)}</div>`;
  if(how!=="뜻"){
    box.innerHTML=head+`<div class="cvnone">검색 준비 중</div>`;
  }else{
    const rows=res.filter(x=>!CANV?.focusPath||(PATHS[x.p.id]||"").startsWith(CANV.focusPath+"/")).slice(0,CV_TOP);
    box.innerHTML=head+(rows.length?canvasResultRows(rows,true):`<div class="cvnone">문서 없음</div>`);
    bindCanvasResults(box,rows);
  }
  box.classList.add("show");
}
function canvasResultRows(rows,preview,related){
  return rows.map((x,i)=>{
    const excerpt=((x.passage&&x.passage.sourceText)||x.p.body||"").trim();
    const measured=x.c!=="n"&&Number.isFinite(x.s);
    const score=preview&&measured?`<span class="s" title="검색 기준 대비 관련도. 100%가 초록 기준이며 정답 확률이 아닙니다.">${readyPct(x.s,related?SIM_G_DIRECT:1)}%</span>`:"";
    return `<button class="cvrow${i===0?" lead":""}${preview?" preview-row":""}" data-result="${i}"><span class="dot ${x.c==="n"?"hmn":x.c}"></span><span class="preview-copy"><span class="t">${esc(x.p.title)}</span><span class="preview-path">${esc(PATHS[x.p.id]||"")}</span>${preview?`<span class="preview-excerpt">${esc(excerpt)}</span>`:""}</span>${score}</button>`;
  }).join("");
}

function bindCanvasResults(box,rows){
  box.querySelectorAll("[data-result]").forEach(el=>el.onclick=()=>openWorkspaceDocument(rows[+el.dataset.result].p.id));
}

/* ══ 별에서 나가는 파동 (목업 `pickFragment`·`planNeighbors`·`refreshBeams` 이식) ═══════════
   박선호 2026-09-02: *"별 선택해도 파장이랑 신호등 관계 보여주는거 그대로 앱에 적용"*.
   ★ **자를 안 만들었다.** 이웃과 순서는 `hmNear`(조각↔조각 코사인, 없으면 글자), 색은
     **그 이어짐의 등급**(`eris(cos/SIM_G_DIRECT)`) — 라이브 검색이 쓰는 그 눈금 그대로다.
   ★ **문서 선택은 항성을 건너뛰어 전체 저장소를 찾는다** (workspace-navigation-v2).
     폴더를 질문하는 경로의 범위는 `canvasPaint` 가 따로 지키고, 문서 기준 관련 탐색은
     구조적 소속과 의미적 이어짐을 분리한다.
   ⚠ **빨강을 선에 안 칠한다** (`beamStyle` 과 같은 규율). 빨강·못 잼인 이웃은 회색 선이다.
   ⚠ 질문 파동과 **같은 고리·같은 상자·같은 파동 함수**다. 다른 것은 근원(`L.src`)뿐. */
function nbBeamStyle(c,s){
  const t=Math.max(0,Math.min(s||0,1)),r=x=>Math.round(x*100)/100;
  if(c==="g"||c==="a")return {s:c==="g"?"var(--acc)":"var(--warn)",w:r(.8+2.2*t),o:r(.26+.44*t)};
  return {s:"var(--t4)",w:r(.8+1.2*t),o:r(.18+.22*t)};
}
function canvasNeighborPlan(id){
  const L=CANV,p=DOC.fragments.find(x=>x.id===id),me=L&&L.by[id];
  if(!L||!p||!me)return null;
  /* 선택한 문서의 관련 탐색은 전체 저장소다. 항성·폴더 질문의 범위는 `canvasPaint` 경로에서
     별도로 좁히며, 여기서는 행성 기준의 의미적 이어짐을 구조 경계로 자르지 않는다. */
  const sunId=sunOfFragment(L.tree,id);
  const nb=hmNear(p,null),by={};
  nb.forEach((x,k)=>{by[x.p.id]={c:x.c,s:x.s,k:k}});
  /* ★ **이어진 것 = 켜지는 것.** 빨강은 무반응이라 줄에서도 빠진다 (#75 5 · design.md §2) —
     안 빼면 순위 상자가 「이어진 것 셋」이라며 아무 데도 안 빛나는 셋을 적는다. */
  const lit=nb.filter(x=>x.c!=="r"),topBy={};
  lit.slice(0,CV_TOP).forEach((x,k)=>{topBy[x.p.id]=k+1});
  const items=canvasStars(L).filter(n=>n.id!==id).map(n=>{
    const x=by[n.id]||null;
    /* ★ **빨강은 안 켜진다** (#75 5 · design.md §2: 빨강 = 무반응). `canvasPlan` 이 질문
       쪽에서 지키는 그 규칙을 이웃 쪽도 지킨다 — 갈리면 같은 색이 한 화면에서 두 뜻이 된다.
       못 잰 이웃(`"n"`)은 그대로 켜진다: 그건 「약하다」가 아니라 「자가 없다」다. */
    return {id:n.id,kind:n.kind,c:x?x.c:"n",s:x?x.s:null,rank:x?x.k:null,lit:!!x&&x.c!=="r",
            scope:true,
            top:topBy[n.id]||0,dist:Math.hypot(n.x-me.x,n.y-me.y)};
  }).sort((a,b)=>a.dist-b.dist);
  const map={};items.forEach(it=>{map[it.id]=it});
  map[id]={id:id,c:null,s:null,lit:false,top:0,dist:0,self:true};
  return {empty:!lit.length,items:items,by:map,self:id,nb:lit,sunId:sunId};
}
function canvasPaintFrom(id,opt){
  const L=CANV;if(!L||!L.els)return null;
  const P=canvasNeighborPlan(id);if(!P)return null;
  L.last=P;L.src=id;
  canvasWaveCancel();
  const wave=!!(opt&&opt.wave)&&!cvReduced();
  const plan=P.items.map(it=>({dist:it.dist,apply:()=>{
    const g=L.els.node[it.id],d=g.querySelector(".d");
    g.setAttribute("class",canvasNodeClass(it.id));
    d.setAttribute("fill",it.lit?(it.c==="g"?"var(--acc)":it.c==="a"?"var(--warn)":it.c==="r"?"var(--risk)":"var(--t2)"):"var(--t3)");
    d.setAttribute("opacity",litOpacity(it.lit,it.s||0,it.id));
    const b=L.els.beam[it.id];
    if(!b)return;
    if(!it.lit){b.setAttribute("opacity","0");return}
    const st=nbBeamStyle(it.c,it.s);
    b.setAttribute("stroke",st.s);b.setAttribute("stroke-width",String(st.w));b.setAttribute("opacity",String(st.o));
  }}));
  canvasPlace();
  /* 근원이 된 별 — 흰빛으로 서고(#70 확정 ③), 제 빔은 안 쏜다 */
  const sg=L.els.node[id],sd=sg.querySelector(".d");
  sg.setAttribute("class",canvasNodeClass(id));
  sd.setAttribute("fill","var(--t1)");sd.setAttribute("opacity","1");
  const sb=L.els.beam[id];if(sb)sb.setAttribute("opacity","0");
  if(wave){
    P.items.forEach(it=>{
      const g=L.els.node[it.id],d=g.querySelector(".d");
      g.setAttribute("class","cvn k"+it.kind);d.setAttribute("fill","var(--t3)");d.setAttribute("opacity","1");
      const b=L.els.beam[it.id];if(b)b.setAttribute("opacity","0");
    });
    canvasWave(plan);
  }else plan.forEach(p=>p.apply());
  /* ★ **그 계가 반응한다** (#75 3·5) — 이웃이 전부 빨강이라 켜지는 것이 없어도 여기는 돈다.
     그러면 「눌렀는데 아무 일도 없다」가 아니라 「이 계엔 이어진 것이 없다」로 읽힌다. */
  canvasBoostSystem(id);
  canvasNeighborBox(DOC.fragments.find(x=>x.id===id),P);
  paintHomeList();   /* 이웃 불도 왼쪽 트리에 같이 붙는다 (#74 C2) */
  return P;
}
/* 순위 상자 — 질문 때와 같은 상자, 다른 머리. 수는 이어진 정도(100 = 같은 뜻), 색은 그 이어짐의 등급 */
function canvasNeighborBox(p,P){
  const box=document.getElementById("cvrank");if(!box||!p)return;
  const rows=P.nb.slice(0,CV_TOP);
  box.innerHTML=`<div class="cq">${esc(p.title)} <span class="preview-scope">전체 저장소</span></div>`
    +(rows.length?canvasResultRows(rows,true,true):`<div class="cvnone">관련 문서 없음</div>`);
  bindCanvasResults(box,rows);
  box.classList.add("show");
}

/* 질문을 놓는다 — 글자·벡터·표식·입력 칸까지. 파동은 안 건드린다(부르는 쪽이 정한다) */
function canvasDropQuestion(){
  CANVQ="";CQV=null;
  const q=document.getElementById("cvq");if(q)q.value="";
  const tag=document.getElementById("cvhow");if(tag){tag.className="cvhow";tag.textContent=""}
}
/* 고른 별이 있으면 그 별에서 **조용히** 다시 켠다, 없으면 끈다 */
function canvasPaintEntry(id){
  const file=workspaceFile(id);if(!file?.p.entry)return false;
  canvasLightsOff();
  const g=CANV?.els?.node[id];if(g)g.setAttribute("class",canvasNodeClass(id));
  const box=document.getElementById("cvrank");
  if(box){
    const manageable=file.p.entry.manageable!==false;
    box.innerHTML=`<h4>${esc(file.path)}</h4><div class="cvnone">${manageable?"내용 검색을 지원하지 않는 파일입니다.":"이 항목은 탐색과 파일 정리 대상에서 제외됩니다."}</div>`
      +(manageable?`<button id="externalopen" class="gbtn">외부 앱으로 열기</button>`:"");
    box.classList.add("show");const button=document.getElementById("externalopen");if(button&&manageable)button.onclick=()=>workspaceOpen(id);
  }
  return true;
}
function canvasRelightSel(){
  if(canvasPaintEntry(workspaceSelectedID()))return;
  const p=sel!==null?DOC.fragments[sel]:null;
  if(!(p&&canvasPaintFrom(p.id,{wave:false})))canvasLightsOff();
}
/* 다시 그린 뒤 불을 되살리는 자리 하나 — 질문이 먼저, 그 다음 고른 별 */
function canvasRelight(){
  if(CANV&&CANV.relatedID)return canvasPaintEntry(CANV.relatedID)||canvasPaintFrom(CANV.relatedID,{wave:false});
  if(CANVQ.trim())return canvasAsk(CANVQ,{wave:false});
  canvasRelightSel();
}
/* 점을 눌렀다 — **오른쪽 판만 갈아끼운다.** 화면을 통째로 다시 그리면 방금 켠 불과
   사람이 옮긴 배치가 날아간다(`paintHomeList` 가 왼쪽 칸만 고쳐 쓰는 것과 같은 규율). */
function canvasSelect(id,opt){
  if(!leaveEditorAllowed(()=>canvasSelect(id,opt)))return;
  const file=workspaceFile(id);if(!file)return;
  const i=DOC.fragments.findIndex(p=>p.id===id);
  canvasRemember();
  const parent=file.path.split("/").slice(0,-1).join("/");
  if(parent!==WORKSPACE_SCOPE)workspaceEnterFolder(parent);
  const L=canvasUniverse();
  const keepCamera=!!(opt&&opt.preserveCamera),savedVT=keepCamera?Object.assign({},L.vt):null;
  sel=i<0?null:i;WORKSPACE_SELECTED_ID=id;revealWorkspaceFile(id);
  /* 문서는 전체 관련 탐색의 기준이다. 이전 질문은 뒤로 돌아갈 맥락으로 보존한다. */
  L.relatedID=id;L.follow=null;L.glide=null;
  const fixed=document.getElementById("workspacequery");if(fixed)fixed.value="";
  canvasAskClose();
  if(savedVT){L.vt=savedVT;canvasApplyVT()}else canvasFit();
  if(i<0)canvasPaintEntry(id);else canvasPaintFrom(id,{wave:true});
  paintCanvasNavigation();
  canvasPaintPanel();
  /* 왼쪽 목록의 `.sel` 도 같이 옮긴다 — 안 옮기면 **한 화면이 두 조각을 가리킨다** */
  paintHomeList();
  /* ★ **그 줄까지 굴려 보여준다** (#75 4). 목록이 길면 `.sel` 이 접힌 화면 밖에 붙고,
     그러면 「고른 것이 왼쪽 어디인가」를 사람이 찾아야 한다 — 우주→트리 방향의 포커스다. */
  treeScrollSel();
}
function canvasNavigateFile(id){
  if(!leaveEditorAllowed(()=>canvasNavigateFile(id)))return false;
  if(stackView==="settings"){stackView="edit";stackRender()}
  const currentID=workspaceSelectedID();
  const tracking=CANV&&(CANV.glide&&CANV.glide.id===id||CANV.follow&&CANV.follow.id===id);
  if(currentID===id&&tracking){paneApply("r",0);return true}
  /* 파일 행은 `canvasSelect` 의 전체 맞춤에서 시작하지 않는다 — 진행 중인 카메라를 이어야 한다. */
  const before=CANV,stableScale=before&&(before.glide&&before.glide.targetScale||before.follow&&before.follow.scale);
  const targetScale=stableScale||Math.min(1.55,Math.max(.75,(before&&before.vt?before.vt.k:1)*1.55));
  canvasSelect(id,{preserveCamera:true});
  paneApply("r",0);
  const L=CANV,n=L&&L.by[id];if(!n)return false;
  L.travelUntil=performance.now()+2600;L.travelSystem=n.sun;
  canvasBoostSystem(id);
  canvasGlideTo(id,targetScale);
  canvasWake();return true;
}
function canvasGoHome(){canvasScopeFolder("")}
function revealWorkspaceFile(id){
  LZIP=treeReveal(LZIP,workspaceFile(id)?.path||PATHS[id]);
  /* 파일 검색은 사용자의 작업 맥락이다. 문서를 열거나 이동해도 지우지 않는다. */
}
/* 왼쪽 트리에서 지금 표시된 줄로 굴린다. **`block:"nearest"`** — 이미 보이면 아무 일도 안 한다
   (트리에서 누른 경우 화면이 덜컥 움직이면 안 된다). */
function treeScrollSel(q){
  const box=document.getElementById("leftlist");if(!box||!box.querySelector)return;
  const el=box.querySelector(q||".hmit.sel");
  if(el&&el.scrollIntoView)try{(el.querySelector(".hmtx")||el).scrollIntoView({block:"nearest",inline:"nearest"})}catch(e){}
}
/* ★ 항성 하나로 **범위 지정 + 카메라 글라이드** (#75 4). 문이 둘이다 — 우주의 항성과 트리의
   폴더 줄. 둘이 같은 함수를 부르므로 어느 문으로 들어와도 결과가 하나다.
   ⚠ 우주에서 눌렀을 때 트리의 그 폴더를 **편다**(`treeReveal`) — 접힌 채로 강조하면
     강조된 줄이 화면에 없다. */
function workspaceEnterFolder(path){
  const old=CANV,anchor=old?.nodes.find(n=>n.path===path&&n.kind==="sun"),vt=old?Object.assign({},old.vt):null;
  WORKSPACE_SCOPE=path||"";
  const L=canvasUniverse();
  if(vt){L.vt=vt;if(anchor){L.vt.x+=(anchor.x-L.gc.x)*vt.k;L.vt.y+=(anchor.y-L.gc.y)*vt.k}L.restoreVT=true}
  canvasMount();return L;
}
function canvasScopeFolder(path){
  if(!leaveEditorAllowed(()=>canvasScopeFolder(path)))return;
  if(path&&!VAULT_FOLDERS.includes(path)&&!vaultRows(canvasUniverse().tree,{}).some(r=>r.folder&&r.path===path))return;
  const changed=path!==WORKSPACE_SCOPE;
  canvasRemember();canvasAskClose();paneApply("r",0);
  const L=workspaceEnterFolder(path);L.relatedID=null;L.follow=null;L.glide=null;sel=null;WORKSPACE_SELECTED_ID=null;
  LZIP=treeReveal(LZIP,path);canvasLightsOff();
  if(path){canvasBoostSystem(L.focusID);const board=document.getElementById("cvb"),r=board?.getBoundingClientRect();if(r?.width)canvasGlideTo(L.focusID,canvasScopeScale(L,L.focusID,r.width,r.height))}else canvasFit(true);
  if(changed&&!cvReduced()&&!document.hidden)L.els?.root?.animate?.([{opacity:.4},{opacity:1}],{duration:180,easing:"ease-out"});
  paintHomeList();paintCanvasNavigation();treeScrollSel('.hmit.fold.scoped');
}
function canvasScopeExtent(L,id){
  let extent=160;
  for(const n of L.nodes){
    let p=n,reach=n.r+24;
    while(p&&p.id!==id){reach+=p.ring;p=p.parent?L.by[p.parent]:null}
    if(p)extent=Math.max(extent,reach);
  }
  return extent;
}
function canvasScopeScale(L,id,w,h){
  const box=canvasBox();
  return Math.max(.03,Math.min(1.25,(w-72)/box.w,(h-72)/box.h));
}
function canvasScopeSun(id,folderPath){const n=CANV?.by[id];if(n)canvasScopeFolder(folderPath||n.path||"")}
/* 위치·보기·질문은 한 번의 방문으로 복원한다. 상위 경로 이동과 방문 이력은 별개다. */
function canvasContext(){
  const L=CANV||{},list=document.getElementById("leftlist");
  return {id:L.focusID||null,path:L.focusPath||null,scoped:L.scoped||null,follow:L.follow||null,
    vt:Object.assign({},L.vt),relatedID:L.relatedID||null,query:CANVQ,queryVector:CQV,
    selectedID:workspaceSelectedID(),
    find:LFIND,zip:Object.assign({},LZIP),scroll:list?list.scrollTop||0:0,pane:PANE.r};
}
function canvasRemember(){
  const L=CANV;if(!L)return;
  (L.navStack||(L.navStack=[])).push(canvasContext());
  L.forwardStack=[];
}
function canvasRestore(frame){
  if(!CANV||!frame)return;
  const L=workspaceEnterFolder(frame.path||"");
  canvasAskClose();
  L.focusID=frame.id||null;L.focusPath=frame.path||null;L.scoped=frame.scoped||null;
  L.follow=frame.follow||null;L.glide=null;L.relatedID=frame.relatedID||null;
  if(frame.vt)L.vt=Object.assign({},frame.vt);
  if(frame.query!==undefined){CANVQ=frame.query;CQV=frame.queryVector||null}
  if(frame.find!==undefined)LFIND=frame.find;
  if(frame.zip)LZIP=Object.assign({},frame.zip);
  if(frame.selectedID!==undefined){WORKSPACE_SELECTED_ID=frame.selectedID;const i=DOC.fragments.findIndex(p=>p.id===frame.selectedID);sel=i<0?null:i}
  const input=document.getElementById("lfind");if(input)input.value=LFIND;
  const query=document.getElementById("cvq");if(query)query.value=CANVQ;
  const fixed=document.getElementById("workspacequery");if(fixed)fixed.value=L.relatedID?"":CANVQ;
  canvasPaintPanel();paneApply("r",sel===null?0:frame.pane||0);
  canvasApplyVT();canvasRelight();paintHomeList();paintCanvasNavigation();
  const list=document.getElementById("leftlist");if(list&&frame.scroll!==undefined)list.scrollTop=frame.scroll;
}
function canvasGoBack(){
  const L=CANV;if(!L||!leaveEditorAllowed(canvasGoBack)||!L.navStack?.length)return;
  (L.forwardStack||(L.forwardStack=[])).push(canvasContext());
  canvasRestore(L.navStack.pop());
}
function canvasGoForward(){
  const L=CANV;if(!L||!leaveEditorAllowed(canvasGoForward)||!L.forwardStack?.length)return;
  (L.navStack||(L.navStack=[])).push(canvasContext());
  canvasRestore(L.forwardStack.pop());
}
function canvasGoUp(){if(WORKSPACE_SCOPE)canvasScopeFolder(WORKSPACE_SCOPE.split("/").slice(0,-1).join("/"))}
function paintCanvasNavigation(){
  const el=document.getElementById("cvnav"),L=CANV;if(!el||!L)return;
  const node=L.focusID&&L.by[L.focusID];
  const source=L.relatedID&&DOC.fragments.find(p=>p.id===L.relatedID);
  const location=source?`${L.focusPath||"전체 저장소"} · ${source.title} 관련 자료`:(L.focusPath||node?.name||"전체 저장소");
  el.innerHTML=`<button id="cvhome" aria-label="전체 저장소" title="전체 저장소">◎</button>`
    +`<button id="cvup" aria-label="상위 폴더" title="상위 폴더" ${L.focusPath?"":"disabled"}>↑</button>`
    +`<span title="${esc(location)}">${esc(location)}</span>`;
  const home=document.getElementById("cvhome");if(home)home.onclick=canvasGoHome;
  const up=document.getElementById("cvup");if(up)up.onclick=canvasGoUp;
  const ask=document.getElementById("cvask");if(ask)ask.onclick=canvasAskToggle;
  const query=document.getElementById("workspacequery");
  if(query){query.placeholder=L.scoped?`${L.focusPath||node?.name||"현재 폴더"} 안에서 질문`:"전체 저장소에 질문";}
}

/* 지도의 오른쪽 판을 **제자리에서** 갈아끼운다. ⚠ 짓기와 손잡이 걸기가 **언제나 한 쌍**이라
   부르는 자리를 하나로 둔다 — 한쪽만 부르면 저장 버튼이 조용히 죽는다(#66-1 의 그 모양). */
function canvasPaintPanel(){
  const box=document.getElementById("right");if(!box)return;
  const cur=sel!==null?DOC.fragments[sel]:null;
  box.innerHTML=editPanel(cur);
  bindEditPanel(cur,saveChips(cur,null));
}
/* ★ 자유 질문 한 번. **여기가 이 화면의 동사 하나**다.
   ⚠ **글자 자로 먼저 칠하지 않는다.** `실측 2026-08-31`(#53): 이 말뭉치에서 글자 자는
     정답·오답·저장소 밖이 통째로 겹쳐 **색을 못 낸다.** 그걸로 한 번 칠하면 100ms 뒤 뜻 자가
     와서 판이 뒤집히고, 사람은 그 사이의 거짓 그림을 본다 — 기다리는 동안은 아무 말도 안 한다.
   ⚠ **선언된 갈림**: 브리지가 없거나(브라우저 단독) 색인이 없으면 글자 자로 돌고 화면이
     그렇게 적는다. ⚠ **알고 두는 한계** — 임베딩이 실패하면(`ContentGraph.embedDraft` 가
     표준오류에 적고 돌아온다) 이 화면은 「재는 중」에 머문다. 라이브 검색이 `QVEC` 를 영영
     못 받는 것과 같은 자리이고, 그때 지도가 틀린 순위를 내는 것보다 낫다. */
function canvasAsk(q,opt){
  if(CANV&&(CANVQ!==(q||"")||CANV.relatedID))canvasRemember();
  if(CANV)CANV.relatedID=null;
  CANVQ=q||"";
  const tag=document.getElementById("cvhow");
  /* 칸을 비운 것도 「그 질문을 떠난 것」이다 — 기다리던 기록을 같이 걷는다(`goMode` 와 같은 사정). */
  if(!CANVQ.trim()){CQV=null;askLogPending=null;if(tag){tag.className="cvhow";tag.textContent=""}canvasRelightSel();return}
  /* 벡터와 **그 벡터가 나온 글자**를 같이 든다 — `onQueryVector`·`gradePractice` 와 같은 규율.
     한 발 늦게 도착한 벡터로는 절대 안 매긴다. */
  const dv=DRAFT.canvas;
  CQV=(dv&&dv.t===CANVQ)?{q:CANVQ,v:dv.v}:null;
  const how=scorer(CANVQ,CQV,VEC);
  if(how!=="뜻"&&VEC&&bridged()){
    post("embedDraft",{slot:"canvas",kind:"query",text:CANVQ});
    if(opt&&opt.log)askLogPending=CANVQ;      /* ★ 기록은 벡터가 온 뒤 — 색 없는 줄을 먼저 안 적는다 */
    if(tag){tag.className="cvhow";tag.textContent="뜻으로 재는 중…"}
    /* ⚠ **옛 답을 들고 기다리지 않는다** (matt Spec 리뷰 ⑤). 안 끄면 화면은 B 를 물었는데
       A 의 선과 A 의 순위 상자를 그대로 보여준다 — 「기다리는 동안은 아무 말도 안 한다」가
       주석에서만 참이 되는 자리다. */
    canvasLightsOff();
    return;
  }
  if(tag){tag.className="cvhow"+(how==="뜻"?" mean":"");
    tag.textContent=how==="뜻"?"":"검색 준비 중"}
  /* ★ 입력 기록은 **사람이 Enter 로 물은 것만**(`opt.log`). 다시 그리기(색인 도착·판 갈림)는
     같은 질문을 두 번 적어 「또 물었다」를 지어낸다. */
  if(opt&&opt.log){askLogPending=null;canvasNoteAsked(CANVQ,CQV,how)}
  canvasPaint(CANVQ,CQV,how,opt);
}
/* 태양 질문 한 줄을 기록한다. 색은 **저장소 전체 1위**의 색이다 — 항성 범위가 아니라 갤럭시
   (판정선 = 「이 입력에 저장소가 답하나」).
   ⚠ 글자 자(`how!=="뜻"`)면 색 없이 적힌다 (#53). 브라우저 단독에서도 기록은 남는다 —
     `save()` 가 브리지가 없으면 localStorage 로 간다. */
function canvasNoteAsked(q,qv,how){
  const r=how==="뜻"?rank(q,qv,VEC):[];
  DOC.asked=logAsked(DOC.asked,q,"sun",verdictOf(r,how));
  save();
}
/* 초안 벡터가 도착해서 부르는 자리 (`onDraftVector`). **다시 물어보는 것이 아니라
   같은 질문을 이제 뜻 자로 재는 것**이라, 파동은 여기서 한 번 퍼진다. */
function canvasVectorArrived(){
  if(mode!=="stack"||stackView!=="edit"||CANV?.relatedID)return;
  const dv=DRAFT.canvas;
  if(!dv||dv.t!==CANVQ||!CANVQ.trim())return;
  /* ★ 기다리던 그 글자의 벡터가 왔다 — 여기서 처음으로 색이 있는 줄이 된다 */
  if(askLogPending===CANVQ){askLogPending=null;canvasNoteAsked(CANVQ,{q:CANVQ,v:dv.v},"뜻")}
  canvasAsk(CANVQ,{wave:true});
}
/* 벡터 꾸러미가 갈렸을 때 (`paintByVectors`). **오른쪽 판은 안 건드린다** — 사람이 치는 중일 수 있다. */
function canvasRefresh(){
  const L=CANV;
  /* ⚠ **서명을 판을 세우는 쪽과 같은 무리로 잰다** (matt Standards/Spec 리뷰 C2).
     무리를 재는 자리가 둘이면 서명이 영영 안 맞아 자가 바뀔 때마다 SVG 를 통째로 다시 짓는다.
     ★ **색인은 이제 서명에 안 든다** (#74) — 자리는 구조에서 나오므로 색인이 도착해도
       별은 안 움직인다. 갈리는 것은 불뿐이고 그것은 `canvasRelight` 가 든다. */
  if(!L||L.sig!==canvasSigNow()){canvasMount()}
  canvasRelight();
}

/* ★ 가운데 칸의 알맹이 — **`stackRender` 가 3단 사이에 끼워 넣는 글자다** (#67 재편).
   ⚠ 전 판은 `canvasRender()` 라는 **화면 하나**였다. 그것이 죽었다 — 헤더도 「쌓기로」도
     없다(돌아갈 곳이 없다: 여기가 홈이다). 검색줄(`#cvbar`)도 죽었고 그 동사는
     **가운데 태양**이 든다 (#70 확정 ④).
   ⚠ 「화면 맞춤」 버튼도 걷었다 — 접기/펴기마다 `canvasFit` 이 저절로 돈다(`bindResizer`). */
function canvasPane(){
  return `<div id="cvwrap"${cvReduced()?' class="rm"':""}>
      <div id="cvstage"><svg id="cvb"></svg></div><div id="cvnav"></div>
      <div class="workspacequery"><input id="workspacequery" aria-label="자료에 질문" placeholder="전체 저장소에 질문" value="${esc(CANV?.relatedID?"":CANVQ)}"><button id="workspaceask">검색</button></div>
      <span class="cvhow" id="cvhow"></span>

      <div class="cvrank" id="cvrank"></div>
      <div class="askpop" id="askpop">
        <input id="cvq" aria-label="저장소 질문" placeholder="질문" value="${esc(CANVQ)}">
</div>

    </div>`;
}
/* 가운데 칸의 손잡이 전부. **짓기(`canvasPane`)와 언제나 한 쌍이다** — 한쪽만 부르면
   태양이 눌리지도 별이 끌리지도 않는다(`editPanel`/`bindEditPanel` 과 같은 규율). */
function canvasBindPane(){
  /* ⚠ **안 지어졌으면 여기서 멈춘다** — 아래 셋이 전부 그 SVG 를 만진다(`canvasMount` 의 갈림) */
  if(!canvasMount())return;
  canvasBindBoard();
  canvasBindAsk();
  const fixed=document.getElementById("workspacequery"),submit=document.getElementById("workspaceask");
  const ask=()=>{const value=fixed.value;const run=()=>{paneApply("r",0);canvasAsk(value,{wave:true,log:true});paintCanvasNavigation()};if(!leaveEditorAllowed(run))return;run()};
  if(fixed)fixed.onkeydown=ev=>{if(ev.key==="Enter"){ev.preventDefault();ask()}};
  if(submit)submit.onclick=ask;
  if(typeof ResizeObserver!=="undefined"){
    if(CANVAS_RESIZE)CANVAS_RESIZE.disconnect();
    let size="";CANVAS_RESIZE=new ResizeObserver(entries=>{const r=entries[0]?.contentRect,key=r&&`${r.width}:${r.height}`;if(key&&key!==size){size=key;if(mode==="stack"&&stackView==="edit"){canvasFit();canvasWake()}}});
    CANVAS_RESIZE.observe(document.getElementById("cvb"));
  }
  /* ★ 창이 커지면 다시 맞춘다 — **없으면 지도가 칸 한구석에 오그라든 채로 남는다**
     (`실측`: 목업에서 창을 키우자 점 구름이 왼쪽 위에 몰린 채 그대로였다).
     ⚠ **대입이다.** 여러 번 렌더해도 손잡이가 하나뿐이고, 다른 화면에 가면 스스로 비킨다. */
  onresize=()=>{if(mode==="stack"&&stackView==="edit"){canvasFit();canvasWake()}};
  /* ★ 창이 숨으면 루프도 잔다 (#75 1). ⚠ **대입이다** — 여러 번 렌더해도 손잡이가 하나다.
     ⚠ 깨우는 자리를 여기 하나로 두고, 자는 판정은 프레임 안에서 매번 다시 한다. */
  try{document.onvisibilitychange=canvasWake}catch(e){}
  /* reduced-motion 을 **끄는** 쪽도 듣는다 — 안 들으면 켰다 끈 사람의 우주가 다음 클릭까지 굳는다(matt Spec 리뷰 #75 C3) */
  try{const mq=matchMedia("(prefers-reduced-motion: reduce)");if(mq&&!mq.__cv){mq.__cv=1;mq.addEventListener("change",canvasWake)}}catch(e){}
  /* 들고 있던 질문이 있으면 **조용히** 다시 칠한다 — 저장·선택 뒤에 지도가 꺼져 보이면
     「검색이 사라졌다」로 읽힌다. 파동은 안 퍼뜨린다(같은 결과다). */
  canvasRelight();
  paintCanvasNavigation();
  canvasWake();   /* ★ 공전을 돌린다 (#75) — 자는 조건은 루프가 스스로 다시 잰다 */
}
/* ★ 경계면 하나를 살린다 (#67 스펙 3 · 목업 v4). **접기 버튼이 아니라 끌기다.**
   ⚠ 폭을 `PANE` 에 적고 **그 자리에서 칸만 고친다** — 다시 그리면 끄는 중에 편집기가
     통째로 갈아끼워져 사람이 치던 글자가 날아간다(`paintHomeList` 와 같은 규율).
   ⚠ 임계(`PANE_SNAP`) 아래면 **0 으로 스냅**한다. 억지로 좁힌 칸은 읽히지도 눌리지도 않는데,
     그 상태가 「접힘」과 구별이 안 가면 사람은 자기가 무엇을 봤는지 모른다.
   ⚠ 끝날 때 `canvasFit()` 을 부른다 — 가운데가 커졌는데 별자리가 그대로면 접기가
     「캔버스 확대」로 안 읽힌다(그것이 이 스펙의 전부다). */
function bindResizer(hid,pid,key){
  const h=document.getElementById(hid),p=document.getElementById(pid);
  if(!h||!p)return;
  let sx=0,sw=0,on=false;
  const put=w=>paneApply(key,w);
  const clamp=w=>w<PANE_SNAP?0:Math.max(PANE_MIN[key],Math.min(PANE_MAX,w));
  h.onpointerdown=ev=>{
    on=true;sx=ev.clientX;sw=p.getBoundingClientRect().width;
    try{h.setPointerCapture(ev.pointerId)}catch(e){}
    h.classList.add("on");document.body.classList.add("rzing");
    ev.preventDefault();
  };
  h.onpointermove=ev=>{if(on)put(clamp(sw+(key==="l"?ev.clientX-sx:sx-ev.clientX)))};
  const end=()=>{
    if(!on)return;
    on=false;h.classList.remove("on");document.body.classList.remove("rzing");
    canvasFit();
  };
  h.onpointerup=end;h.onpointercancel=end;
  /* 접힌 손잡이를 두 번 누르면 편다 — 되돌리는 길이 끌기 하나뿐이면 접은 사람이 갇힌다 */
  const toggle=()=>{put(PANE[key]>0?0:PANE_DEF[key]);canvasFit()};
  h.ondblclick=toggle;
  /* ★ 키보드로도 닿는다 — **머리글이 그렇다고 적었으니 실제로 그래야 한다**
     (matt Standards 리뷰 ③: 손잡이가 `pointer*` 뿐인데 주석은 Enter 를 약속하고 있었다).
     화살표는 24px 씩 밀고 Enter 는 접었다 편다. ⚠ 방향은 칸마다 뒤집힌다 — 오른쪽 칸은
     왼쪽으로 끌어야 넓어진다(끌기와 같은 부호). */
  h.onkeydown=ev=>{
    const w=p.getBoundingClientRect().width;
    if(ev.key==="ArrowLeft"||ev.key==="ArrowRight"){
      ev.preventDefault();
      put(clamp(w+(ev.key==="ArrowRight"?1:-1)*(key==="l"?1:-1)*24));canvasFit();
    }else if(ev.key==="Enter"||ev.key===" "){ev.preventDefault();toggle()}
  };
}
/* ★ 태양을 누르면 질문 칸이 뜬다 (#70 확정 ④) — **이 화면의 동사 하나가 여기로 옮겨졌다.**
   ⚠ 전 판은 화면 머리의 검색줄(`#cvbar`)이었다. 그것이 죽은 이유는 재편이다: 홈의 머리는
     이제 3단 전체의 머리라 지도만의 칸을 둘 자리가 아니다.
   ⚠ **팝오버는 판 안에 산다** — 창을 새로 만들면 그 창이 면접 중에 뜰 수 있는 창이 되고,
     그러면 은신(`WindowPrivacy`)을 다시 따져야 한다. 여기는 웹뷰 안이라 그 문제가 없다.

   ★ **손잡이가 두 자리로 갈라져 있다. 그게 사고를 막는 자리다** (`실측 2026-09-02` 실앱):
     태양(`#orbg`)은 **SVG 안**이라 `canvasMount` 가 판을 다시 지을 때마다 **새 것이 된다** —
     색인이 도착하면(`canvasRefresh`) 그 일이 벌어지고, 그때 손잡이를 다시 안 걸면
     **태양이 조용히 안 눌린다.** 그래서 태양의 손잡이는 `canvasMount` 안에서 걸고,
     여기서는 **다시 안 지어지는 것**(팝오버의 입력 칸)만 건다. */
function canvasAskClose(){
  const orb=document.getElementById("orbg"),pop=document.getElementById("askpop");
  if(pop)pop.classList.remove("show");
  if(orb)orb.classList.remove("asking");
}
function canvasAskToggle(){
  const fixed=document.getElementById("workspacequery");
  if(fixed&&fixed.parentNode){fixed.focus();return}

  const orb=document.getElementById("orbg"),pop=document.getElementById("askpop"),
        q=document.getElementById("cvq");
  if(!orb||!pop||!q)return;
  if(pop.classList.contains("show"))return canvasAskClose();
  /* 태양 바로 아래 앉힌다 — 판 좌표를 화면 좌표로 옮긴다(`canvasTip` 과 같은 식) */
  const L=CANV;
  if(L){
    const C=(L.focusID&&L.by[L.focusID])||canvasCenter();
    pop.style.left=(C.x*L.vt.k+L.vt.x)+"px";
    pop.style.top=(C.y*L.vt.k+L.vt.y+(CV_ORB+14)*L.vt.k)+"px";
  }
  pop.classList.add("show");orb.classList.add("asking");
  q.focus();q.select();
}
function canvasBindAsk(){
  const q=document.getElementById("cvq");if(!q)return;
  /* Enter 가 「훑기」다 — 한 글자마다 퍼지면 화면이 시끄럽고 임베딩도 매 타건마다 돈다.
     ⚠ 칸을 비우면 그 자리에서 불이 꺼진다(들고 있을 결과가 없다). */
  q.oninput=()=>{if(!q.value.trim())canvasAsk("")};
  q.onkeydown=ev=>{
    if(ev.key==="Enter"){ev.preventDefault();canvasAsk(q.value,{wave:true,log:true});canvasAskClose()}
    else if(ev.key==="Escape"){ev.preventDefault();canvasAskClose()}
  };
}
/* 줌·팬·끌기 — 손코드.
   ⚠ **배치(`CANV`)를 손잡이 안에 가둬 두지 않는다.** 색인이 갈리면 `canvasRefresh` 가
     `canvasMount` 만 다시 부르고 그때 `CANV` 는 **새 객체**가 된다 — 손잡이가 옛 것을 붙들고
     있으면 끌기·줌이 **조용히 죽는다**(옛 배치의 수를 고치는데 화면은 새 배치를 그린다).
     그래서 매 이벤트에 전역을 다시 읽는다. */
function canvasBindBoard(){
  const board=document.getElementById("cvb");
  if(!board)return;
  board.addEventListener("wheel",ev=>{
    const L=CANV;if(!L)return;
    ev.preventDefault();canvasTipOff();L.follow=null;L.glide=null;
    const r=board.getBoundingClientRect(),mx=ev.clientX-r.left,my=ev.clientY-r.top;
    const f=Math.exp(-ev.deltaY*.0016),nk=Math.max(.03,Math.min(3.2,L.vt.k*f)),s=nk/L.vt.k;
    L.vt.x=mx-(mx-L.vt.x)*s;L.vt.y=my-(my-L.vt.y)*s;L.vt.k=nk;canvasApplyVT();
  },{passive:false});
  board.onpointerdown=ev=>{
    const L=CANV;if(!L)return;
    /* ★ **태양은 여기서 손을 뗀다** (`실측 2026-09-02` 실앱). 판이 모든 pointerdown 에
       `setPointerCapture` 를 걸면 pointerup 의 과녁이 판이 되고, `click` 은 내림·올림의
       공통 조상(= 판)으로 가서 **`orb.onclick` 이 영영 안 불린다.** JS 의 `orb.click()` 은
       이 길을 안 지나서 QA 는 초록이었다 — 진짜 포인터만 죽는 자리. */
    if(ev.target.closest&&ev.target.closest("#orbg"))return;
    const g=ev.target.closest?ev.target.closest(".cvn"):null;
    const n=g?L.by[g.dataset.f]:null;
    L.drag={sx:ev.clientX,sy:ev.clientY,moved:0,node:n,
            oa:n?n.ang:0,ox:L.vt.x,oy:L.vt.y};
    try{board.setPointerCapture(ev.pointerId)}catch(e){}
    if(!n)board.classList.add("grabbing");
  };
  board.onpointermove=ev=>{
    const L=CANV,d=L&&L.drag;if(!d)return;
    const dx=ev.clientX-d.sx,dy=ev.clientY-d.sy;
    d.moved=Math.max(d.moved,Math.hypot(dx,dy));
    if(d.moved>3)canvasTipOff();
    if(d.node){
      if(d.node.fixed)return;
      /* ★ **위상만 바뀐다** (design.md §3: *"궤도 위 위상만 바뀐다 · 반지름·궤도 안 바뀜"*).
         손끝의 판 좌표에서 부모 중심을 향한 **각도**를 다시 내고 반지름은 그대로 쓴다. */
      const r=board.getBoundingClientRect();
      const px=(ev.clientX-r.left-L.vt.x)/L.vt.k,py=(ev.clientY-r.top-L.vt.y)/L.vt.k;
      d.node.ang=workspaceOrbitAngle(d.node,px-d.node.cx,py-d.node.cy);
      /* ★ **놓은 자리에서 이어 돈다** (#75 1) — 위상 오프셋을 지금 각도에 맞춰 다시 낸다.
         안 고치면 손을 뗀 순간 별이 원래 위상으로 순간이동한다. */
      d.node.phase=d.node.ang-orbitAngle(d.node.base,d.node.clk,
        d.node.period||ORBIT_PERIOD[d.node.kind]||ORBIT_PERIOD.planet);
      canvasReflow();canvasPlace();
    }
    else{if(d.moved>3){L.follow=null;L.glide=null}L.vt.x=d.ox+dx;L.vt.y=d.oy+dy;canvasApplyVT()}
  };
  board.onpointerup=()=>{
    board.classList.remove("grabbing");
    const L=CANV,d=L&&L.drag;if(L)L.drag=null;
    canvasWake();   /* 잡고 있는 동안 시계가 멈춘 몸이 있다 — 놓으면 그 자리에서 다시 돈다 */
    /* 끌었으면 고르기가 아니다 — 4px 이 그 갈림이다 */
    if(d&&d.node&&d.moved<4){
      /* ★ **항성을 누르면 범위 지정이다** (#74 C1 · design.md §3). 들고 있던 질문이
         그 항성 안에서 다시 돈다. 질문이 없으면 범위만 든 채로 불을 끈다 —
         빈 손으로 색을 칠하면 그것이 곧 거짓 측정이다.
         ⚠ 작은 중심(폴더)은 **아직 누르는 것이 아니다** — 파일이 없어 열 판도, 잴 벡터도 없다. */
      /* ⚠ 범위 지정은 **트리의 폴더 줄과 같은 함수**다 (#75 4) — 두 문이 갈리면 우주로
         들어왔을 때만 트리가 안 펴지는 식으로 조용히 어긋난다. */
      if(d.node.kind==="sun"||d.node.kind==="center")canvasScopeSun(d.node.id);
      else if(d.node.kind==="planet"||d.node.kind==="moon"){
        const tick=performance.now(),double=L.lastClick&&L.lastClick.id===d.node.id&&tick-L.lastClick.at<350;
        L.lastClick={id:d.node.id,at:tick};
        if(double)workspaceOpen(d.node.id);else canvasNavigateFile(d.node.id);
      }
    }
    /* 빈 곳을 누르면 질문을 놓는다(목업 `svg click → closeAsk+lightsOff`). 고른 별이 있으면 그리로 돌아간다 */
    else if(d&&!d.node&&d.moved<4){canvasAskClose();if(CANVQ.trim()){canvasDropQuestion();canvasRelightSel()}}
    /* ★ **끈 자리를 안 남긴다** (#74). 배치 사이드카가 걷혔다 — 별의 자리는 이제 볼트
       폴더(궤도)가 정하고, 끌기는 **이 세션의 위상**일 뿐이다. */
  };
  board.onpointercancel=()=>{if(CANV)CANV.drag=null;board.classList.remove("grabbing")};
  /* 몸이 포인터 밑에서 돌아 나가면 그 몸의 leave 가 안 온다 — 판을 나갈 때 슬로우를 푼다 */
  board.onpointerleave=()=>{const C=CANV;if(C)C.hover=null;canvasTipOff()};
}

/* ★ 왼쪽 칸에 **끌어다 놓으면 받기 화면이 뜬다** (그릴 Q5).
   ⚠ **새 통로를 안 만들었다** — 여는 것은 이미 있는 받기 화면이고, 글자는 그 화면의
     붙여넣기 칸(`#doc`)으로 들어간다. 자르기·초안은 그대로 한 곳이다.
   ⚠ **평문만 여기서 읽는다.** hwpx·docx·pdf 는 브라우저가 못 푼다 — 그 자리는 이름과
     사유를 세우고 「파일 고르기」(Swift 통로)로 보낸다. 조용히 빠지지 않게. */
/* 과녁 하나를 세운다. ⚠ **과녁마다 손잡이를 베끼지 않는다** — 왼쪽 칸과 받기 화면이 같은
   함수를 부르고, 다른 것은 어느 칸이 초록 테를 두르나뿐이다 (#66-9). */
function bindDropTarget(id){
  const box=document.getElementById(id);if(!box)return;
  box.ondragover=e=>{e.preventDefault();box.classList.add("drop")};
  box.ondragleave=()=>box.classList.remove("drop");
  box.ondrop=e=>{e.preventDefault();box.classList.remove("drop");ingestFromDrop(e.dataTransfer)};
}
/* 붙여넣기 칸에 **이어붙인다** — 지우지 않는다. 한 칸으로 모으는 것이 `onIngestFiles` 와 같은 규율이다. */
function appendIngestText(ta,add){
  if(!ta||!add)return;
  ta.value=(ta.value.trim()?ta.value.trim()+"\n\n":"")+add;
}
const DROP_TEXT=/\.(txt|md|markdown|text|csv|json)$/i;
function ingestFromDrop(dt){
  if(stackView!=="ingest"&&!leaveEditorAllowed())return;
  /* ★ **이미 받기 화면이면 다시 안 그린다** (#66-9). `ingestRender` 는 화면을 통째로 지어서
     붙여넣기 칸의 글자와 `INTAKE` 를 같이 날린다 — 받기 화면에서 떨어뜨린 사람은
     **방금 친 글을 잃는다.** 여는 것은 아직 안 열렸을 때뿐이다. */
  if(stackView!=="ingest"){stackView="ingest";stackRender()}
  const ta=document.getElementById("doc");if(!ta||!dt)return;
  const files=[].slice.call(dt.files||[]);
  if(!files.length){
    let t="";try{t=dt.getData("text/plain")||""}catch(e){}
    if(t.trim())appendIngestText(ta,t.trim());
    return;
  }
  const ok=[],bad=[];let left=files.length;
  const done=()=>{
    if(ok.length)appendIngestText(ta,ok.map(f=>f.text.trim()).filter(Boolean).join("\n\n"));
    paintFileRows(ok,bad);
  };
  files.forEach(f=>{
    const name=f.name||"이름 없는 파일";
    const isText=DROP_TEXT.test(name)||String(f.type||"").indexOf("text/")===0;
    if(!isText){
      bad.push({name:name,why:"끌어다 놓기로는 평문만 읽어요 — 「파일 고르기」로 넣어 주세요"});
      if(!--left)done();return;
    }
    const r=new FileReader();
    r.onload=()=>{ok.push({name:name,text:String(r.result||"")});if(!--left)done()};
    r.onerror=()=>{bad.push({name:name,why:"못 읽었어요"});if(!--left)done()};
    r.readAsText(f);
  });
}

/* ★ 받기 화면 (#14 → #40) — **쌓기 모드 안**이다. 모드가 아니라 쌓기의 한 화면이라
   면접 모드와 무관하고, 판정선 검사는 `stackRender` 를 경계로 삼으므로 이 아래를 안 센다.
   #40 이 더한 것 둘: **파일로 받는 길**(`pickIngestFiles`)과 **덩이마다 초안**(`draftFragment`).
   ⚠ 붙여넣기 칸은 그대로다 — 파일도 결국 **이 칸으로 들어온다**(`onIngestFiles`). 받는 길이
     둘이어도 자르기·초안은 한 곳이어야 두 길이 안 갈린다.
   ★ #46 이 모양만 고쳤다 — **큰 안내 한 문장 + 카드 하나**(목업 ①). 「파일 고르기」가 위 막대에서
     카드 안으로 내려왔다: 넣는 일 셋(파일·붙여넣기·갈라보기)이 한 흐름이라 한 상자에 산다.
     손잡이 이름(`pick`·`split`·`doc`·`ifiles`)은 **하나도 안 바뀌었다.** */
function ingestRender(){
  /* 화면을 새로 지으면 덩이 카드도 사라진다 — 들고 있던 진행은 **가리킬 카드가 없어** 낡았다
     (`receiveDocument` 가 `DRAFT` 를 비우는 것과 같은 이유). */
  INTAKE=null;
  app.innerHTML=`<div id="top" class="drag"><span id="brand">Clonie</span>
      <span id="stat">시작하기</span><span style="flex:1"></span>
      <button class="ibtn ico nodrag" id="back" title="저장소로" aria-label="저장소로">${ICO.back}</button>
      <button class="ibtn nodrag" id="x">✕</button></div>
    <div id="ingest">
      <div><div class="ihx">파일이나 자소서를 던져 넣으면, 답변으로 잘라 드려요</div>
        <div class="ihs">기계가 하는 건 자르기와 제안까지예요 — 저장하기 전에는 아무것도 저장소에 안 앉아요</div></div>
      <div class="icard">
        <div><span class="fl">붙여넣기 · 문항 번호가 있으면 문항에서, 없으면 빈 줄에서 갈라요</span>
          <textarea id="doc" spellcheck="false" placeholder="1. 지원동기를 서술해 주십시오&#10;저는 …&#10;&#10;2. 협업 과정에서 갈등을 해결한 경험을 서술해 주십시오&#10;팀 프로젝트에서 …"></textarea></div>
        <div id="ifiles"></div>
        <div class="row"><button class="gbtn p" id="split">갈라보기</button>
          <button class="gbtn" id="pick">파일 고르기</button>
          <span style="flex:1"></span><span class="foot" id="iprv">이 맥 밖으로 나가지 않아요</span></div>
        <div id="cloud"></div>
      </div>
      <div id="ierr"></div><div id="ibar"></div><div id="cands"></div><div id="isum"></div>
    </div>`;
  /* ★ **설정에 잠깐 다녀온 사람의 글을 되돌린다** (#65 P3-4). 위에서 화면을 새로 지었으니
     붙여넣던 글은 방금 사라졌다 — 자리표를 든 사람에게만 그것을 도로 앉힌다.
     ⚠ **한 번만이다.** 여기서 자리표를 비운다 — 안 비우면 다음에 이 화면을 여는 사람에게
       남의 글이 앉는다(자리표는 세션에 산다). */
  if(SETBACK&&SETBACK.view==="ingest"){
    const back=document.getElementById("doc");if(back)back.value=SETBACK.doc;
    SETBACK=null;
  }
  /* 나가는 문. ⚠ **표식(`ingestOptOut`)을 안 세운다** — 첫 실행이 사람을 이리 끌고 오던
     줄이 걷혔다(승격 라운드 #61 A). 이제 이 화면은 사람이 눌러야만 열린다. */
  document.getElementById("back").onclick=()=>{stackView="edit";stackRender()};
  document.getElementById("x").onclick=()=>post("closeWindow");
  document.getElementById("split").onclick=splitDoc;
  /* ⚠ 브라우저 단독(`cue.html`)엔 이 통로가 없다 — **말없이 아무 일도 안 일어나면 안 된다.**
     `bridged()` 로 갈라 그 자리에서 이유를 세운다(`load`/`save` 가 갈리는 것과 같은 규율). */
  document.getElementById("pick").onclick=()=>{
    if(!bridged()){paintFileRows([],[{name:"파일 고르기",why:"이 창에는 파일 통로가 없어요 — 붙여넣기로 넣어 주세요"}]);return}
    if(!pickTake(PICKING,"ingest"))return;   /* 연타는 시트를 큐에 쌓는다 (#80 1) */
    paintPicking("pick","ingest");
    post("pickIngestFiles")};
  paintPicking("pick","ingest");   /* 고르는 중에 화면을 다시 지어도 잠금이 보인다 */
  /* ★ **받기 화면에도 과녁을 둔다** (#66-9, `실측 2026-09-01`). 파일 통로가 있는 유일한
     화면인데 여기 떨어뜨리면 `document.ondrop preventDefault`(`render` 머리글)가 삼켜서
     **무반응·무안내**였다 — 왼쪽 칸에서만 되는 동작이라는 것을 알 길이 없다. */
  bindDropTarget("ingest");
  paintCloudRow();
}
/* ★ 「이 화면이 공통 지능을 걸어도 되나」 — **순수 함수라 `node --test` 가 잠근다**
   (2026-09-02, 리뷰 발견 ①).
   - `ready`  = **지금 고른 두뇌가 되나.** 짓는 자는 Swift 의 `shownLane` 이고, 그건
     **마지막에 잰 로그인 자국까지 본다**(`DrafterChoice.shownLane`)
   - `choice` = 지금 고른 두뇌(`auto`·`claude`·`codex`·`key`). **`CHOICE` 가 정본이다**

   ⚠ **왜 `ready` 하나로 못 막나**: 그 자국은 **낡는다.** 터미널에서 방금 로그인하고 돌아온
     사람은 `ready:false` 로 그려지는데, 그때 화면이 토글까지 죽이면 `cloud:false` 로 나가고
     **Swift 의 두드리는 판정(`lane` — 자국을 안 믿고 진짜로 두드려 보는 쪽)이 애초에 안 불린다.**
     `CliDrafter.lastLoggedIn` 머리글이 배려한다고 적어 둔 바로 그 사람에게서 깨지던 자리다.
   ⚠ **그래서 명시 선택은 게이트를 안 받는다.** 진짜로 죽어 있으면 Swift 의 `unavailable`
     통로가 정직하게 실패하고 화면이 그 사유를 띄운다(`draftFragment`) — 새 규율을 만드는 것이
     아니라 **이미 있는 규율에 도달하게** 하는 것이다.
   ⚠ **`auto` 는 그대로 막는다.** 자동은 「아무 데도 안 걸렸다」가 곧 온디바이스라, 켜 두면
     덩이마다 헛왕복만 는다 — 사람이 고른 것이 없으니 정직하게 실패할 대상도 없다. */
function cloudArmed(ready,choice){
  return !!ready||(!!choice&&choice!=="auto");
}
/* ★ 「지금 켜져 있어야 하나」 — **순수 함수라 `node --test` 가 잠근다** (#55).
   - `ready`·`choice` = 위 `cloudArmed` 와 같은 뜻
   - `pref`   = 사람이 남긴 선호. `"device"` 면 「이 맥 안에서만」
   - `touched`= 이번 세션에 사람이 토글을 만졌나 · `cur` = 그때 고른 값
   ⚠ 갈림 순서가 뜻이다: ① 걸 수 없으면 무조건 끈다 · ② 이번 세션의 선택이 저장된 선호보다
     세다 · ③ 아무것도 없으면 **켬**이 기본이다(#55).
   ⚠ `choice` 를 안 주면 `auto` 로 읽는다 — 옛 호출·브라우저 단독이 조용히 세지지 않게. */
function cloudDefault(ready,pref,touched,cur,choice){
  if(!cloudArmed(ready,choice))return false;
  if(touched)return !!cur;
  return pref!=="device";
}
/* ★ Swift 가 공통 지능을 켤 수 있는지 알려 왔다 (#51 → #55). 창이 뜰 때와 **설정을 저장할 때**
   온다 — 사람이 키를 넣고 돌아오면 그 자리에서 줄이 바뀌어야 한다.
   ⚠ **키도 경로도 안 온다.** 오는 것은 층별로 되나 안 되나 · 제공자 이름 · 모델 이름 ·
     CLI 이름 · 못 켜는 이유뿐이다. */
function setCloudDrafter(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d)return;
  CLOUD.ready=!!d.ready;CLOUD.key=!!d.key;
  /* ★ **키 칸이 읽는 것은 `hasKey` 다** (2026-09-02, 리뷰 H3). `key` 는 「키 층이 준비됐나」라
     주소·모델까지 본 값이고, 그것으로 placeholder 를 그리면 **키를 넣고 모델을 안 고른 사람에게
     「없어요」라고 거짓말한다.** 두 칸이 뜻이 다르므로 두 칸으로 온다(Swift `sendCloudReady`). */
  CLOUD.hasKey=!!d.hasKey;
  /* 「자동」이 지금 어디로 나가나 — **글자째로 온다.** 화면이 다시 유도하지 않는다
     (2026-09-02, 리뷰 P1·H2: 전엔 여기서 한 벌 더 판정했고 Swift 와 갈려 있었다). */
  CLOUD.autoLabel=String(d.autoLabel||"");
  /* ★ **「지금 어디로 나가나」는 따로 온다** (2026-09-01, 두뇌 선택). `key` 는 계속
     「키가 저장돼 있나」이고(설정의 키 칸이 그것을 읽는다), 이 칸이 「이번에 두드릴 층」이다 —
     겹쳐 담으면 키를 넣어 둔 사람이 두뇌를 바꾼 순간 키 칸이 「없어요」로 바뀐다. */
  CLOUD.lane=String(d.lane||"");
  /* ★ **고른 두뇌의 집은 `CHOICE` 하나다** (2026-09-02, 리뷰 발견 ⑥). 전엔 이 회신이 `CLOUD`
     안에 한 벌 더 앉혔고 **아무도 안 읽었다** — 그런데 받기 화면은 그 값이 필요하다
     (`cloudArmed`). `detectCli` 는 **설정 화면을 열 때만** 도니까(`openSettings`), 이 통로가
     안 채워 주면 받기 화면의 `CHOICE` 는 창이 뜬 내내 `auto` 로 남는다 — 명시 선택이
     그 화면에서만 조용히 사라지는 자리다. 두 통로 다 정본은 Swift 의 `UserDefaults` 라 안 갈린다.
     ⚠ **없는 칸은 안 덮는다** (`onCliStatus` 와 같은 규율). */
  if(d.choice)CHOICE=String(d.choice);
  CLOUD.provider=String(d.provider||"");CLOUD.cliName=String(d.cliName||"");
  CLOUD.model=String(d.model||"");CLOUD.why=String(d.why||"");
  /* ★ 프론트 설정 화면이 「지금 고른 프리셋」을 그리는 데 쓴다 (#61 B·C).
     ⚠ **키는 여전히 안 온다** — 오는 것은 「키가 저장돼 있나」(`CLOUD.hasKey`)뿐이다. */
  CLOUD.type=String(d.type||"");CLOUD.url=String(d.url||"");
  CLOUD.on=cloudDefault(CLOUD.ready,readDrafterPref(),cloudTouched,CLOUD.on,CHOICE);
  paintCloudRow();
  /* ★ **설정의 두뇌 목록도 여기서 고쳐 쓴다** (2026-09-02, 리뷰 H3). 키 층 상태와 「자동은
     어디로」의 집이 이 회신 하나가 됐으므로, 키를 저장한 **그 화면에서** 목록이 따라와야 한다 —
     전엔 설정을 닫았다 다시 열어야(=`detectCli` 가 다시 돌아야) 고쳐졌다.
     ⚠ 그 화면이 안 떠 있으면 `paintBrain` 이 칸을 못 찾고 그냥 돌아온다(공짜다). */
  paintBrain();
}
/* 옵트인 한 줄을 제자리에서 다시 그린다. **화면을 새로 안 짓는다** — 사람이 붙여넣기 칸에
   글을 치는 중일 수 있다(`paintCur` 과 같은 규율).
   ⚠ **바로 위 「이 맥 밖으로 나가지 않아요」도 같이 고친다.** 켠 상태에서 그 문장이 그대로
     남아 있으면 화면이 거짓말을 한다 — 이 화면에서 그건 기능 하나보다 비싸다. */
function paintCloudRow(){
  const el=document.getElementById("cloud");if(!el)return;
  const prv=document.getElementById("iprv");
  /* ★ **토글을 죽이는 것은 `ready` 가 아니라 `cloudArmed` 다** (2026-09-02, 리뷰 발견 ①).
     명시 선택은 자국이 낡아도 토글이 살아 있어야 한다 — 죽이면 Swift 의 두드리는 판정에
     **닿지도 못하고** 온디바이스로 내려간다(그 머리글이 근거를 든다). */
  if(!cloudArmed(CLOUD.ready,CHOICE)){
    el.innerHTML=`<span class="foot">${esc(CLOUD.why||"외부 AI로 정리하려면 설정에서 API 키를 입력하거나 공식 CLI를 설치해 주세요.")}</span>`;
    if(prv)prv.textContent="이 맥 밖으로 나가지 않아요";
    return;
  }
  /* ⚠ **이번에 실제로 두드릴 층의 이름을 쓴다** (`CLOUD.lane`). 전엔 「키가 저장돼 있나」
     (`CLOUD.hasKey`)로 갈랐는데, 두뇌 선택이 생기면서 그 둘이 갈렸다 — 키를 넣어 둔 사람이
     「Codex 구독」을 고르면 이 줄이 **키로 보낸다고 거짓말한다.** 판정은 Swift 가 한다.
     ⚠ CLI 쪽은 **주어 꼴**로 쓴다 — 「Claude Code 가 만들어요」. 조사 문제를 안 만든다.
     ★ **자국이 「연결 안 됨」일 때는 층 이름을 안 짓는다.** 그 자리의 `lane` 은 `device` 라
       이름을 그대로 쓰면 「이 맥에 깔린 공식 CLI 가 만들어요」라고 **거짓말**한다 —
       두드려 봐야 아는 판이니 화면도 그렇게 말한다. */
  const providerName=String(CLOUD.provider||"").trim();
  const isOllama=providerName.toLowerCase()==="ollama";
  const who=!CLOUD.ready
    ?"선택한 설정을 사용해요"
    :(CLOUD.lane==="key"
      ?(isOllama
        ?`Ollama로 정리해요${CLOUD.model?` · ${esc(CLOUD.model)}`:""}`
        :`내 키로 ${esc(providerName+(CLOUD.model?" · "+CLOUD.model:""))} 에 보내요`)
      :`이 맥에 깔린 ${esc(CLOUD.cliName||"공식 CLI")} 가 만들어요`);
  /* 미연결 사유는 그대로 보여 주되, 설정이 없을 때 외부 호출을 약속하지 않는다.
     `CLOUD.why` 는 Swift 의 `DrafterChoice.notConnected` 사유다. */
  const foot=!CLOUD.ready
    ?esc(CLOUD.why||"설정이 준비되지 않았어요.")
    :(CLOUD.on
      ?"켜 두면 갈라놓은 이 문서의 덩이만 나가요 — 저장된 조각과 면접 중 들리는 말은 안 보내요"
      :"꺼져 있으면 이 맥 밖으로 안 나가요 — 이 맥의 모델이 뽑아요");
  el.innerHTML=`<label class="ctog"><input type="checkbox" id="cloudon"${CLOUD.on?" checked":""}>
      <span>외부 AI로 정리 · ${who}</span></label>
    <span class="foot">${foot}</span>`;
  /* ⚠ `textContent` 라 `esc` 를 안 쓴다 — 여기서 escape 하면 `&amp;` 가 눈에 보인다 */
  /* ⚠ 조사는 **「에」**로 붙인다 — 제공자 이름이 영문·한글 아무거나 올 수 있어서
     「로/으로」는 반드시 어느 한쪽에서 틀린다 */
  /* ⚠ **켜져 있으면 「안 나가요」라고 못 한다** — 자국이 낡았을 뿐일 수 있어 실제로 나간다.
     나가는 곳의 이름을 모르는 것뿐이라, 이름 없이 나간다는 사실만 말한다. */
  if(prv)prv.textContent=CLOUD.on
    ?(!CLOUD.ready?"외부 AI 사용을 선택했어요"
      :CLOUD.lane==="key"?(isOllama?"뽑을 때만 Ollama로 정리해요":`뽑을 때만 ${providerName} 에 보내요`)
                        :`뽑을 때만 ${CLOUD.cliName||"공식 CLI"} 를 거쳐 나가요`)
    :"이 맥 밖으로 나가지 않아요";
  /* ⚠ **끈 것만 남긴다** (#55). 켠 것은 안 남긴다 — 남은 것이 조용히 만드는 결과가
     「나간다」쪽이면 안 되고, 「안 나간다」쪽이면 괜찮다. */
  const c=document.getElementById("cloudon");
  if(c)c.onchange=e=>{CLOUD.on=!!e.target.checked;cloudTouched=true;
    writeDrafterPref(CLOUD.on?"":"device");paintCloudRow()};
}
/* ★ 파일이 도착했다 (#40). Swift `pickIngestFiles` 의 답. **본문을 붙여넣기 칸에 이어붙인다** —
   자르기·초안이 한 길로만 가게. 못 읽은 파일은 이름과 사유를 그대로 세운다(조용히 빠지지 않게).
   ⚠ 글자를 **손질하지 않는다.** 자르기는 `sliceIntake` 하나가 하고, 여기서 먼저 자르면 자가 둘이 된다. */
function onIngestFiles(json){
  /* ★ **맨 위에서 푼다** (#80 1). 아래 관문 셋이 전부 조기 반환이라 끝에서 풀면 못 읽은
     짐 하나에 버튼이 잠긴 채 남는다 — 취소도 여기로 오므로 이 자리가 유일한 문이다. */
  pickFree(PICKING,"ingest");paintPicking("pick","ingest");paintPicking("ingbtn","ingest");
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d)return;
  const ta=document.getElementById("doc");if(!ta)return;
  const files=(d.files||[]).filter(f=>f&&(f.text||"").trim()),errors=d.errors||[];
  if(files.length){
    const add=files.map(f=>f.text.trim()).join("\n\n");
    ta.value=(ta.value.trim()?ta.value.trim()+"\n\n":"")+add;
  }
  paintFileRows(d.files||[],errors);
}
function paintFileRows(files,errors){
  const box=document.getElementById("ifiles");if(!box)return;
  box.innerHTML=(files||[]).map(f=>`<div class="ifile"><span class="itag">받았어요</span>
      <span>${esc(f.name)} · ${(f.text||"").length}자</span></div>`).join("")
    +(errors||[]).map(e=>`<div class="ifile bad"><span class="itag">못 읽었어요</span>
      <span>${esc(e.name)} · ${esc(e.why)}</span></div>`).join("");
}
/* 「갈라보기」 — 덩이를 **화면에만** 세운다. 문서엔 아직 아무것도 안 쓴다 (라운드 10 「나」) */
function splitDoc(){
  const err=document.getElementById("ierr"),box=document.getElementById("cands"),
        sum=document.getElementById("isum"),bar=document.getElementById("ibar");
  const r=sliceIntake(document.getElementById("doc").value);
  box.innerHTML="";sum.innerHTML="";bar.className="";bar.innerHTML="";INTAKE=null;
  if(r.error){err.style.display="block";err.textContent=r.error;return}
  err.style.display="none";
  /* `qi`·`cur`·`tries` 는 초안 큐의 것이다 (`makeFragments` 머리글) — 여기선 빈 채로 선다.
     `empty` 는 **모델이 「이야기 없다」고 판정한 덩이의 수**다 (2판) — 실패(`fail`)와 다른 수다.
     `dup` 은 **앞 덩이와 겹쳐 걸러낸 장수**, `dupOf` 는 덩이마다 그 수다 (`dropDupes`). */
  /* `fresh` = **방금 이 화면에서 저장소에 앉은 조각들** (#49 H3). 연습을 열 때 「방금 만든 것이
     걸릴 만한 질문」을 앞으로 당기는 데만 쓴다(`freshQids`) — 세션에만 산다. */
  /* `cloud` = **이번 뽑기가 사용자 백엔드로 가나** (#51). 사람이 켠 것을 `makeFragments` 가
     여기 굳힌다 — 도중에 토글을 만져도 한 판이 반씩 갈리지 않게. */
  INTAKE={items:r.items,ks:[],draft:{},n:0,got:0,fail:0,empty:0,banner:null,done:false,saved:0,
          qi:0,cur:null,tries:{},dup:0,dupOf:{},fresh:[],cloud:false};
  box.innerHTML=r.items.map((it,k)=>{
    /* ★ **칩 목록이 걷혔다** (#53 경계표 ②). 여기 있던 것: 기존 질문 전부를 칩으로 늘어놓고
       `chipFor` 가 고른 하나를 켜 둔 뒤 사람이 눌러 바꾸던 칸. 지금은 문항이 있으면
       **그것이 곧 물음**이고, 저장할 때 `questionForItem` 이 목록에 앉힌다(같은 물음이면 안 앉힌다).
       ⚠ 그래서 이 카드는 이제 **고르는 곳이 아니라 보여주는 곳**이다 — 「문항」 줄이 그 전부다. */
    return `<div class="cand" data-k="${k}">
      <div class="irow"><span class="ilbl">${it.q?"문항":it.h?"구획":"덩이"}</span><div class="cq">${
        it.q?esc(it.q):it.h?esc(it.h)+" · "+it.body.length+"자"
                      :(k+1)+"번째 · "+it.body.length+"자"}</div></div>
      <div class="irow"><span class="ilbl">제목</span><input class="cti" value="${esc(machineDraft(it.body).title)}"></div>
      ${it.q?`<div class="irow"><span class="ilbl">질문</span><div class="cqn">「이대로 저장」으로 넣으면 이 문항이 예상 질문 목록에 얹혀요 — 이미 같은 물음이 있으면 그것에 붙여요. 「답변 뽑기」로 넣은 답변에는 안 얹어요</div></div>`:""}
      <div class="cbody">${esc(it.body)}<span class="orig">원문</span></div>
      <div class="cacts"><button class="gbtn p ok">이대로 저장</button>
        <button class="gbtn drop">버리기</button></div></div>`}).join("");
  box.querySelectorAll(".cand").forEach(el=>{
    /* 버린 것은 어디에도 안 남는다 — 문서에 쓴 적이 없으니 지울 것도 없다 */
    el.querySelector(".drop").onclick=()=>el.remove();
    el.querySelector(".ok").onclick=()=>approve(el,r.items[+el.dataset.k]);
  });
  /* ⚠ **문항 벡터를 안 조른다** (#53). 예전엔 덩이마다 `embedDraft` 를 날려 칩을 뜻 자로
     갈아끼웠는데(`paintCandChip`), 갈아끼울 칩이 없어졌다. 왕복도 같이 사라진다. */
  /* ⚠ **개수를 「답변 N개」로 약속하지 않는다** (2판). 덩이 하나에서 이야기가 둘 나올 수도,
     하나도 안 나올 수도 있다 — 무엇이 한 이야기인가는 모델이 판정한다. */
  sum.innerHTML=`<div class="row"><button class="gbtn p" id="mk">답변 뽑기</button>
    <span class="foot">덩이 ${r.items.length} — 덩이마다 재사용할 이야기를 뽑아 바로 저장해요. 이야기가 없는 덩이는 버려요. 하나씩 고르려면 카드의 「이대로 저장」</span></div>`;
  document.getElementById("mk").onclick=makeFragments;
}
/* ★ [답변 만들기] (#40) — 남아 있는 덩이마다 Swift 에 초안을 조른다.
   ⚠ **한 번에 하나만 날린다.** 전에는 `ks.forEach(post)` 로 전부 동시에 발사했는데,
     FoundationModels 는 동시 요청을 `concurrentRequests` 로 **거절할 수 있다** — 그러면
     그 덩이가 조용히 기계 자르기로 강등되고, 사용자는 왜 어떤 것만 초안이 없는지 모른다.
     그래서 큐다: `pumpIntake` 가 하나 보내고, 답(`onFragmentDraft`)이 다음 하나를 부른다.
   ⚠ **브리지가 없으면 기다리지 않는다.** 브라우저 단독엔 답이 영영 안 오므로 그 자리에서
     기계 자르기로 간다 — 붙여넣기만으로 화면이 사는 길(`cue.html`)이 이 한 줄에 걸려 있다. */
function makeFragments(){
  if(!INTAKE||INTAKE.done)return;
  const ks=[...document.querySelectorAll("#cands .cand")]
    .filter(el=>!el.classList.contains("done")).map(el=>+el.dataset.k)
    .filter(k=>!isNaN(k)&&INTAKE.items[k]);
  if(!ks.length)return;
  INTAKE.ks=ks;INTAKE.n=ks.length;INTAKE.got=0;INTAKE.fail=0;INTAKE.draft={};INTAKE.banner=null;
  INTAKE.qi=0;INTAKE.cur=null;INTAKE.tries={};INTAKE.dup=0;INTAKE.dupOf={};INTAKE.fresh=[];
  /* 켠 것을 **여기서 굳힌다** (#51) — 이 판이 끝날 때까지 안 바뀐다.
     ⚠ **막는 자가 `cloudArmed` 로 바뀌었다** (2026-09-02, 리뷰 발견 ①). `CLOUD.ready` 로
       한 번 더 걸면 토글을 살려 둔 것이 여기서 도로 죽어 **켜 놓고 눌렀는데 아무 데도 안 나가는**
       모양이 된다 — 게이트가 둘이면 반드시 한쪽만 고쳐진다. */
  INTAKE.cloud=!!(cloudArmed(CLOUD.ready,CHOICE)&&CLOUD.on);
  const mk=document.getElementById("mk");if(mk)mk.disabled=true;
  paintIntake();
  if(!bridged()){fallbackIntake("이 창에는 초안 통로가 없어요 — 기계 자르기로 넣어요");return}
  pumpIntake();
}
/* 큐 한 칸을 민다 — **줄 서 있는 다음 덩이 하나**를 보낸다. 큐가 비면 아무것도 안 한다
   (끝맺음은 `onFragmentDraft` 가 `got>=n` 으로 판정한다 — 세는 자리가 둘이면 갈린다).
   ⚠ **꾸러미를 객체로 보낸다** (`embedDraft` 와 같은 모양). `JSON.stringify` 로 보내면
     Swift 쪽 `message.body as? [String: Any]` 가 실패해 **아무 답도 안 온다** —
     `WKWebViewWrapper.swift` 의 `case "draftFragment"` 가 진실원이다. */
/* ★ 한 창의 브리지 꾸러미 — **보내는 자리가 둘(첫 발사·재시도)이라 짓는 자리는 하나여야 한다.**
   갈리면 재시도만 `parts` 를 빠뜨리고, 그 창이 두 번째에 조용히 다른 지시문으로 돈다.
   ⚠ `parts`·`ask` 는 **해당되는 창에만** 싣는다 — 1·false 는 안 보낸다. Swift 쪽 기본값이
     그것이라 뜻이 같고, 안 보내는 쪽이 「이 칸은 없어도 되는 칸」이라는 계약을 꾸러미 자체로 말한다.
   ★ `ask` = **이 창이 면접 문항의 답인가** (#40 3판 조정). 700~1,000자 문항 답이 개조식으로
     무너지거나 결론 숫자를 남기고 잘리던 자리다 — 고치는 문구는 Swift 에 있고, 그 문구를 켤
     사실은 여기에만 있다(`kind`). ⚠ **`parts` 와 같이 실릴 일은 없다** — 문항 창은 안 붙는다. */
/* ★ `cloud` = **사람이 「더 좋은 정리」를 켰나** (#51). `parts`·`ask` 와 **같은 규율**이다:
   해당될 때만 싣고(꺼짐은 안 보낸다), Swift 쪽 기본값이 그것이라 뜻이 같다.
   ⚠ **창이 아니라 사람의 선택이라 인자로 온다.** `it` 에 얹으면 덩이마다 다를 수 있는 것처럼
     보이는데, 이 선택은 한 번 뽑는 동안 통째로 하나여야 한다(`INTAKE.cloud`). */
function draftPacket(id,it,cloud){
  const p={id:id,text:(it&&it.body)||""};
  if(((it&&it.parts)||1)>1)p.parts=it.parts;
  if(it&&it.kind==="q")p.ask=true;
  if(cloud)p.cloud=true;
  return p;
}
function pumpIntake(){
  if(!INTAKE||INTAKE.done)return;
  const k=INTAKE.ks[INTAKE.qi];
  if(k===undefined){INTAKE.cur=null;return}
  INTAKE.qi++;INTAKE.cur=k;INTAKE.tries[k]=1;
  post("draftFragment",draftPacket("i"+k,INTAKE.items[k],INTAKE.cloud));
}
/* 그 덩이를 **한 번 더** 보낸다 — 큐는 안 민다(같은 자리에서 다시 기다린다) */
function retryIntake(k){
  INTAKE.tries[k]=(INTAKE.tries[k]||1)+1;
  post("draftFragment",draftPacket("i"+k,INTAKE.items[k],INTAKE.cloud));
}
/* ★ 답 하나를 무엇으로 볼 것인가 — **순수 함수라 `node --test` 가 잠근다.**
   `tried` = 이 덩이를 지금까지 보낸 횟수(방금 온 답까지 포함).
   - `unavailable` — 이 기기에서 통째로 못 쓴다. 기다려봐야 같은 답이라 **전량 즉시 폴백**
   - `retry` — 이번만 실패했다(모델이 몰렸다·일시적). **딱 한 번 더** 보낸다
   - `fail` — 재시도까지 실패. 그 덩이만 기계 자르기로 물러선다
   ⚠ 상한을 2로 박는다: 재시도가 늘면 스캔 자소서 20덩이에서 대기가 배로 늘고,
     그 시간에 사용자가 창을 닫으면 아무것도 안 저장된다. */
const DRAFT_TRIES=2;
function draftVerdict(d,tried){
  if(d&&d.error==="unavailable")return "unavailable";
  if(d&&d.error)return (tried||1)<DRAFT_TRIES?"retry":"fail";
  return "ok";
}
/* ★ 답 하나에서 **이야기 목록**을 꺼낸다 — 순수 함수라 `node --test` 가 잠근다.
   2판 계약: `{id, drafts:[{title,body},…]}` (1판의 `{id,title,body}` 단수형을 대체했다.
   진실원 = `WKWebViewWrapper.swift` 의 `draftFragment` · `FragmentDrafter.Outcome`).
   ⚠ **빈 배열은 사고가 아니라 판정이다** — 「이 덩이엔 재사용할 이야기가 없다」.
     그래서 여기서 기계 자르기로 메우지 않는다. 메우면 2판이 없앤 쓰레기가 그대로 돌아온다.
   ⚠ 제목이 비면 본문 앞머리로 채운다 — 제목 없는 조각은 목록에서 못 고른다. 본문이 비면 버린다. */
/* ⚠ `how` 는 **어디서 왔나**를 카드에 적는 표식이다 (#51 이 갈래를 하나, #55 가 또 하나 더했다):
     「초안」 = 이 맥의 모델 · 「내 키」 = 사용자 백엔드 · 「구독」 = 이 맥에 깔린 공식 CLI ·
     「기계」 = 자르기(`cutDraft`).
     Swift 가 `via` 로 말해 준다 — 화면이 「켰으니 클라우드겠지」로 추측하면 **폴백이 일어난
     덩이에 거짓 표식**이 붙는다. 사다리가 세 층이 된 지금은 그 추측이 두 배로 틀린다.
   ⚠ **모르는 `via` 는 「초안」이다.** 옛 답·새 층 어느 쪽이든 표식이 없는 것이 거짓 표식보다 싸다. */
function draftList(d){
  const a=d&&d.drafts;
  if(!Array.isArray(a))return [];
  const how=d&&d.via==="cloud"?"내 키":(d&&d.via==="cli"?"구독":"초안");
  return a.map(x=>({title:String((x&&x.title)||"").trim(),body:String((x&&x.body)||"").trim()}))
          .filter(x=>x.title||x.body)
          .map(x=>({title:x.title||x.body.slice(0,34),body:x.body||x.title,how:how}))
          .slice(0,DRAFT_MAX);
}
/* 한 덩이에서 받는 이야기 상한. **`FragmentDrafter.maxDrafts` 와 같은 값이어야 한다** —
   갈리면 모델이 넷을 내고 화면이 셋만 받는 조용한 손실이 된다. */
const DRAFT_MAX=3;
/* ★ **겹침 문턱** — 두 초안이 같은 이야기인가 (#40 2판 조정).
   `실측 2026-08-30` 셀프 실기, 대기업 표준 자소서에서 나온 초안 11장의 55쌍을 전부 재 봤다:
   **진짜 중복 한 쌍이 0.545**(「교내 해커톤 2위」 × 「무엇 버릴지 먼저 정하는 습관」 — 같은 사건을
   두 장으로 쓴 것)이고, **나머지 54쌍은 전부 0.084 이하**다. 두 무리 사이가 6.5배 벌어져 있고
   0.35 는 그 사이다 — 위로도 아래로도 여유가 있다.
   ⚠ **선언한 값이지 실측이 아니다.** 잰 것은 저 두 무리의 자리고, 0.35 는 그 위에 그은 선이다. */
const DUP_SIM=0.35;
/* 초안 한 장을 견줄 글자 — **제목+본문**이다. 제목만 보면 같은 사건을 다른 이름으로 부른 두 장이
   안 걸리고, 본문만 보면 제목이 다른 것을 못 본다. */
const draftKey=g=>((g&&g.title)||"")+" "+((g&&g.body)||"");
/* ★ **겹치는 이야기를 걷어내는 안전망** — 저장 직전에 같은 사실이 두 장으로 앉는 것을 막는다.
   순수 함수라 `node --test` 가 잠근다.
   ⚠ **첫 방어선은 지시문이다**(`FragmentDrafter` 의 「같은 사실을 두 장에 반복하지 마라」).
     여기는 그것이 새는 자리를 받는 그물이지, 중복을 대신 판정하는 자가 아니다.
   ⚠ 자는 이미 있는 `sim`(bigram Jaccard)을 그대로 쓴다 — 여기서 새 자를 지으면 순위·색이
     쓰는 자와 갈리고, 그때부터 두 벌을 유지한다.
   ⚠ **한계**: Jaccard 는 대칭이라, 짧은 한 장이 훨씬 긴 한 장 **안에 통째로** 들어 있는 모양은
     분모가 커져 문턱 밑으로 떨어진다. 그 모양은 여기서 안 잡히고 지시문이 막는다.
   ⚠ **먼저 온 것이 남는다.** 덩이 순서가 곧 원문 순서라, 남는 쪽은 언제나 앞에 쓰인 이야기다. */
function dropDupes(gs,seen){
  const kept=(seen||[]).slice(),out=[];
  (gs||[]).forEach(g=>{
    const key=draftKey(g);
    if(kept.some(s=>sim(key,s)>=DUP_SIM))return;
    kept.push(key);out.push(g);
  });
  return out;
}
/* 이미 받아 둔 초안들의 자 — **덩이 번호 순서**로 모은다. 순서가 흔들리면 어느 쪽이 남는지가 흔들린다. */
const draftKeys=m=>Object.keys(m||{}).map(Number).sort((a,b)=>a-b)
  .reduce((a,k)=>a.concat(((m||{})[k]||[]).map(draftKey)),[]);
/* ★ 「이 글에서 이야기를 못 찾았다」인가 — 순수 함수. **전 덩이가 빈 배열일 때만** 참이다.
   ⚠ 한 덩이만 비는 것은 정상이다(목차·연락처). 그때 배너를 띄우면 매번 뜬다.
   ⚠ 실패해서 기계 자르기가 들어간 덩이는 비지 않았다 — 그래서 여기가 거짓이 된다. 맞다:
     그때 사람에게 물을 것은 「기계 자르기를 할까」가 아니라 이미 한 것의 보고다. */
function noStories(draft,ks){
  const list=ks||Object.keys(draft||{});
  if(!list.length)return false;
  return list.every(k=>!((draft||{})[k]||[]).length);
}
/* ★ 답 하나가 도착했다 (#40 2판). 성공 `{id,drafts:[…]}` / 실패 `{id,error,why}`.
   여기가 **큐의 심장**이다 — 한 덩이가 끝나야 다음 덩이가 나간다. */
function onFragmentDraft(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d||!INTAKE||INTAKE.done)return;
  const k=parseInt(String(d.id||"").slice(1),10);
  if(isNaN(k)||!INTAKE.items[k]||INTAKE.draft[k])return;
  /* ⚠ **지금 날아가 있는 그 덩이의 답만 받는다.** 늦게 온 옛 답을 그대로 세면 큐가 두 칸
     밀려 다시 동시 발사가 된다 — 이 한 줄이 직렬을 지킨다. */
  if(INTAKE.cur!==k)return;
  /* ★ 공통 지능이 **한 층도** 안 됐다 (#51 → #55). Swift 가 사다리를 끝까지 내려가
     이 맥의 모델로 만들어 왔다 — **사고가 아니라 알림**이라 `error` 가 아니고,
     그래서 판정(`draftVerdict`)을 안 건드린다.
     ⚠ 한 층이라도 성공하면 이 칸이 아예 안 온다 — Swift 가 그때 안 싣는다.
     ⚠ 남은 덩이는 **다시 안 보낸다.** 키가 틀렸으면 덩이마다 왕복을 한 번씩 더 물게 된다. */
  const cw=d.cloudWhy?"공통 지능을 못 썼어요 — "+d.cloudWhy:"";
  if(cw)INTAKE.cloud=false;
  const v=draftVerdict(d,INTAKE.tries[k]);
  if(v==="unavailable"){fallbackIntake([cw,d.why||"초안을 지금 못 만든다 — 기계 자르기로 넣는다"]
    .filter(Boolean).join(" · "));return}
  if(v==="retry"){retryIntake(k);return}
  if(v==="fail"){INTAKE.banner=INTAKE.banner||d.why||"초안 하나가 실패했다 — 그것만 기계 자르기로 넣는다";
    INTAKE.draft[k]=[cutDraft(k)];INTAKE.fail++}
  /* ⚠ **「이야기 없음」과 「앞과 겹침」을 한 수로 세지 않는다.** 둘의 처방이 다르다 —
     앞엣것은 사람이 「그래도 넣어라」를 누를 자리(`machineIntake`)고, 뒤엣것은 이미 넣은 것이 있다. */
  else{const raw=draftList(d),gs=dropDupes(raw,draftKeys(INTAKE.draft));
    INTAKE.draft[k]=gs;INTAKE.dupOf[k]=raw.length-gs.length;INTAKE.dup+=INTAKE.dupOf[k];
    if(!raw.length)INTAKE.empty++}
  /* 물러선 사유는 **첫 번째 것만** 띠에 세운다 — 덩이마다 같은 줄이 쌓일 자리다 */
  if(cw&&!INTAKE.banner)INTAKE.banner=cw+" · 이 맥 안에서 만들었어요";
  INTAKE.got++;INTAKE.cur=null;paintCardDraft(k);paintIntake();
  if(INTAKE.got>=INTAKE.n)commitIntake();else pumpIntake();
}
/* 기계 자르기 한 장 — **이제 강등이 아니라 물러설 자리**다. 모델이 못 돌 때(불가·실패)와
   사람이 「그래도 넣어라」를 누를 때만 나온다. 모델이 「이야기 없다」고 한 덩이에는 안 쓴다. */
const cutDraft=k=>Object.assign(machineDraft(INTAKE.items[k].body),{how:"기계"});
/* 초안 경로가 통째로 닫혔다 — 남은 덩이를 전부 기계 자르기로 채우고 그대로 저장까지 간다. */
function fallbackIntake(why){
  if(!INTAKE||INTAKE.done)return;
  /* 큐를 세운다 — 늦게 오는 답이 다음 덩이를 또 발사하지 않게 (`commitIntake` 의 `done` 과 짝) */
  INTAKE.cur=null;INTAKE.qi=INTAKE.ks.length;
  INTAKE.banner=why||null;
  INTAKE.ks.forEach(k=>{
    if(INTAKE.draft[k])return;
    INTAKE.draft[k]=[cutDraft(k)];INTAKE.got++;INTAKE.fail++;paintCardDraft(k)});
  paintIntake();commitIntake();
}
/* 뽑힌 이야기들을 그 덩이의 카드에 붙인다. **원문은 그대로 둔다** — 무엇에서 나온 것인지 대볼 수 있게.
   ⚠ 카드를 다시 짓지 않는다: 사람이 제목 칸을 고치는 중일 수 있다 (`paintCur` 과 같은 규율).
   ⚠ **0장도 그린다.** 아무것도 안 그리면 그 카드만 조용히 멈춘 것처럼 보인다. */
function paintCardDraft(k){
  const gs=INTAKE&&INTAKE.draft[k];if(!gs)return;
  const el=document.querySelector('#cands .cand[data-k="'+k+'"]');
  if(!el||el.querySelector(".dbox"))return;
  const d=document.createElement("div");d.className="dbox";
  d.innerHTML=gs.length?gs.map(g=>`<div class="dti">${esc(g.title)}<span class="dhow">${g.how}</span></div>`
      +(g.body?`<div class="dbo">${esc(g.body)}</div>`:"")).join("")
    :((INTAKE.dupOf||{})[k]
      ?`<div class="dti dnone">앞 덩이에 이미 있는 이야기라 안 넣어요<span class="dhow">겹침</span></div>`
      :`<div class="dti dnone">재사용할 이야기를 못 찾았어요 — 이 덩이는 안 넣어요<span class="dhow">판정</span></div>`);
  el.insertBefore(d,el.querySelector(".cacts"));
}
/* ★ 전부 왔다 — **여기서 처음으로** 문서가 바뀌고 저장된다 (기존 `saveDocument` 그대로).
   ⚠ `questionIds` 는 **빈 배열**이다 (#40). 연결은 저장 뒤 색인·제안(#33)이 맡는다 —
     여기서 기계가 질문을 걸면 사람이 안 고른 칩이 저장소에 앉는다.
   ⚠ 덩이 하나가 **여러 장**이 될 수 있다 (2판) — 세는 것은 덩이가 아니라 이야기다. */
function commitIntake(){
  if(!INTAKE||INTAKE.done)return;
  INTAKE.done=true;
  INTAKE.saved=saveDrafts(INTAKE.ks);
  if(INTAKE.saved)save();
  paintIntake();
}
/* 덩이 목록의 초안을 문서에 앉히고 **앉힌 장수**를 돌려준다. `commitIntake` 와 `machineIntake`
   가 같이 쓴다 — 앉히는 코드가 두 벌이면 한쪽이 조용히 낡는다. */
function saveDrafts(ks){
  const t=now();let n=0;
  (ks||[]).forEach(k=>{
    const gs=INTAKE.draft[k];if(!gs)return;
    gs.forEach(g=>{const p={id:uid("f"),title:g.title,body:g.body,
                            questionIds:[],createdAt:t,updatedAt:t};
      DOC.fragments.push(p);(INTAKE.fresh=INTAKE.fresh||[]).push(p);n++});
    const el=document.querySelector('#cands .cand[data-k="'+k+'"]');
    if(el){el.classList.add("done");const a=el.querySelector(".cacts");
      if(a)a.innerHTML=gs.length?`<span class="okmsg">저장됨 · ${gs.length}장</span>`
             :((INTAKE.dupOf||{})[k]?'<span class="okmsg">안 넣었어요 — 앞과 겹침</span>'
                                    :'<span class="okmsg">안 넣었어요 — 이야기 없음</span>')}});
  return n;
}
/* ★ 「이 글에서 이야기를 못 찾았다」의 **유일한 되돌릴 자리** (2판). 사람이 눌러야 돈다 —
   자동으로 강등하면 2판이 없앤 「기계적으로 문단 나누기」가 그대로 돌아온다.
   ⚠ **앞과 겹쳐 걸러낸 덩이는 여기 안 든다.** 그 덩이의 이야기는 이미 저장돼 있고, 기계 자르기로
     다시 넣으면 방금 막은 중복을 이 버튼이 도로 만든다. 이 버튼이 덮는 것은 「이야기 없음」뿐이다. */
function machineIntake(){
  if(!INTAKE||!INTAKE.done)return;
  const ks=INTAKE.ks.filter(k=>!(INTAKE.draft[k]||[]).length&&!(INTAKE.dupOf||{})[k]);
  if(!ks.length)return;
  ks.forEach(k=>{INTAKE.draft[k]=[cutDraft(k)];
    const el=document.querySelector('#cands .cand[data-k="'+k+'"]');
    if(el){const old=el.querySelector(".dbox");if(old)old.remove()}
    paintCardDraft(k)});
  const n=saveDrafts(ks);
  INTAKE.saved+=n;INTAKE.fail+=n;INTAKE.empty=0;INTAKE.banner=null;
  if(n)save();
  paintIntake();
}
/* 진행 띠 — 만드는 중엔 「3/7」, 끝나면 **연습으로 가는 문**. 사유가 있으면 그 위에 한 줄. */
function paintIntake(){
  const bar=document.getElementById("ibar");if(!bar)return;
  if(!INTAKE||!INTAKE.n){bar.className="";bar.innerHTML="";return}
  const b=INTAKE.banner?`<div>${esc(INTAKE.banner)}</div>`:"";
  if(!INTAKE.done){bar.className=INTAKE.banner?"warn":"";
    bar.innerHTML=b+`<div>이야기 뽑는 중 ${INTAKE.got}/${INTAKE.n}</div>`;return}
  /* ★ 전 덩이가 빈 배열 — **이 글엔 이야기가 없다**는 판정이다. 그때만 기계 자르기를 **권한다**
     (누르는 것은 사람이다). 한 덩이만 빈 것은 정상이라 여기 안 걸린다(`noStories`). */
  const none=noStories(INTAKE.draft,INTAKE.ks);
  bar.className=none||INTAKE.banner?"warn":"okd";
  bar.innerHTML=b+(none
      ?`<div>이 글에서 재사용할 이야기를 못 찾았어요 — 아무것도 안 넣었어요</div>`
      :`<div>내 답변 ${INTAKE.saved}장이 들어왔어요${
          INTAKE.fail?` · 그중 ${INTAKE.fail}장은 기계 자르기예요`:""}${
          INTAKE.empty?` · 덩이 ${INTAKE.empty}개는 이야기가 없어 버렸어요`:""}${
          INTAKE.dup?` · ${INTAKE.dup}장은 앞과 겹쳐 걸렀어요`:""}</div>`)
    +`<div class="row">${none?`<button class="gbtn p" id="mcut">그래도 기계 자르기로 넣기</button>`
        :`<button class="gbtn p" id="topr">바로 모의 질문 하나 받아보기</button>`}`
    +`<button class="gbtn" id="tostack">저장소로</button></div>`;
  /* ★ **time-to-magic** (#49 H3) — 넣자마자 그것이 무엇이 됐는지 한 문항으로 보여준다.
     ⚠ **흐름을 새로 안 만들었다.** 기존 `startPractice` 그대로고, 늘어난 것은 인자 하나(`first`)다 —
       방금 앉은 조각들이 걸릴 만한 질문을 앞으로 당긴다(`freshQids`). 셀 것이 없으면 빈 배열이라
       **예전 순서 그대로** 돈다(구멍부터). 「실패 시 기존 순서 그대로」가 그 뜻이다.
     ⚠ 여는 데 실패하면 모드를 안 바꾼다 — 질문이 0개면 빈 화면 대신 쌓기의 띠 한 줄이 말한다
       (`stackRender` 의 「연습」 버튼과 **같은 모양**이다). */
  const pr=document.getElementById("topr");
  if(pr)pr.onclick=()=>{
    if(!canGoMode("practice"))return;   /* 부작용 앞에 게이트 — `stackRender` 의 「연습」과 같다 (#66 리뷰 발견 ③) */
    const first=freshQids((INTAKE&&INTAKE.fresh)||[],DOC.questions);
    stackView="edit";
    if(startPractice(undefined,first))goMode("practice");else stackRender()};
  const mc=document.getElementById("mcut");
  if(mc)mc.onclick=machineIntake;
  document.getElementById("tostack").onclick=()=>{stackView="edit";stackRender()};
}
/* 승인 하나 = 조각 하나. **여기서 처음으로** 문서가 바뀌고 저장된다 (기존 `saveDocument` 그대로).
   ⚠ **칩을 화면에서 안 긁는다** (#53). 문항이 있으면 `questionForItem` 이 그것을 목록에 앉히고
     그 id 하나를 든다 — 「기존 질문 중 어느 것에 붙일까」를 고르던 칸이 걷혔다.
     문항이 없는 덩이(문단·구획)는 `questionIds` 가 **빈 배열**이다. 예전과 같고,
     그래도 면접 중 순위는 산다(`escore` 가 내용만 보므로). */
function approve(el,it){
  if(!it||el.classList.contains("done"))return;
  const title=el.querySelector(".cti").value.trim()||candTitle(it.body);
  /* 문항 = 그 답이 답하는 물음이다 **(#13 사용자 이야기 4)** — 목록에 얹고 그 하나를 든다 */
  const qid=it.q?questionForItem(it.q):null,ids=qid?[qid]:[];
  const t=now();
  const p={id:uid("f"),title:title,body:it.body,questionIds:ids,createdAt:t,updatedAt:t};
  DOC.fragments.push(p);
  /* 한 장씩 승인한 것도 「방금 만든 것」이다 (#49 H3) — 연습 첫 문항이 그것을 물게 */
  if(INTAKE)(INTAKE.fresh=INTAKE.fresh||[]).push(p);
  save();
  el.classList.add("done");
  el.querySelector(".cacts").innerHTML=`<span class="okmsg">저장됨 — 내 답변 ${DOC.fragments.length}</span>`;
}

/* ══ 프론트 설정 화면 (#61 C, 그릴 Q2) ═════════════════════════════════════════
   ★ **톱니가 여는 것이 여기다.** 네이티브 설정창이 들고 있던 것 중
     백엔드·키·모델·화면이 이리로 내려왔고, 거기 남는 것은 **단축키 녹화와 권한**뿐이다
     (그 함수는 이제 `showShortcutPanel` 이다 — #61 D 가 이름까지 줄였다)
     (그것들은 AppKit 이 아니면 못 만든다 — 맨 아래 한 줄이 그리로 보낸다).
   ★ **묶음이 둘이다** (박선호 2026-08-31 그릴 Q2): 「지능」 과 「화면」.
   값은 즉시 저장하되 제공자·서버 변경은 명시적으로 저장한다. 이전 키가 삭제되는 전환은 확인한다.
   ⚠ **키를 되읽지 않는다.** 화면이 아는 것은 「저장돼 있나」(`CLOUD.hasKey`)뿐이라, 빈 칸은
     「안 바꾼다」는 뜻이다. 지우는 길은 따로 한 줄로 둔다 — 안 그러면 되돌릴 수가 없다. ══ */

/* 공식 CLI 상태 — `detectCli` 의 답이 앉는 자리.
   `[{id,name,installed,loggedIn,install,login,model,reasoning,models,reasonings}]`
   — `install`·`login` 은 터미널 한 줄(#61 리뷰 발견 ④), 뒤 넷은 모델·추론 칸이다(2026-09-01).
   ★ **고를 수 있는 목록도 Swift 가 준다** (`models`·`reasonings` = `[{v,l}]`). 화면이 그 표를
     한 벌 더 들면 모델 이름이 바뀌는 날 두 곳이 조용히 갈린다 — 같은 이유로 터미널 두 줄이
     이미 Swift 로 갔다. `reasonings` 가 비면 그 줄을 **안 그린다**(claude 층엔 그 깃발이 없다). */
let CLIST=[];
/* ★ **두뇌 선택** (박선호 2026-09-01: *"사디리를 해당순서로 강제하는게 아니라 구독제가 있으면
   구독제로 쓰는거고 api키가 있으면 api로 꼳아서 쓰는거고, … 유저가 원하는 모델을 물려서 쓸수
   있게 하는거지"*). `detectCli` 의 답에 같이 온다:
   - `CHOICE`  = 지금 고른 것 (`auto`·`claude`·`codex`·`key`). **정본은 Swift 의 `UserDefaults`**
   - `CHOICES` = 고를 수 있는 넷과 이름표 `[{v,l}]` — **이름표도 Swift 가 준다**(`DrafterChoice.label`).
     화면이 그 표를 한 벌 더 들면 이름이 바뀌는 날 두 곳이 갈린다(모델 목록과 같은 자리)
   ⚠ **키 층 요약은 이 통로로 안 온다** (2026-09-02, 리뷰 H3). 그것과 「자동은 지금 어디로」는
     `setCloudDrafter` 가 든다(`CLOUD.key`·`CLOUD.provider`·`CLOUD.autoLabel`) — 집이 둘이면
     키를 저장한 직후 이 목록만 낡는다. ⚠ **키 값도 앞자리도 어느 통로로도 안 온다.**
   ★ **`CHOICE` 는 통로가 둘이다** (2026-09-02, 리뷰 발견 ⑥): `detectCli`(설정 화면을 열 때) 와
     `setCloudDrafter`(창이 뜰 때·설정을 저장할 때). **집은 그래도 이 칸 하나**고 정본은 양쪽 다
     Swift 의 `UserDefaults` 다. 둘째 통로가 필요한 이유 = 받기 화면은 설정을 안 열어도 이 값을
     읽는다(`cloudArmed`) — 첫째 통로만 있으면 그 화면에서 명시 선택이 조용히 `auto` 가 된다. */
let CHOICE="auto",CHOICES=[];
/* ★ 모델 이름 목록 — `loadModels` 의 답이 앉는 자리 (#61 리뷰 발견 ②).
   ⚠ **고르는 칸이 아니라 거드는 칸이다.** 모델 칸은 계속 자유 입력이고(`<input>`), 이 목록은
     `<datalist>` 로 붙는다 — 목록을 못 받아도(키가 없다·주소가 틀렸다·오프라인) 사람이
     이름을 쳐 넣는 길이 안 막힌다. 드롭다운으로 바꾸면 **못 받은 날 설정이 잠긴다.**
   ⚠ **세션에만 산다.** 저장되는 것은 고른 이름 하나(`saveBackend` 의 `model`)뿐이다. */
let MODELS=[];
/* 모델 목록의 **상태** — `[]` 하나로는 성공한 빈 목록과 네트워크 실패를 구분할 수 없다.
   ⚠ 모델 칸은 계속 자유 입력이다. 목록은 도움말이고, 상태 문구가 떠도 사람이 직접 모델을
   입력해 저장할 수 있어야 한다. */
let MODEL_STATUS="idle",MODEL_MESSAGE="",MODEL_REQUEST=0;
function onModelsState(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d||!d.state)return;
  if(d.requestID!==undefined&&Number(d.requestID)!==MODEL_REQUEST)return;
  MODEL_STATUS=String(d.state);
  MODEL_MESSAGE=String(d.message||"");
  paintModelList();
}
/* 저장 뒤 한 줄. **세션에만 산다** */
let setMsg="";
function onCliStatus(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d||!d.cli)return;
  CLIST=d.cli;
  /* ⚠ **없는 칸은 안 덮는다.** 옛 답(두뇌 선택이 없던 판)이 오면 지금 고른 것이 `auto` 로
     되돌아간 것처럼 보인다 — 화면이 저장소와 다른 말을 하는 자리다. */
  if(d.choice)CHOICE=String(d.choice);
  if(Array.isArray(d.choices))CHOICES=d.choices;
  paintBrain();
  paintCliCards();
}
/* ★ 두뇌 하나의 지금 상태 한 줄. **순수 함수라 `node --test` 가 잠근다.**
   재료는 방금 온 회신뿐이다(`CLIST` = `onCliStatus` · `CLOUD` = `setCloudDrafter`) —
   화면이 자기 판정을 따로 들지 않는다.
   ★ **「자동」 줄은 이름표를 그리기만 한다** (2026-09-01 → 2026-09-02 리뷰 P1·H2). 전엔 여기
     여기 있던 `autoWho()` 가 사다리를 **한 벌 더 유도**했고 Swift 와 갈려 있었다 — 저쪽은 「깔린 첫
     CLI」, 이쪽은 「로그인된 첫 CLI」. 게다가 `"API 키(…)"` 를 손으로 박아 이름표의 집이 둘이
     됐다. 지금 오는 것은 `DrafterChoice.autoLabel` 이 지은 글자 하나고, 화면이 더하는 것은
     **문장 껍데기뿐**이다.
   ⚠ 조사를 안 만든다 — 이름 뒤에 붙는 것은 「쪽으로」 하나다(로/으로가 없다). */
function brainNote(v){
  if(v==="auto")return CLOUD.autoLabel
    ?`현재 ${CLOUD.autoLabel} 사용`:"외부 AI 설정 없음";
  /* ⚠ **갈래가 셋이다** (2026-09-02, 리뷰 H3 을 고치다 드러난 자리). `key`(층이 준비됐나)와
     `hasKey`(키가 저장돼 있나)를 가르고 나니, **키는 저장했는데 모델을 안 고른 사람**에게
     이 줄이 「키가 없어요」라 하고 바로 위 키 칸은 「저장돼 있어요」라 하는 **한 화면 안의
     자기모순**이 생겼다. 사실 둘을 다 받았으니 말도 셋이어야 한다.
     ⚠ 사실은 Swift 것이고(참/거짓·제공자 이름) **문장은 화면 것이다** — 「로그인이 필요해요」·
       「안 깔려 있어요」와 같은 자리다. 이름표만 Swift 에서 온다. */
  if(v==="key")return CLOUD.key?`설정됨 · ${CLOUD.provider}`
    :(CLOUD.type==="ollama"?"Ollama 설정 필요":CLOUD.hasKey?"키는 있는데 설정이 덜 됐어요":"키가 없어요");
  const c=CLIST.find(x=>x&&x.id===v);
  if(!c)return "못 찾았어요";
  return c.loggedIn?"연결됨":(c.installed?"로그인이 필요해요":"안 깔려 있어요");
}
/* 두뇌 넷을 그린다.
   ⚠ **「제자리」가 아니다** (2026-09-02 정정, 리뷰 J1). 이 칸은 `innerHTML` 을 **통째로 갈아
     끼운다** — 라디오 넷이 새 요소가 되고 `onchange` 도 다시 건다. 제자리인 것은 **화면**이지
     (`render()` 를 다시 안 부른다) 요소가 아니다. 그래서 **이 칸엔 사람이 치는 입력을 두면
     안 된다**: 고르는 칸뿐이라 지금은 안전하고, 글자 칸을 더하는 날 이 규율이 깨진다
     (키 칸이 `paintBackendKey` 로 따로 사는 이유가 그것이다).
   ⚠ **넷을 늘 다 그린다.** 안 되는 것을 감추면 「왜 Codex 가 안 보이지」가 되고, 그 답이
     화면 어디에도 없다. 대신 각 줄이 자기 상태를 말한다.
   ⚠ **고른 즉시 저장한다** — 저장 버튼이 없다(이 화면의 규율). */
function paintBrain(){
  const box=document.getElementById("setbrain");if(!box)return;
  if(!CHOICES.length){
    box.innerHTML=`<div class="mkcard"><div class="mkstat"><span class="mkdot"></span><span>연결 상태 확인 중</span></div></div>`;
    return;
  }
  box.innerHTML=`<div class="mkcard">`+CHOICES.map(o=>
    `<div class="mkrow"><label class="ctog"><input type="radio" name="brain" class="setbr"`
    +` value="${esc(o.v)}"${o.v===CHOICE?" checked":""}><span>${esc(o.l)}</span></label>`
    +`<span style="flex:1"></span><span class="mkfine">${esc(brainNote(o.v))}</span></div>`).join("")
    +`</div>`;
  box.querySelectorAll(".setbr").forEach(el=>el.onchange=()=>{
    CHOICE=el.value;post("saveCliConfig",{choice:CHOICE});paintBrain()});
}
/* ⚠ **키가 안 온다.** 오는 것은 「키가 있나 · 종류 · 모델」뿐이다(Swift 쪽 `saveBackend`).
   ⚠ **「저장 못 했어요」 갈래를 걷었다** (#61 리뷰 발견 ⑦). 저장은 `UserDefaults.set` 세 줄이라
     **실패를 낼 통로가 없고**, Swift 는 그래서 언제나 `ok:true` 를 실어 보냈다 —
     화면에 죽은 갈래를 남겨 두면 다음 세션이 그것을 「실패를 다루고 있다」로 읽는다.
     ★ **다시 열 조건**: 저장이 실패할 수 있는 자리(파일·키체인·원격)로 옮겨가면 그때
       Swift 가 실결과를 싣고 이 갈래가 돌아온다. */
/* ★ **방금 무엇을 시켰나** (#65 ①②). 회신에는 결과(`hasKey`)만 오고 「지우려던 것인가」가
   안 온다 — 그런데 사람이 읽어야 하는 말은 그 둘이 다르다. 통로를 늘리는 대신 화면이
   방금 낸 뜻을 여기 한 칸에 든다. `push` 가 세우고 회신이 걷는다. */
let setPend=null;
/* ⚠ **말은 한 곳에서 난다** (#66 리뷰 발견 ⑦). 이 한 줄은 두 번 뜬다 — 보낼 때(`push`) 한 번,
   회신이 올 때(`onBackendSaved`) 한 번. 글자를 두 집에 두면 한쪽만 고쳐져 **보낼 때와 돌아올 때
   다른 말**이 뜬다. 지우기와 저장이 같은 통로라 이 갈림 자체는 안 없어진다 (#65 ②). */
const pendMsg=()=>setPend==="clear"?"키를 지웠어요":"저장했어요";
function onBackendSaved(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d)return;
  CLOUD.hasKey=!!d.hasKey;
  setMsg=pendMsg();
  setPend=null;
  paintSetMsg();
  /* ★ **키 줄을 회신대로 다시 그린다** (#65 ①②). 전엔 이 줄이 없어서, 키를 지워도
     「저장돼 있어요」 placeholder 와 「키 지우기」 링크가 그대로 남았다 — 화면이 저장소와
     다른 말을 하는 자리다. 정본은 `CLOUD.hasKey` 이고 그것을 정하는 것은 Swift 의 회신이다.
     ⚠ **`CLOUD.key` 가 아니다** (2026-09-02, 리뷰 H3). 그 칸은 「키 층이 준비됐나」라 주소·모델
       까지 보고, 그것으로 이 줄을 그리면 모델을 안 고른 사람에게 「없어요」라고 거짓말한다. */
  paintBackendKey();
}
function paintSetMsg(){
  const el=document.getElementById("setmsg");
  if(el)el.textContent=setMsg;
}
/* 키 줄만 **제자리에서** 고쳐 쓴다 — 화면을 새로 지으면 사람이 치던 주소·모델 칸이 날아간다
   (`paintCliCards`·`paintCur` 와 같은 규율).
   ⚠ **「키 지우기」는 언제나 그려 두고 여기서 감춘다.** 있다 없다 하는 요소로 두면 지운 뒤에
     다시 끼우는 코드가 필요하고, 그 코드가 곧 두 번째 그리는 자리가 된다. */
function paintBackendKey(){
  const key=document.getElementById("setkey"),clr=document.getElementById("setclr");
  if(key)key.placeholder=CLOUD.hasKey?"저장돼 있어요 — 바꿀 때만 입력하세요":"없어요";
  if(clr)clr.style.display=CLOUD.hasKey?"":"none";
}
/* ★ Swift → JS. 모델 이름들이 도착했다 (`fetchModels` 의 답, #61 리뷰 발견 ②).
   전엔 **빈 스텁**이라 통로가 살아 있는 채로 답이 버려졌다 — Swift 는 `loadModels` 를 계속
   등록·처리하고 있었고(`WKWebViewWrapper` 낱말표 · `case "loadModels"`), 끊긴 것은 화면뿐이다.
   ⚠ **둘째 인자(제공자 종류)는 안 본다.** 고른 백엔드가 무엇이든 Swift 가 그 백엔드에 물어서
     답하므로, 여기서 한 번 더 가리면 자가 둘이 된다.
   ⚠ **칸을 안 덮어쓴다.** 사람이 치고 있던 글자를 목록이 밀어내면 안 된다 — 붙는 것은 목록뿐이다. */
function receiveModels(names,type,requestID){
  if(requestID!==undefined&&Number(requestID)!==MODEL_REQUEST)return;
  MODELS=Array.isArray(names)?names.filter(n=>typeof n==="string"&&n):[];
  MODEL_STATUS="ready";MODEL_MESSAGE="";
  paintModelList();
}
function paintModelList(){
  const dl=document.getElementById("setmodels");if(!dl)return;
  dl.innerHTML=MODELS.map(n=>`<option value="${esc(n)}"></option>`).join("");
  const msg=document.getElementById("setmodelstatus");if(!msg)return;
  if(MODEL_STATUS==="loading")msg.textContent="모델 목록을 불러오는 중이에요 — 이름은 직접 입력할 수 있어요";
  else if(MODEL_STATUS==="error")msg.textContent=(MODEL_MESSAGE||"모델 목록을 불러오지 못했어요")+" — 모델 이름을 직접 입력해 주세요";
  else if(MODEL_STATUS==="ready"&&!MODELS.length)msg.textContent="모델 목록이 없어요 — 모델 이름을 직접 입력해 주세요";
  else msg.textContent="";
}
function requestModelList(){
  MODEL_REQUEST++;MODEL_STATUS="loading";MODEL_MESSAGE="";paintModelList();
  post("loadModels",{requestID:MODEL_REQUEST});
}
/* 연결 카드 — **제자리에서만 고쳐 쓴다.** 화면을 새로 지으면 사람이 치고 있던 키 칸이 날아간다
   (`paintCur`·`paintCloudRow` 와 같은 규율). */
function paintCliCards(){
  const box=document.getElementById("setcli");if(!box)return;
  box.innerHTML=CLIST.length?CLIST.map(cliCard).join("")
    :`<div class="mkcard"><div class="mkstat"><span class="mkdot"></span><span>공식 CLI 를 찾는 중이에요</span></div></div>`;
  /* 카드를 누르면 **다시 잰다** — 「다시 확인」 버튼을 따로 안 만든다(미니멀 원칙).
     터미널에서 로그인하고 돌아와 한 번 누르면 그 자리에서 바뀐다. */
  box.querySelectorAll(".setcli").forEach(el=>el.onclick=()=>post("detectCli"));
  box.querySelectorAll(".setcp").forEach(el=>el.onclick=ev=>{ev.stopPropagation();
    mkCopy(el.dataset.cmd,"복사했어요 — 터미널에 붙여넣고 이 카드를 다시 눌러 주세요",el.dataset.v)});
  /* ★ 모델·추론 칸 (2026-09-01). ⚠ **카드 클릭(=다시 재기)이 위에 걸려 있다** — 칸을 만질 때
     그것이 같이 터지면 고르는 도중에 카드가 통째로 새로 그려져 **고른 것이 사라진다.**
     그래서 누를 때도 바뀔 때도 `stopPropagation` 이다(`.setcp` 와 같은 규율). */
  box.querySelectorAll(".setcm").forEach(el=>{
    el.onclick=ev=>ev.stopPropagation();
    el.onchange=ev=>{ev.stopPropagation();saveCliCfg(el.dataset.v,el.dataset.k,el.value)};
  });
}
/* 고치는 즉시 저장한다 — 저장 버튼이 없다(백엔드 칸과 같은 규율, 미니멀 원칙).
   ★ **꾸러미에 둘 다 싣는다.** 방금 바꾼 한 칸만 보내면 Swift 가 「안 온 칸 = 안 바꾼다」와
     「안 온 칸 = 비운다」 중 하나를 골라야 하고, 그 판정이 두 곳에 서면 갈린다.
     무엇을 받을지는 **벤더 표가 안다** — 추론 칸이 없는 벤더는 그 값을 통째로 버린다.
   ⚠ **여기 값을 CLIST 에 같이 앉힌다.** 안 앉히면 다음 그리기가 옛 값을 되살려,
     고른 것이 화면에서 되돌아가는 것처럼 보인다(회신이 없어 새로 오지도 않는다). */
function saveCliCfg(id,kind,value){
  const v=CLIST.find(x=>x.id===id);if(!v)return;
  if(kind==="model")v.model=value;else v.reasoning=value;
  post("saveCliConfig",{vendor:id,model:v.model||"",reasoning:v.reasoning||""});
}
/* 터미널 한 줄 — **정본은 Swift 다** (#61 리뷰 발견 ④). 벤더 표(`CliDrafter.Vendor`)가
   `install`·`login` 글자를 들고 `detectCli` 의 답(`onCliStatus`)에 실어 보낸다.
   여기 한 벌 더 두면 벤더가 늘거나 명령이 바뀔 때 **두 곳이 조용히 갈린다.**
   ⚠ **비밀값이 아니다.** 키·토큰이 앉을 자리를 여기 만들지 않는다(memory 규율).
   ⚠ **한 줄 자리(`mkmsg`)가 벤더마다 따로다** (#61 리뷰 발견 ①). id 를 공유하면
     `getElementById` 가 언제나 **첫 카드**를 집어, codex 를 눌렀는데 claude 카드 밑에
     「복사했어요」가 뜬다 — 실측으로 걸린 자리다. */
function cliCard(v){
  const head=(dot,text)=>`<div class="mkstat"><span class="mkdot ${dot}"></span>`
    +`<span>${esc(v.name)}</span><span style="flex:1"></span><span class="mkfine">${esc(text)}</span></div>`;
  if(v.loggedIn)return `<div class="mkcard setcli" title="눌러서 다시 확인">${head("on","연결됨")}
    ${cliTune(v)}</div>`;
  const line=(v.installed?v.login:v.install)||v.id;
  const why=v.installed?"로그인이 필요해요":"안 깔려 있어요";
  return `<div class="mkcard setcli" title="눌러서 다시 확인">${head(v.installed?"mid":"",why)}
    <div class="mkrow"><code class="mkcode">${esc(line)}</code>
      <button class="gbtn setcp" data-cmd="${esc(line)}" data-v="${esc(v.id)}">명령 복사</button>
      <span class="mkfine" id="mkmsg-${esc(v.id)}"></span></div>${cliTune(v)}</div>`;
}
/* 모델·추론 칸 (박선호 2026-09-01: *"모델 선택이나 추론 설정도 가능한가?"*).
   ⚠ **안 깔린 벤더엔 안 그린다.** 없는 CLI 의 모델을 고르는 칸은 고를 값이 있어도 뜻이 없고,
     그 카드가 지금 말하는 것은 「깔아 주세요」 하나여야 한다.
   ⚠ **설명 문구를 안 단다**(미니멀 원칙) — 라벨 두 글자와 값이 전부다.
   ⚠ **목록이 비면 그 줄이 통째로 없다** — claude 층엔 추론 깃발이 없다(`CliDrafter` 벤더 표). */
function cliTune(v){
  if(!v.installed)return "";
  return cliSel(v,"model","모델",v.models,v.model)+cliSel(v,"reasoning","추론",v.reasonings,v.reasoning);
}
function cliSel(v,kind,label,list,cur){
  if(!Array.isArray(list)||!list.length)return "";
  return `<div class="mkrow"><span class="setlbl">${label}</span>
    <span class="setsel"><select class="setfld setcm" data-v="${esc(v.id)}" data-k="${kind}">`
    +list.map(o=>`<option value="${esc(o.v)}"${o.v===cur?" selected":""}>${esc(o.l)}</option>`).join("")
    +`</select></span></div>`;
}
/* 설치·로그인 명령처럼 비밀값이 아닌 텍스트만 복사한다. WebView에 브라우저 클립보드가
   없으면 네이티브 브리지를 사용하고, 두 경로 모두 실패하면 직접 복사할 수 있게 안내한다. */
function mkCopy(text,okMsg,vid){
  const m=document.getElementById("mkmsg-"+String(vid||""));
  const fail=()=>{if(m)m.textContent="이 창에선 복사가 안 돼요 — 위 명령을 직접 골라 복사해 주세요"};
  const native=()=>bridged()
    ?post("copyText",{text:String(text||""),id:String(vid||"")})
    :fail();
  try{
    const p=typeof navigator!=="undefined"&&navigator.clipboard
      &&navigator.clipboard.writeText&&navigator.clipboard.writeText(text);
    if(!p||!p.then)return native();
    p.then(()=>{if(m)m.textContent=okMsg},native);
  }catch(e){native()}
}
function onNativeCopyText(ok,vid){
  const m=document.getElementById("mkmsg-"+String(vid||""));
  if(m)m.textContent=ok?"복사했어요":"이 창에선 복사가 안 돼요 — 위 명령을 직접 골라 복사해 주세요";
}
/* ══ 시스템 한 벌 — 단축키 둘 · 권한 둘 · 볼트 (2026-08-31 설정 통합) ══════════════
   ★ **네이티브 미니 패널이 죽고 그 셋이 여기로 왔다** (박선호: *"단축키 설정이나 그런것들도
     그냥 설정창 하나로 다 통합시키고"*). 설정 창이 이제 하나다.
   ★ **정본은 Swift 다.** 화면은 `probeSystem` 으로 물어보고 `setSystemState` 로 받는다 —
     여기 값을 화면이 스스로 고치지 않는다(고치면 「저장은 됐는데 안 먹는」 단축키가 생긴다).
   ⚠ 브라우저 단독에서는 답이 안 온다. 그때 보이는 것은 **앱의 기본값**이고, 아래 한 줄이
     「여기서는 안 걸린다」를 말한다 — 조용히 진짜인 척하지 않는다(`bridged()` 규율). */
let SYS={keys:{toggle:{k:{cmd:true,opt:true,ctrl:false,shift:false,key:"m"},on:false},
                capture:{k:{cmd:true,opt:false,ctrl:false,shift:true,key:""},on:false}},
         mic:"ask",screen:"off",vault:"",failed:null};
/* 지금 녹화 중인 자리(`"toggle"`·`"capture"`) 와 아직 글자가 안 온 미리보기 */
let RECSLOT=null,RECMOD=null;
/* ★ 방금 **이미 쓰이는 조합**을 눌렀다고 말해야 하는 자리 (#65 ⑧). `SYS.failed`(Swift 가 못
   걸었다)와 **다른 사실**이라 칸을 따로 든다 — 한 칸에 담으면 「다른 앱이 쓰고 있을 수
   있어요」라는, 우리가 방금 안 사실과 다른 말이 나간다. */
let RECCLASH=null;
/* 두 조합이 같은가 — **글자까지 같아야 같다.** 모디파이어만 같은 것은 다른 조합이다.
   ⚠ 글자가 빈 값(`""`)은 어느 것과도 안 같다 — 그건 아직 조합이 아니다(`slotLabel` 머리글). */
const sameKey=(a,b)=>!!(a&&b&&a.key&&a.key===b.key
  &&!!a.cmd===!!b.cmd&&!!a.opt===!!b.opt&&!!a.ctrl===!!b.ctrl&&!!a.shift===!!b.shift);
const KEYSLOTS=["toggle","capture"];
/* ★ **조합을 글자로 바꾸는 자리는 여기 하나다.** Swift 쪽 `displayString` 을 걷은 이유가
   이것이다 — 녹화 중에는 아직 저장 안 된 조합을 그려야 해서 화면에 자가 반드시 있어야 하고,
   그러면 Swift 쪽 것은 **두 번째 자**가 된다. */
function keyLabel(k){
  if(!k)return "—";
  let s="";
  if(k.ctrl)s+="⌃";if(k.opt)s+="⌥";if(k.shift)s+="⇧";if(k.cmd)s+="⌘";
  s+=(k.key||"").toUpperCase();
  return s||"—";
}
function setSystemState(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d)return;
  if(d.keys)SYS.keys=d.keys;
  SYS.mic=d.mic||"off";SYS.screen=d.screen||"off";
  SYS.vault=d.vault||"";SYS.failed=d.failed||null;
  /* ★ 볼트 고르기의 **답이 이 길로 온다** (#80 1 — `openSystem what=vault` 의 완료 핸들러가
     `sendSystemState()` 를 부른다). 그래서 여기가 그 줄을 푸는 자리다. */
  pickFree(PICKING,"vault");
  paintPicking("connectvault","vault");
  paintSys();
}
/* 단축키 두 줄 + 권한 두 줄 + 볼트 한 줄. **제자리에서만 고쳐 쓴다** — 화면을 새로 지으면
   같은 카드 안에서 사람이 치고 있던 키 칸(지능 묶음)이 날아간다(`paintCliCards` 규율). */
/* 그 자리에 앉아 있는 조합을 글자로. ★ **글자 키가 없으면 「없음」이다** (#65 P3).
   `keyLabel` 은 모디파이어만 들어도 「⇧⌘」을 내는데, 그건 **녹화 중 미리보기**를 위해서다 —
   앉은 값에 그대로 쓰면 캡처 기본값(⇧⌘ · 글자 없음)이 **배정된 것처럼** 읽힌다.
   ⚠ Swift 쪽 기본값은 안 바꾼다. 거짓말을 한 것은 저장된 값이 아니라 그것을 적던 화면이다. */
const slotLabel=e=>{const k=(e||{}).k;return (k&&k.key)?keyLabel(k):"없음"};
function paintSys(){
  for(const slot of KEYSLOTS){
    const btn=document.getElementById("key-"+slot),msg=document.getElementById("keymsg-"+slot);
    if(!btn)continue;
    const rec=RECSLOT===slot;
    btn.className="gbtn setkey"+(rec?" rec":"");
    btn.textContent=rec?(keyLabel(RECMOD)==="—"?"누르세요…":keyLabel(RECMOD)+"…"):slotLabel(SYS.keys[slot]);
    if(!msg)continue;
    if(rec)msg.textContent="Esc 로 취소";
    /* 우리가 **방금 안 사실**이 Swift 의 옛 실패보다 먼저다 — 같은 조합이 옆 자리에 있다 (#65 ⑧) */
    else if(RECCLASH===slot)msg.textContent="같은 조합이 다른 자리에 있어요 — 다른 조합을 눌러 주세요";
    else if(SYS.failed===slot)msg.textContent="그 조합은 못 걸어요 — 다른 앱이 쓰고 있을 수 있어요";
    else if((SYS.keys[slot]||{}).on)msg.textContent="걸렸어요";
    else if(!bridged())msg.textContent="이 창에서는 안 걸려요";
    /* ★ **왜 안 걸렸는지를 갈라 말한다** (#65 ⑤). 전 판은 글자 키가 **이미 있는** 조합에도
       「글자 키 하나가 필요해요」라고 했다 — 사람이 고칠 수 없는 것을 고치라고 시키는 자리다. */
    else msg.textContent=((SYS.keys[slot]||{}).k||{}).key
      ?"안 걸렸어요 — 다른 앱이 쓰고 있을 수 있어요"
      :"안 걸렸어요 — 글자 키 하나가 필요해요";
  }
  const P={on:["on","켜짐"],ask:["mid","아직 안 물었어요"],off:["","꺼짐"]};
  for(const [id,val] of [["mic",SYS.mic],["screen",SYS.screen]]){
    const dot=document.getElementById("pdot-"+id),txt=document.getElementById("ptxt-"+id);
    const p=P[val]||P.off;
    if(dot)dot.className="mkdot "+p[0];
    if(txt)txt.textContent=p[1];
  }
  const vp=document.getElementById("setvault");
  if(vp)vp.textContent=SYS.vault||"앱에서만 보여요";
  const heading=document.getElementById("vaultheading");if(heading&&SYS.vault)heading.textContent=SYS.vault.split("/").filter(Boolean).pop();
  paintPicking("vaultmenu","vault");   /* 제자리 고쳐쓰기라 잠금도 여기서 따라온다 (#80 1) */
}
/* ★ 키 조합을 받아 적는 자리. **`e.code` 로 읽는다** — `e.key` 는 ⌥ 를 누르면 다른 글자가
   되고(맥 옵션 조판), 한글 자판에서도 갈린다. `code` 는 **자판의 그 자리**라 안 흔들린다.
   ⚠ **Carbon 이 아는 것만 받는다**: 글자 하나(A–Z)와 숫자 하나(0–9). 그 밖은 조용히 안 받고
     아래 한 줄이 무엇이 필요한지 말한다.
   ⚠ **못 받는 조합이 있다.** ⌘Q·⌘W·⌘X·⌘C·⌘V·⌘A 는 이 앱의 메뉴가 키 등가로 먼저 가져가고,
     ⌘Tab·⌘Space 는 시스템이 가져간다 — keydown 이 **여기까지 안 온다.** 감지할 방법이
     없어서 「눌렀는데 아무 일도 안 남」이 되는데, 그것을 침묵으로 두지 않으려고
     녹화 칸 밑에 그 목록을 적어 둔다. */
function recKey(e){
  if(!RECSLOT)return;
  e.preventDefault();e.stopPropagation();
  if(e.key==="Escape"){RECSLOT=null;RECMOD=null;RECCLASH=null;paintSys();return}
  const m={cmd:!!e.metaKey,opt:!!e.altKey,ctrl:!!e.ctrlKey,shift:!!e.shiftKey,key:""};
  const code=e.code||"";
  if(/^Key[A-Z]$/.test(code))m.key=code.slice(3).toLowerCase();
  else if(/^Digit[0-9]$/.test(code))m.key=code.slice(5);
  if(!m.key){RECMOD=m;paintSys();return}       /* 아직 모디파이어뿐 — 미리보기만 */
  /* ★ **⇧ 단독은 모디파이어로 안 센다** (#65 ④). ⇧A 는 그냥 대문자 A 라, 그것을 전역 핫키로
     걸면 **어느 앱에서도 대문자를 못 친다.** 맨 글자 하나를 못 거는 것과 같은 이유이고,
     Swift 쪽 `RecordingShortcut.fromJS` 가 같은 판정을 든다 — 화면만 좁히면 통과한 조합이
     저쪽에서 조용히 `nil` 이 되어 「받았는데 안 걸리는」 조합이 생긴다. */
  if(!(m.cmd||m.opt||m.ctrl)){RECMOD=m;paintSys();return}
  const slot=RECSLOT;
  /* ★ **같은 조합을 두 자리에 못 앉힌다** (#65 ⑧). 앉히면 Carbon 이 뒤엣것을 거절하거나
     한 조합이 두 일을 하려 들고, 화면에는 둘 다 걸린 것처럼 적힌다.
     ⚠ **막는 자리가 화면인 이유**: Swift 는 자리마다 따로 걸어서 「옆 자리가 이미 쓴다」를
       사고가 아니라 **아무 일도 안 남**으로 낸다 — 그 침묵을 사람이 읽을 방법이 없다.
     ⚠ 녹화를 접고 그 자리에 사유를 세운다. 아무것도 저장하지 않는다. */
  const clash=KEYSLOTS.some(s=>s!==slot&&sameKey((SYS.keys[s]||{}).k,m));
  if(clash){RECSLOT=null;RECMOD=null;RECCLASH=slot;paintSys();return}
  RECSLOT=null;RECMOD=null;RECCLASH=null;
  SYS.failed=null;
  /* 화면이 값을 앞질러 앉히지 않는다 — 걸렸는지는 Swift 만 안다(`setSystemState` 가 답이다) */
  post("saveShortcut",{slot:slot,cmd:m.cmd,opt:m.opt,ctrl:m.ctrl,shift:m.shift,key:m.key});
  paintSys();
}

/* ★ 메뉴바 「Settings…」가 부르는 자리 (#61 D). Swift→JS 라 브리지 배열에 안 박힌다.
   ⚠ **면접·연습 중에는 안 끌고 간다.** 그 판정을 Swift 가 하려면 화면 상태를 한 벌 더
     들어야 하고, 그 순간 「지금 무슨 모드인가」의 자가 둘이 된다.
   ★ **그동안 그 메뉴 칸은 회색이다** (#61 리뷰 발견 ⑧) — 여기서 조용히 `return` 하는 것만
     남겨 두면 「눌리는데 아무 일도 안 나는 칸」이 된다. 회색으로 만드는 것은 Swift 가 하되
     자는 안 늘렸다: 모드 이름은 화면이 이미 `resizeWindow` 에 얹어 보내고 있다. */
function openSettingsScreen(){
  if(mode!=="stack")return;
  if(stackView==="edit"&&!leaveEditorAllowed(openSettingsScreen))return;
  /* ★ **이미 설정이면 다시 안 짓는다** (#65 ⑨ 와 같은 사고). 메뉴 칸은 면접·연습에서만
     회색이라 설정 화면에서도 눌리는데, 다시 지으면 사람이 치고 있던 주소·키·모델 칸이
     통째로 날아간다 — 「보던 것을 뺏는 것」이 기능 하나보다 비싸다. */
  if(stackView==="settings")return;
  /* ★ **받기 화면에서 부르면 치던 글을 들고 간다** (#65 P3-4). 받기도 쌓기 모드라 위 가드를
     그냥 지나가는데, `ingestRender` 는 머리에서 화면을 새로 지어 **붙여넣던 자소서 전문이
     통째로 날아갔다.** 나가는 문은 언제나 홈이라 돌아갈 길도 없었다.
     ⚠ **조용한 `return` 으로 안 막는다** — 위 머리글의 #61 리뷰 발견 ⑧ 이 거절한 길이다
       (「눌리는데 아무 일도 안 나는 칸」). 막는 대신 자리표를 들고 간다.
     ⚠ 이 레포는 같은 사고를 이미 세 번 막았다(#65 ⑨ · #66-9 · `drop.test.mjs`) —
       **이 문만 안 막혀 있었다.** */
  SETBACK=null;
  if(stackView==="ingest"){const d=document.getElementById("doc");
    SETBACK={view:"ingest",doc:d?d.value:""}}
  /* ⚠ **창 크기를 안 건드린다** (#67 재편). 전엔 뜻 지도가 자기 창 크기를 가져서 나올 때
     되돌려야 했는데, 지도가 홈의 한 칸이 되면서 그 크기가 하나로 합쳐졌다 — 같은 값을
     다시 보내면 사람이 손으로 키워 둔 창이 원래 크기로 되돌아간다. */
  stackView="settings";
  stackRender();
}
/* ★ 「지금 주소가 표의 어느 줄인가」 — **순수 함수라 `node --test` 가 잠근다** (#65 P3-3).
   돌려주는 것은 줄 번호, 못 가르면 **-1(모르겠다)** 이다. 부르는 쪽이 그때 「직접 입력」을 세운다.
   ⚠ **종류만 보고 물러서지 않는다.** `BackendType` 은 넷인데 프리셋 표는 여덟이라
     `openai` 하나에 **다섯 줄**이 걸린다 — 종류로 물러서면 사설 서버도, 포트를 바꾼 서버도
     전부 첫 줄의 이름을 뒤집어썼다. 그 칸은 「이 키가 어디로 가나」를 말하는 자리라
     남의 이름을 대면 사람이 키를 잘못 넣는다 (같은 뿌리의 다른 반쪽 = `BackendKeyRule`).
   ⚠ 종류가 아직 안 왔으면(브라우저 단독·첫 실행) **첫 줄**이다. 그건 「모르겠다」가 아니라
     아직 아무것도 안 고른 것이다 — 거기서 「직접 입력」을 세우면 빈 주소가 골라져 있다. */
function presetPick(list,url,type){
  const u=(url||"").trim(),t=type||"";
  if(!t)return 0;
  let i=list.findIndex(p=>p.url===u&&p.type===t);
  if(i>=0)return i;
  const o=urlOrigin(u);
  if(o){i=list.findIndex(p=>p.type===t&&urlOrigin(p.url)===o);if(i>=0)return i}
  const same=list.filter(p=>p.type===t);
  if(same.length===1)return list.indexOf(same[0]);
  return same.length?-1:0;
}
/* 주소의 **자리**만 — 뒷길(`/v1`)이 있고 없고는 같은 서버다. 못 읽는 글자는 빈 자리다. */
function urlOrigin(u){try{return new URL(u).origin}catch(e){return ""}}
function settingsRender(){
  /* ★ **지난 방문의 한 줄을 안 들고 들어온다** (#65 ⑦). `setMsg` 는 세션에 사는데 화면을
     열 때 안 비워서, 어제 저장하고 닫은 사람이 오늘 열자마자 「저장했어요」를 봤다 —
     방금 아무것도 안 했는데 뭔가 한 것처럼 읽힌다.
     ⚠ **`setPend` 도 같이 비운다** (#66 리뷰 발견 ④). 그건 「방금 무엇을 시켰나」인데,
       회신이 오기 전에 나갔다 들어오면 **옛 뜻이 그대로 남아** 다음 회신을 잘못 번역한다 —
       키를 지우다 나갔다 들어와 저장하면 「키를 지웠어요」가 뜬다. 짝은 언제나 같이 비운다. */
  setMsg="";setPend=null;
  /* ⚠ **프리셋 표가 이 함수 안에 산다.** 최상위에 두면 그 안의 주소 리터럴이
     `tests/check_interview_offline.py` 의 「최상위 코드」 검사에 걸린다 — 이 화면은
     판정선 경계(`stackRender`) 아래라 안 세어지는데, 최상위는 언제나 세어진다.
     ★ **이 여덟이 프리셋의 정본이다** (#61 D 이후). 네이티브 패널이 들고 있던 짝은
       **죽었다** — 백엔드 칸이 통째로 걷히면서 그 표도 같이 지워졌고(`showShortcutPanel` 머리글의
       「무엇이 나갔나」), 이제 같은 표를 드는 곳이 여기 하나뿐이다. */
  const PRESETS=[
    {label:"Ollama",     type:"ollama",     url:"http://localhost:11434"},
    {label:"OpenAI",     type:"openai",     url:"https://api.openai.com/v1"},
    {label:"Anthropic",  type:"anthropic",  url:"https://api.anthropic.com/v1"},
    {label:"OpenRouter", type:"openrouter", url:"https://openrouter.ai/api/v1"},
    {label:"NVIDIA NIM", type:"openai",     url:"https://integrate.api.nvidia.com/v1"},
    {label:"llama.cpp",  type:"openai",     url:"http://localhost:8080/v1"},
    {label:"LM Studio",  type:"openai",     url:"http://localhost:1234/v1"},
    {label:"vLLM",       type:"openai",     url:"http://localhost:8000/v1"}];
  /* 지금 고른 것 — 판정은 `presetPick` 이 든다(위 머리글). 못 가르면 **「직접 입력」 한 줄**을
     표 끝에 세우고 그것을 고른다. ⚠ 그 줄은 **표에 없는 주소일 때만** 선다 — 늘 붙어 있으면
     고를 수 있는 줄이 되고, 그러면 「무엇을 고른 건지」가 다시 흐려진다. */
  const pk=presetPick(PRESETS,CLOUD.url,CLOUD.type);
  const OPTS=pk>=0?PRESETS:PRESETS.concat([{label:"직접 입력",type:CLOUD.type,url:CLOUD.url}]);
  const pi=pk>=0?pk:OPTS.length-1;
  app.innerHTML=`<div id="top" class="drag">${explorerToggleButton()}<span id="brand">Clonie</span><span style="flex:1"></span>
      <button class="ibtn nodrag" id="x" aria-label="앱 닫기">✕</button></div>
    <div id="cols" class="settings-open">${explorerPane()}<div id="settingspane">
    <div class="settingsbar"><span>설정</span><button class="ibtn" id="setback" title="설정 닫기" aria-label="설정 닫기">×</button></div>
    <div id="setbody"><nav id="setnav" aria-label="설정 항목"><button class="gbtn" data-page="1">음성·권한</button><button class="gbtn" data-page="2">화면·조작</button><button class="gbtn" data-page="3">외부 AI</button></nav>
<section class="setpage" data-page="1">        <div class="mkcard">
          <div class="mkrow"><span class="setlbl">마이크</span>
            <span class="mkstat"><span class="mkdot" id="pdot-mic"></span><span id="ptxt-mic"></span></span>
            <span class="mkfine">내 목소리</span><span style="flex:1"></span>
            <button class="gbtn setperm" data-what="mic">시스템 설정 열기</button></div>
          <div class="mkrow"><span class="setlbl">화면 기록</span>
            <span class="mkstat"><span class="mkdot" id="pdot-screen"></span><span id="ptxt-screen"></span></span>
            <span class="mkfine">상대 목소리</span><span style="flex:1"></span>
            <button class="gbtn setperm" data-what="screen">시스템 설정 열기</button></div>
        </div>
        <div class="mkcard">
          <div class="mkrow"><span class="setlbl">한국어 받아쓰기</span><span class="mkfine" id="speechstate"></span><span style="flex:1"></span><button class="gbtn" id="speechprepare">모델 준비</button></div>
          <div class="mkfine">처음에는 모델 다운로드가 필요할 수 있어요. 음성은 이 Mac에서 처리해요.</div>
        </div>
        <p class="mkfine">외부 자료나 AI 사용이 금지된 시험·평가에서는 사용하지 마세요.</p>
</section>
<section class="setpage" data-page="2" hidden>        <div class="mkcard">
          <div class="mkrow"><span class="setlbl">블러</span>
            <input type="range" id="setblur" min="0" max="1" step="0.05" value="${WSTYLE.blur}"></div>
          <div class="mkrow"><span class="setlbl">불투명</span>
            <input type="range" id="setopa" min="0.35" max="1" step="0.05" value="${WSTYLE.opacity}"></div>
        </div>
        <div class="mkcard">
          <div class="mkrow"><span class="setlbl">창 토글</span>
            <button class="gbtn setkey" id="key-toggle">—</button>
            <span class="mkfine" id="keymsg-toggle"></span></div>
          <div class="mkrow"><span class="setlbl">캡처</span>
            <button class="gbtn setkey" id="key-capture">—</button>
            <span class="mkfine" id="keymsg-capture"></span></div>
        </div>
</section>
<section class="setpage" data-page="3" hidden>
        <div class="mkcard"><div class="setlbl">Clonie 안에서 자료 정리</div>
          <div class="mkfine">API와 CLI로 가져온 자료의 초안을 만들어요.</div></div>
        <div id="setbrain"></div>
        <div id="setcli"></div>
        <div class="mkcard">
          <div class="mkrow"><span class="setlbl">제공자</span>
            <span class="setsel"><select class="setfld" id="setpreset">${OPTS.map((p,i)=>
              `<option value="${i}"${i===pi?" selected":""}>${esc(p.label)}</option>`).join("")}</select></span></div>
          <div class="mkrow"><span class="setlbl">주소</span>
            <input class="setfld" id="seturl" spellcheck="false" value="${esc(CLOUD.url||OPTS[pi].url)}"></div>
          <div class="mkrow"><span class="setlbl">API 키</span>
            <input class="setfld" id="setkey" type="password" spellcheck="false" placeholder="">
            <button class="mklink" id="setclr">키 지우기</button></div>
          <div class="mkrow"><span class="setlbl">모델</span>
            <input class="setfld" id="setmodel" spellcheck="false" list="setmodels"
              value="${esc(CLOUD.model)}"><datalist id="setmodels"></datalist></div>
          <div class="mkfine" id="setmodelstatus"></div>
          <div class="mkrow" id="setprovideraction" style="display:none">
            <span class="setlbl">제공자 변경</span><span class="mkfine">키를 바꾸기 전에 저장을 눌러 주세요.</span>
            <span style="flex:1"></span><button class="gbtn p" id="setprovidersave">변경 저장</button></div>
          <div class="mkfine" id="setmsg">${esc(setMsg)}</div>
        </div>
        <div class="mkcard"><div class="mkrow"><span class="setlbl">외부 앱에서 저장소 사용</span>
          <span class="mkfine">MCP</span></div>
          <div class="mkfine">Claude 같은 외부 앱이 같은 저장소를 읽고 쓸 때 사용하는 별도 경로예요.</div></div>
<button class="gbtn" id="organizefiles">자료 정리</button></section>
    </div>
    </div></div>
    ${confirmBox("저장된 키를 지울까","지운다","둔다")}`;
  bindExplorerPane();
  app.querySelectorAll("#setnav button").forEach(button=>{
    button.classList.toggle("active",button.dataset.page==="1");
    button.onclick=()=>{
      app.querySelectorAll(".setpage").forEach(page=>{page.hidden=page.dataset.page!==button.dataset.page});
      app.querySelectorAll("#setnav button").forEach(b=>b.classList.toggle("active",b===button));
    };
  });
  document.getElementById("organizefiles").onclick=()=>{stackView="ingest";stackRender()};
  /* ★ **들어온 자리로 돌아간다** (#65 P3-4). 전엔 언제나 홈이라, 받기 화면에서
     메뉴바 「Settings…」로 들어온 사람은 치던 글도 잃고 돌아갈 길도 없었다.
     자리표를 비우는 자는 `ingestRender` 하나다(그 머리글) — 여기서 비우면 글이 안 돌아온다. */
  document.getElementById("setback").onclick=()=>{
    stackView=(SETBACK&&SETBACK.view)||"edit";stackRender()};
  document.getElementById("x").onclick=()=>post("closeWindow");
  /* ★ **열 때마다 다시 잰다.** 사람이 터미널에서 로그인하고 돌아오는 것이 이 화면의 동선이다.
     ⚠ 두뇌 선택도 **같은 답**으로 온다 — 통로를 안 늘렸다(`detectCli` 의 회신 칸이 늘었다). */
  paintBrain();
  paintCliCards();
  post("detectCli");
  /* ★ 모델 목록도 열 때마다 다시 묻는다 (#61 리뷰 발견 ②) — **이미 있는 통로**다.
     ⚠ **판정선 밖이다.** `loadModels` 는 네트워크에 닿고(`fetchModels`), 그래서 이 자리는
       `stackRender` 아래(= 검사가 안 세는 경계 밖)여야 한다. 면접 화면에서는 안 열린다.
     ⚠ 답이 안 와도 화면은 그대로다 — 자유 입력 칸이고 목록은 거들 뿐이다(`MODELS` 머리글). */
  requestModelList();
  const pre=document.getElementById("setpreset"),url=document.getElementById("seturl"),
        key=document.getElementById("setkey"),mdl=document.getElementById("setmodel"),
        providerAction=document.getElementById("setprovideraction"),providerSave=document.getElementById("setprovidersave");
  let providerPending=false;
  let providerBefore={value:pre.value,url:url.value,model:mdl.value};
  const setProviderPending=v=>{
    providerPending=!!v;
    key.disabled=providerPending;
    document.getElementById("setclr").disabled=providerPending;
    if(providerAction)providerAction.style.display=providerPending?"":"none";
    if(providerSave)providerSave.style.display=providerPending?"":"none";
  };
  const askConfirm=(q,yes,no,onYes,onNo)=>{
    const cf=document.getElementById("confirm"),y=document.getElementById("cyes"),n=document.getElementById("cno");
    setConfirmCopy(q,yes,no);
    if(n)n.onclick=()=>{if(cf)cf.classList.remove("on");if(onNo)onNo()};
    if(y)y.onclick=()=>{if(cf)cf.classList.remove("on");onYes()};
    openConfirm();
  };
  /* 키 칸이 비면 안 싣는다. 제공자·서버 변경은 확인을 거친 뒤 이 함수로 온다. */
  const push=extra=>{
    const b={type:OPTS[+pre.value].type,url:url.value.trim(),model:mdl.value.trim()};
    if(key.value)b.key=key.value;
    for(const k in (extra||{}))b[k]=extra[k];
    setPend=(extra&&extra.clearKey)?"clear":"save";
    post("saveBackend",b);
    providerBefore={value:pre.value,url:b.url,model:b.model};
    /* ⚠ 지우기와 저장이 **같은 통로**라 말도 여기서 갈린다 — 「저장했어요」 하나로 두면
       키를 지운 사람이 「방금 뭘 저장한 거지」를 묻는다 (#65 ②). 글자는 `pendMsg` 한 집이다. */
    setMsg=pendMsg();paintSetMsg();
  };
  /* ★ **제공자 선택은 저장이 아니다** (#65 ③). 앞 제공자의 키를 화면에서 몰래 지우거나
     새 주소로 보내지 않도록, 선택은 보류하고 사람이 「변경 저장」을 눌렀을 때만 확정한다.
     키 칸의 미저장 입력도 확인 전에는 그대로 둔다. */
  pre.onchange=()=>{
    url.value=OPTS[+pre.value].url;
    mdl.value="";MODEL_REQUEST++;MODELS=[];MODEL_STATUS="idle";MODEL_MESSAGE="";paintModelList();setProviderPending(true);
  };
  url.onchange=()=>{
    if(urlOrigin(url.value.trim())!==urlOrigin(providerBefore.url)){
      MODEL_REQUEST++;MODELS=[];MODEL_STATUS="idle";MODEL_MESSAGE="";paintModelList();setProviderPending(true);
    }
    if(providerPending){setMsg="제공자 변경을 저장해 주세요";paintSetMsg()}else push();
  };
  mdl.onchange=()=>{if(providerPending){setMsg="제공자 변경을 저장해 주세요";paintSetMsg()}else push()};
  key.onchange=()=>{
    if(providerPending||!key.value)return;
    push();key.value="";
  };
  /* ★ **되돌릴 수 없는 것 앞에 한 번 더 묻는다** (#65 ②). 화면은 저장된 키를 되읽지 못하므로
     (`saveBackend` 머리글) 잘못 지운 키의 복구는 「사람이 어디선가 다시 찾아와 친다」뿐이다 —
     그 값이 확인 한 번보다 비싸다. 상자는 면접 「끝내기」와 **같은 한 벌**이다(`confirmBox`). */
  const clr=document.getElementById("setclr");
  clr.onclick=()=>askConfirm("저장된 키를 지울까","지운다","둔다",()=>{key.value="";push({clearKey:true})});
  providerSave.onclick=()=>{
    if(!providerPending)return;
    const needsConfirm=!!CLOUD.hasKey||!!key.value;
    const finish=()=>{
      if(needsConfirm)key.value="";
      setProviderPending(false);push(needsConfirm?{clearKey:true}:{});requestModelList();
    };
    if(needsConfirm){
      askConfirm("이전 제공자의 저장된 키를 지울까","변경 저장","돌아가기",finish,()=>{
        pre.value=providerBefore.value;url.value=providerBefore.url;mdl.value=providerBefore.model;
        MODELS=[];setProviderPending(false);requestModelList();
      });
    }else finish();
  };
  /* 키 줄의 지금 모습 — placeholder 와 「키 지우기」가 `CLOUD.hasKey` 를 따른다 (#65 ①②) */
  paintBackendKey();
  /* ★ 창 손잡이 — **불투명도는 이 자리에서 즉시 CSS 로**, 블러는 Swift 가 창 뒤에 건다.
     ⚠ 둘 다 `oninput` 이다: 슬라이더를 놓을 때만 반영하면 「얼마나 흐린가」를 눈으로 못 고른다. */
  const blur=document.getElementById("setblur"),opa=document.getElementById("setopa");
  const style=()=>{WSTYLE.blur=+blur.value;WSTYLE.opacity=+opa.value;
    applyPanelOpacity();post("setWindowStyle",{blur:WSTYLE.blur,opacity:WSTYLE.opacity})};
  blur.oninput=style;opa.oninput=style;
  /* ★ 단축키 · 권한 · 볼트 (2026-08-31 설정 통합) — **여기가 그 셋의 마지막 집이다.**
     네이티브 미니 패널로 보내던 한 줄(`openSettings`)은 죽었다.
     ⚠ **열 때마다 다시 잰다** — 사람이 시스템 설정에서 권한을 켜고 돌아오는 것이 동선이다
       (연결 카드가 `detectCli` 를 다시 부르는 것과 같은 규율). */
  RECSLOT=null;RECMOD=null;RECCLASH=null;SYS.failed=null;
  document.onkeydown=recKey;
  for(const slot of KEYSLOTS){
    const b=document.getElementById("key-"+slot);
    b.onclick=()=>{RECSLOT=RECSLOT===slot?null:slot;RECMOD=null;RECCLASH=null;SYS.failed=null;paintSys()};
  }
  /* ★ **다른 칸에 손이 가면 녹화가 풀린다** (#65 ④). 녹화 중 `document.onkeydown` 은 키를
     전부 `preventDefault` 로 삼킨다 — 그 상태로 주소·모델 칸을 누르면 **글자가 한 자도 안
     들어가고**, 사람은 칸이 죽은 줄 안다. 전엔 나가는 문이 Esc 와 그 버튼 재클릭 둘뿐이었다.
     ⚠ 자리는 **칸 쪽**이다. 문서에 한 벌 걸면 녹화 버튼 자신의 포커스까지 같이 먹는다.
     ⚠ **사유 한 줄도 같이 걷는다** (#66 리뷰 발견 ⑤). 겹침 거절(`RECCLASH`)은 녹화를 **접으면서**
       세우는 값이라 `RECSLOT` 이 이미 null 이다 — 「녹화 중일 때만」으로 걸러 두면 이 줄이
       영영 안 걷혀 다른 칸으로 옮겨가도 「같은 조합이 다른 자리에 있어요」가 붙어 있었다. */
  const dropRec=()=>{if(!RECSLOT&&!RECCLASH)return;RECSLOT=null;RECMOD=null;RECCLASH=null;paintSys()};
  [pre,url,key,mdl,blur,opa].forEach(el=>{if(el)el.onfocus=dropRec});
  app.querySelectorAll(".setperm").forEach(el=>
    el.onclick=()=>post("openSystem",{what:el.dataset.what}));
  /* ★ 볼트 줄도 같은 잠금이다 (#80 1). ⚠ **취소가 안 오는 줄**이라 스스로 푸는 시계를
     같이 건다 — 위 `PICKING` 머리글의 그 갈림이다. 답(`setSystemState`)이 먼저 오면 그쪽이 푼다. */

  paintSpeechModel();
  document.getElementById("speechprepare").onclick=()=>{
    if(["unknown","loading","ready","unsupported"].includes(SPEECH_STATE))return;
    onSpeechModelState("loading","");post("prepareSpeechModel");
  };
  paintSys();
  post("probeSystem");
}

/* ★ 창 손잡이 둘이 되돌아온다 (#61 B). Swift 가 창이 뜰 때 한 번, 그리고 설정에서 바뀔 때마다.
   ⚠ **블러는 여기서 안 만진다** — 그건 창 뒤의 AppKit 층이고 Swift 가 이미 걸었다.
     화면이 드는 것은 판의 불투명도 하나(`--opa`)다(`WindowStyle` 머리글의 갈림).
   ⚠ 값이 없거나 이상하면 **1**(지금까지의 그 화면)로 물러선다. */
let WSTYLE={blur:0,opacity:1};
function setWindowStyleValues(json){
  let d;try{d=typeof json==="string"?JSON.parse(json):json}catch(e){return}
  if(!d)return;
  WSTYLE.blur=clamp01(d.blur,0);
  WSTYLE.opacity=clamp01(d.opacity,1);
  applyPanelOpacity();
}
const clamp01=(v,dflt)=>{const n=Number(v);return (isFinite(n)&&n>=0&&n<=1)?n:dflt};
function applyPanelOpacity(){
  try{document.documentElement.style.setProperty("--opa",String(WSTYLE.opacity))}catch(e){}
}

/* ★ QA 노출 게이트가 켜졌나 (#24 C 층 → #61 E). Swift 가 창이 뜰 때 한 번 알려 준다.
   ⚠ **통로를 안 늘렸다** — Swift→JS 다(`setCloudDrafter` 와 같은 길).
   ⚠ **이 값으로 은신을 정하지 않는다.** 창이 잡히나 마나는 `WindowPrivacy` 하나가 정하고
     (`tests/check_qa_visible_gate.py` 가 그것을 잰다), 여기 값은 **화면이 검증용 숫자를
     보여도 되나**의 판정일 뿐이다. 안 오면 `false` — 기본이 「안 보인다」다. */
let QAVIS=false;
function setQAVisible(on){QAVIS=!!on}

/* ── Swift 가 부르는 자리. v1 은 안 쓰지만 없애면 조용히 깨진다 ── */
function appendToken(){} function endStream(){} function onMicError(){}
function onRecordingStarted(){} function onScreenshotCaptured(){} function onScreenshotError(){}
function onTranscribing(){} function onWhisperStatus(){}
function setSavedModel(){} function setScreenshotPrompt(){}
/* ⚠ `setShortcut`·`setCaptureShortcut` 둘은 **걷혔다** (2026-08-31 설정 통합). 빈 스텁이라
   Swift 가 보낸 단축키가 그대로 버려지고 있었고 — 그 값을 네이티브 패널이 들고 있었으므로 —
   화면이 그 칸을 갖게 되면서 `setSystemState` 하나가 그 자리를 대신한다. */
/* ★ **재조준할 값이 있는 질문인가.** `실측 2026-08-30`(E2E 실기 블로커): 면접관의 추임새
   ("네", "음", "아 알겠습니다")도 `them` 발화라 `onEar` 가 그때마다 검색어를 갈아끼웠고,
   **답변을 읽는 중에 카드가 사라졌다**(`opened`·`manual` 이 같이 초기화된다).
   그래서 재조준을 이 자 뒤로 보냈다 — 맞장구를 걷어낸 뒤 남는 글자로 잰다.

   ⚠ 들어오는 것은 이미 부호가 걷힌 글자(`TranscriptText.forSearch`)다. 여기서 부호를 다시 안 판다.
   ⚠ **어절 통째로만 걷는다.** 부분 문자열로 지우면 "어떤"의 "어", "아니라"의 "아" 가 같이 녹아
     실제 질문이 짧아진다. 목록에 없는 어절은 그대로 남는다 — 화이트리스트가 아니다.
   ⚠ **알고 두는 한계**: "왜요?" 같은 초단문 후속 질문은 문턱에 같이 걸린다. 문턱을 내리면
     맞장구가 다시 새는데(대부분 2~4자) 그쪽이 더 비싸다 — 못 잡은 초단문은 사용자가 카드를
     손으로 고르면 되지만, 헛재조준은 **보던 것을 뺏는다.** 자물쇠 = `tests/askable.test.mjs`. */
const ASK_MIN=5;
const FILLER=new Set(["네","넹","넵","예","응","음","어","아","오","그","뭐",
  "네네","예예","어어","음음","아아","그래","그래요","그렇죠","그쵸","그렇군요","그렇습니다",
  "알겠습니다","알겠어요","좋습니다","좋아요","맞아요","맞습니다","오케이","감사합니다","고맙습니다"]);
function askable(q){
  if(typeof q!=="string")return false;
  return q.split(/\s+/).filter(w=>w&&!FILLER.has(w)).join("").length>=ASK_MIN;
}
/* ★ 귀가 들은 것이 들어오는 **유일한 통로** (#17). Swift `InterviewEars` 가 부른다.
   who = 어느 관에서 왔나 · confirmed = 굳은 글자 · volatile = 아직 흔들리는 꼬리 ·
   query = 검색에 넣을 글자(부호 걷힌 것) · ended = 이 발화가 끝났나. */
function onEar(json){
  let e;try{e=JSON.parse(json)}catch(_){return}
  /* ★ 연습도 **같은 통로**로 듣는다 (#36). 다른 것은 어느 관을 보나뿐이다 —
     면접은 상대(`them`)의 말이 질의고, 연습은 묻는 것이 앱이라 **내 말(`me`)이 질의**다.
     ⚠ 연습에서는 `them` 관이 아예 안 열린다(`render` 가 마이크만 연다). 그래도 여기서
       한 번 더 거른다 — 관이 살아 있는 채로 모드가 바뀌는 찰나가 있다. */
  if(mode==="practice"){
    if(!prac||prac.done||e.who!=="me")return;
    prac.cur=e.confirmed||"";prac.vol=e.volatile||"";prac.curq=e.query||"";
    if(e.ended){
      /* ⚠ **한 답이 여러 발화로 갈린다.** 귀는 4초 침묵을 발화 끝으로 보는데(`InterviewEars`
         의 `silenceGap`), 면접 답변은 그보다 긴 뜸을 문다. 그래서 끝난 발화를 **쌓아**
         하나의 답으로 본다 — 면접 모드가 발화마다 검색어를 갈아끼우는 것과 **반대**다.
         저기선 발화 하나가 질문 하나지만, 여기선 질문이 앱에서 오고 답이 길다. */
      prac.head=(prac.head+" "+prac.cur).trim();
      prac.headq=(prac.headq+" "+prac.curq).trim();
      prac.cur="";prac.vol="";prac.curq="";
      gradePractice();                 /* 말이 멎으면 자동 채점. 다음으로 넘기는 것은 사람이 한다 */
    }
    paintPractice();
    return;
  }
  if(mode!=="live")return;
  const lane=CUR[e.who];if(!lane)return;
  lane.c=e.confirmed||"";lane.v=e.volatile||"";
  curWho=e.who;                      /* 큰 줄에는 **마지막으로 말한 쪽**이 뜬다 */
  if(e.who==="them"){
    /* ⚠ 맞장구면 **검색어를 그대로 둔다** — 보던 카드가 접히지 않게(`askable` 주석).
       전사 표시(`paintCur`)는 그대로다: 들리는 것은 계속 보여야 한다. */
    if(askable(e.query)){
      if(e.query!==heardV){heardV=e.query;opened=null;manual=false}   /* 새 질문 = 자동 펼침 초기화 */
      applyRank(!!e.ended);
    }
  }else{
    mineV=e.query;if(!manual)autoPick();
  }
  paintCur();
  if(e.ended){
    if(e.who==="them")harvestQuestion(e.query);   /* 확정된 질문만 본다 (#22) */
    flushCur(e.who);
    /* 저쪽이 아직 말하는 중이면 큰 줄을 그쪽에 넘긴다 — 안 그러면 내가 답하는 중에 줄이 빈다 */
    const other=e.who==="them"?"me":"them";
    if((CUR[other].c+CUR[other].v).trim()){curWho=other;paintCur()}
  }
}
/* ★ 질의 벡터가 도착하는 자리 (#34). `onEar` 뒤에 **따로** 온다 — 전사 표시가 임베딩을
   기다리지 않게 하려고 통로를 갈랐다(Swift 쪽 `startInterviewEars` 주석에 그 경위가 있다).

   ⚠ **벡터와 그 벡터가 나온 글자를 같이 든다.** `scorer()` 가 지금 들리는 말과 대조해서,
     한 발 늦게 도착한 벡터로는 절대 안 매긴다 — 대조 없이 쓰면 화면이 **조용히 틀린 답**을
     가리킨다. 늦게 온 벡터는 그냥 앉아 있다가 그 글자가 다시 맞으면 산다.
   ⚠ 다시 그리는 것은 `applyRank` 하나다. 여기서 `liveRender()` 를 부르면 안 된다 —
     `paintCur`·`onIndexNotice` 와 같은 이유로 사용자가 보던 것이 갈아끼워진다. */
function onQueryVector(json){
  if(!VEC)return;                       /* 문서 벡터가 없으면 질의 벡터만으로는 못 매긴다 */
  let d;try{d=JSON.parse(json)}catch(e){return}
  if(!d||typeof d.query!=="string")return;
  const v=unvec(d.v,VEC.dim);
  if(!v)return;
  QVEC={q:d.query,v:v};
  if(mode==="live")applyRank(true);
}
/* 사람이 손을 써야 닫히는 것만 온다 (권한·장치). 화면 아래 한 줄. */
function onEarTrouble(msg){
  trouble=msg||null;
  const t=document.getElementById("trouble");
  if(t)t.innerHTML=trouble?`<div class="trouble">${esc(trouble)}</div>`:"";
}
/* whisper 경로가 주던 것. 죽어 있지만 Swift 가 아직 부른다 — 지우면 조용히 깨진다. */
function onTranscription(text){
  if(mode!=="live"||!text)return;
  curWho="them";CUR.them.c=text;CUR.them.v="";heardV=text;opened=null;manual=false;
  paintCur();applyRank(true);
}
/* ══ 쌓기 홈의 그림 — 인라인 이분 뷰 ═══════════════════════════════════════════
   ★ 이 구획은 **목업 셋이 남긴 것**이다 (#45 #46 #57 → 승격 라운드 #61 A):
     - 목업 A(구독 연결 카드)는 **프론트 설정 화면**으로 옮겼다 — 어휘(`mk*` CSS)만 남았다.
     - 목업 B(전체 지도 화면)는 **통째로 걷혔다**(그릴 Q1 ⑤). 인라인 뷰가 그 일을 하고,
       화면 하나를 덜 갖는 것이 미니멀 원칙이다. 같이 걷힌 것: `mapRender`·`paintMap`·
       `mapSvg`·`mapTop`·`mapData`·`MAPSEED`·`MAPSEEDDOT`·`MAP_*`·`BI_WIDE`·`#map` CSS.
     - 목업 C(쌓기 재설계)는 **정식 화면**이 됐다(`stackRender`). 이름이 `s2*` → `hm*` 다.
   ⚠ 그래서 **부르는 쪽이 하나로 줄었다.** 그래도 안 합친다 — 「무엇을 그릴까」와
     「어떻게 그릴까」가 갈려 있는 것이 이 그림의 뜻을 지킨다(아래 그 함수 머리글).
   ⚠ **씨앗 판(지어낸 색·지어낸 유사도)이 같이 죽었다.** 그릴 판이 언제나 지금 볼트라,
     화면이 「이 색은 지어낸 것」이라고 유보할 자리가 이제 없다. ══ */

/* ⚠ **질문 준비도로 점을 칠하던 셋이 죽었다** (#74 B4·C2 — 옛 이름은 여기 안 적는다.
   걷힘을 세는 검사가 주석을 안 가려서, 적으면 그 자리가 안 걷힌 것으로 세어진다).
   왼쪽 칸은 이제 **폴더 트리**라 쉴 때 점이 없고, 검색 중에만 별과 **같은 색**의 점이
   붙는다 — 그 색은 지도가 이미 낸 것을 그대로 읽는다(`CANV.last`). 자가 하나라는 규율은
   그대로고, 사라진 것은 「질문 준비도」라는 **두 번째 어휘**다(ADR 0006). */
const HM_NEAR=4;    /* 이웃 상한 — 고른 조각까지 다섯 줄이면 순위 상자의 키가 맞는다 */
/* ★ 뜻이 가까운 이웃 조각 — **순서와 등급을 같이 낸다** (#74 B4).
   ⚠ 벡터가 있으면 조각↔조각 코사인(`cosv`)이고 색은 `eris(cos/SIM_G_DIRECT)` —
     **라이브 검색이 쓰는 그 눈금 그대로다.** 없으면 글자(`sim`)로 물러서고 **색을 안 낸다**
     (`"n"`): 눈금이 달라 섞으면 그 색이 거짓말이 된다(#34 의 선언된 갈림).
   ⚠ 씨앗은 이웃으로 안 그린다 — 예시가 내 답변 옆에 앉으면 그림이 그것을 답으로 말한다.
   ★ `kin` = **같은 항성 안의 조각 id 표**(#74 B4). 주면 그 밖은 후보에서 빠진다 —
     이웃이 항성을 건너뛰면 「폴더 = 중심체」라는 그림이 그 순간 거짓말이 된다.
     안 주면(항성을 못 찾는 볼트) 전 판 그대로 갤럭시 전체에서 고른다. */
function hmNear(p,kin){
  return (DOC.fragments||[]).filter(x=>x.id!==p.id&&!isSeed(x))
    .filter(x=>!kin||Object.prototype.hasOwnProperty.call(kin,x.id))
    .map(x=>{
      const c=passagePairScore(p,x,VEC);
      return c===null
        ?{p:x,s:sim(p.title+" "+p.body,x.title+" "+x.body),c:"n"}
        :{p:x,s:c,c:eris(c/SIM_G_DIRECT)};
    })
    .filter(x=>x.s>0).sort((a,b)=>b.s-a.s).slice(0,HM_NEAR);
}

/* 문서 두 개의 이웃 점수도 passage 쌍의 최댓값이다. 한 passage만 든 기존 꾸러미는
   `frags`로 같은 결과를 내므로, 옛 화면 fixture가 새 계약 때문에 무채색이 되지 않는다. */
function passagePairScore(a,b,vec){
  const P=((vec||{}).passages||{}),aa=P[a&&a.id]||[],bb=P[b&&b.id]||[];
  let best=null;
  aa.forEach(x=>bb.forEach(y=>{const score=cosv(x.v,y.v);if(score!==null&&(best===null||score>best))best=score}));
  if(best!==null)return best;
  return cosv(((vec||{}).frags||{})[a&&a.id],((vec||{}).frags||{})[b&&b.id]);
}
DOC=load();
render();
</script>
</body>
</html>
"""# }
