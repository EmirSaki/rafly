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

// Kişisel iade uyarısı: numara + okul seviyesi birlikte eşleşmeli.
function visible(level,number,targetValues){
 context.__in={level,number,targetValues};
 return vm.runInContext(`(()=>{
  state.schoolLevel=__in.level; state.user={student_number:__in.number};
  return annVisible({target_type:'section',target_values:__in.targetValues,start_date:'2000-01-01',end_date:'2999-01-01'},new Date());
 })()`,context);
}
test('warning for lise 10 is shown to lise 10 only',()=>{
 assert.equal(visible('lise','10',['10','seviye:lise']),true);
 assert.equal(visible('ortaokul','10',['10','seviye:lise']),false);
 assert.equal(visible('lise','11',['10','seviye:lise']),false);
});
test('level tag is matched case-insensitively and as a JSON string',()=>{
 assert.equal(visible('lise','10','["10","Seviye:LISE"]'),true);
 assert.equal(visible('ortaokul','10','["10","seviye:lise"]'),false);
});
test('old warnings without a level tag still match by number',()=>{
 assert.equal(visible('ortaokul','10',['10']),true);
 assert.equal(visible('ortaokul','11',['10']),false);
});
