const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const html=fs.readFileSync('docs/ogrenci/index.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/boot\(\);\s*$/,'');
function setup(){
 const nodes=Object.fromEntries(['#bk-rows','#bk-total','#bk-status','#bk-sentinel'].map(k=>[k,{innerHTML:'',textContent:'',insertAdjacentHTML(_,h){this.innerHTML+=h;}}]));
 const pending=[];
 const ctx=vm.createContext({URL,localStorage:{getItem:()=>null},document:{querySelector:s=>nodes[s]},setTimeout,clearTimeout,IntersectionObserver:class{observe(){} disconnect(){}},fetch:url=>new Promise(resolve=>pending.push({url,resolve}))});
 vm.runInContext(script,ctx);
 return {ctx,nodes,pending,run:s=>vm.runInContext(s,ctx),reply(i,books,page=1,totalPages=2,status=200){pending[i].resolve({status,json:async()=>({books,pagination:{page,totalPages},summary:{totalQuantity:4000}})});}};
}
test('next batch appends without replacing prior rows; concurrent loads are blocked',async()=>{
 const t=setup();let a=t.run('fetchBooks(1)');t.reply(0,[{title:'First'}]);await a;
 a=t.run('fetchBooks(2)');await t.run('fetchBooks(2)');assert.equal(t.pending.length,2);
 t.reply(1,[{title:'Second'}],2);await a;
 assert.equal(t.run('state.books.items.length'),2);assert.match(t.nodes['#bk-rows'].innerHTML,/First[\s\S]*Second/);
 assert.equal(t.nodes['#bk-status'].textContent,'Tüm kitaplar gösteriliyor');
});
test('new search wins over stale response',async()=>{
 const t=setup();const old=t.run('fetchBooks(1)');const fresh=t.run('state.books.search="new";fetchBooks(1)');
 t.reply(1,[{title:'New result'}],1,1);await fresh;t.reply(0,[{title:'Old result'}]);await old;
 assert.match(t.nodes['#bk-rows'].innerHTML,/New result/);assert.doesNotMatch(t.nodes['#bk-rows'].innerHTML,/Old result/);
});
test('failed next batch keeps existing results and announces failure',async()=>{
 const t=setup();let a=t.run('fetchBooks(1)');t.reply(0,[{title:'Keep me'}]);await a;
 a=t.run('fetchBooks(2)');t.reply(1,[],2,2,500);await a;
 assert.match(t.nodes['#bk-rows'].innerHTML,/Keep me/);assert.match(t.nodes['#bk-status'].textContent,/yüklenemedi/);assert.equal(t.run('state.books.page'),1);
});
test('empty batch stops loading and tab departure ignores pending response',async()=>{
 const t=setup();let a=t.run('fetchBooks(1)');t.reply(0,[],1,100);await a;
 assert.equal(t.run('state.books.totalPages'),1);assert.equal(t.nodes['#bk-status'].textContent,'Kitap bulunamadı');
 a=t.run('fetchBooks(1)');t.run('stopBookLoading()');t.reply(1,[{title:'Late result'}]);await a;assert.doesNotMatch(t.nodes['#bk-rows'].innerHTML,/Late result/);
});
