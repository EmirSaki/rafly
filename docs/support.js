const form=document.querySelector('#support-search');
const query=document.querySelector('#query');
const status=document.querySelector('#search-status');
const entries=[...document.querySelectorAll('.searchable')];
const normalize=text=>text.toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/ı/g,'i');
function search(scroll=false){const words=normalize(query.value.trim()).split(/\s+/).filter(Boolean);let count=0;entries.forEach(entry=>{const matches=words.every(word=>normalize(entry.textContent).includes(word));entry.hidden=!matches;if(matches){count++;if(words.length&&entry.tagName==='DETAILS')entry.open=true;}});status.replaceChildren();status.hidden=!words.length;if(words.length){status.append(document.createTextNode(count?`${count} sonuç bulundu.`:'Sonuç bulunamadı. Farklı bir kelime deneyin veya e-posta ile bize ulaşın.'));const reset=document.createElement('button');reset.type='button';reset.textContent='Aramayı temizle';reset.onclick=()=>{query.value='';search();query.focus();};status.append(reset);if(scroll)status.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth'});}}
form.addEventListener('submit',event=>{event.preventDefault();search(true);});query.addEventListener('input',()=>search());
document.querySelectorAll('a[href^="#"]').forEach(link=>link.addEventListener('click',()=>{if(query.value){query.value='';search();}}));
