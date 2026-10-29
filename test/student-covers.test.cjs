const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'docs/ogrenci/index.html'),'utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/boot\(\);\s*$/,'');
const context=vm.createContext({URL,localStorage:{getItem:()=>null},document:{querySelector:()=>({})},setTimeout,clearTimeout});
vm.runInContext(script,context);
test('all inline JavaScript parses',()=>assert.doesNotThrow(()=>new vm.Script(script)));
test('API cover_url and coverUrl are escaped and rendered',()=>{
 for(const key of ['cover_url','coverUrl']){
 const result=context.bookCover({[key]:'https://example.com/book.jpg?a=1&b=2'});
 assert.match(result,/src="https:\/\/example.com\/book.jpg\?a=1&amp;b=2"/);
 assert.match(result,/object|cover-art/);
 }
});
test('missing, whitespace, invalid and unsafe covers use only symbolic book',()=>{
 for(const url of [null,'','   ','javascript:alert(1)','data:image/svg+xml,<svg/>','https://[broken']){
 const result=context.bookCover({cover_url:url});
 assert.match(result,/symbolic-book/);assert.doesNotMatch(result,/<img/);
 }
});
test('relative backend covers resolve against API, not Pages',()=>{
 assert.match(context.bookCover({cover_url:'/covers/1.jpg'}),/https:\/\/library-api-346058361420.europe-west1.run.app\/covers\/1.jpg/);
});
test('broken image removes itself, preserves fallback without retry loop',()=>{
 const result=context.bookCover({cover_url:'https://example.com/missing.jpg'});
 const handler=result.match(/onerror="([^"]+)"/)[1];
 let removed=false;new Function(handler).call({remove(){removed=true}});assert.equal(removed,true);
 assert.match(result,/symbolic-book/);assert.doesNotMatch(handler,/src=/);
});
test('history uses backend cover and preserves status/dates with escaped text',()=>{
 const result=context.rzCard({book_name:'<script>alert(1)</script>',book_writer:'Author',cover_url:'https://example.com/a.jpg',status:'returned',reserved_at:'2026-10-01',due_date:'2026-10-15',returned_at:'2026-10-12'});
 assert.match(result,/src="https:\/\/example.com\/a.jpg"/);assert.match(result,/İade Edildi/);assert.match(result,/2026-10-12/);assert.doesNotMatch(result,/<script>/);
});
test('reservation controller returns cover with existing scoped query',async()=>{
 const source=fs.readFileSync(path.join(root,'backend/src/controllers/student.controller.js'),'utf8');
 const fn=source.slice(source.indexOf('const getMyReservations ='),source.indexOf('\n};',source.indexOf('const getMyReservations ='))+3);
 let query,params,body;
 const ctx=vm.createContext({pool:{query:async(q,p)=>{query=q;params=p;return {rows:[{cover_url:'https://example.com/a.jpg'}]}}}});
 vm.runInContext(fn+'\nthis.handler=getMyReservations;',ctx);
 await ctx.handler({user:{user_id:42,school_code:'123456'}},{status(){return this},json(b){body=b}},e=>{throw e});
 assert.match(query,/b\.cover_url/);assert.match(query,/WHERE r.user_id = \$1/);assert.equal(params[0],42);assert.equal(body.data[0].cover_url,'https://example.com/a.jpg');
});
