const features=[['book','Kaynak Yönetimi','Kitap, dergi ve tüm materyalleri kolayca yönetin.'],['refresh','Ödünç & İade İşlemleri','Hızlı ödünç verme, iade alma ve süre takibi.'],['users','Öğrenci & Kullanıcı Yönetimi','Öğrenci listeleri, sınıf bazlı yönetim ve yetkilendirme.'],['chart','Raporlar & İstatistikler','Kullanım, ödünç ve en çok okunanlar gibi detaylı raporlar.'],['megaphone','Anlık Bildirimler','Kitap iade süresi dolan öğrencilere anlık hatırlatma bildirimleri gönderin.'],['cloud','Rapor & Dışa Aktarma','Kitap ve işlem listelerini dışa aktarın; öğrenciler için okuma karnelerini PDF olarak oluşturun.'],['shield','Güvenli & Kurumsal Altyapı','Verileriniz güvende, okulunuza özel ve kesintisiz kullanım.']];
const row=document.querySelector('#feature-row');row.innerHTML=features.map(([icon,title,desc],i)=>`<button class="feature ${i===0?'active':''}" aria-pressed="${i===0}" data-index="${i}"><div><svg aria-hidden="true"><use href="#${icon}"/></svg><h3>${title}</h3><p>${desc}</p><span class="arrow">→</span></div></button>`).join('');
function selectCard(n,scroll=false){document.querySelectorAll('.feature').forEach((el,i)=>{el.classList.toggle('active',i===n);el.setAttribute('aria-pressed',i===n)});document.querySelectorAll('.dots button').forEach((el,i)=>el.classList.toggle('current',i===Math.floor(n/2)));if(scroll&&innerWidth<761)row.scrollTo({left:row.children[n].offsetLeft-30,behavior:'smooth'})}row.addEventListener('click',e=>{const card=e.target.closest('.feature');if(card)selectCard(Number(card.dataset.index))});document.querySelectorAll('[data-card]').forEach(b=>b.onclick=()=>selectCard(Number(b.dataset.card),true));
const modal=document.querySelector('#modal'),content=document.querySelector('#modal-content');
let modalTrigger=null;
let loginRequest=null;
function showLoginChoices(focus=false){
 modal.classList.add('login-modal');
 content.innerHTML=`<div class="login-brand"><svg aria-hidden="true"><use href="#book"/></svg> Rafly</div><h2 id="modal-title">Giriş Yap</h2><p class="login-intro">Devam etmek için giriş türünüzü seçin.</p><div class="login-roles"><button type="button" class="login-role" data-role="student"><svg aria-hidden="true"><use href="#book"/></svg><strong>Öğrenci Giriş</strong><span>Kitaplarınızı ve işlemlerinizi takip edin.</span><b aria-hidden="true">→</b></button><button type="button" class="login-role" data-role="staff"><svg aria-hidden="true"><use href="#users"/></svg><strong>Personel Giriş</strong><span>Kütüphanenizi ve kayıtlarınızı yönetin.</span><b aria-hidden="true">→</b></button></div>`;
 content.querySelectorAll('[data-role]').forEach(button=>button.onclick=()=>showLoginForm(button.dataset.role));
 if(focus)content.querySelector('[data-role]').focus();
}
function showLoginForm(role){
 const student=role==='student';
 content.innerHTML=`<button type="button" class="login-back">← Giriş türünü değiştir</button><h2 id="modal-title">${student?'Öğrenci Giriş':'Personel Giriş'}</h2><p class="login-intro">Hesap bilgilerinizle devam edin.</p><form id="login-form">${student?`<fieldset class="school-level"><legend>Okul Seviyesi</legend><div class="school-level-options">${['İlkokul','Ortaokul','Lise','Hazırlık','Diğer'].map((level,index)=>`<label class="school-level-option"><input type="radio" name="schoolLevel" value="${index}" required><span>${level}</span></label>`).join('')}</div></fieldset>`:''}<label for="school-code">Okul kodu</label><input id="school-code" name="schoolCode" required maxlength="60" autocomplete="organization" placeholder="Okul kodunuzu girin"><label for="login-identity">${student?'Öğrenci numarası':'E-posta adresi'}</label><input id="login-identity" name="identity" type="${student?'text':'email'}" required maxlength="254" autocomplete="username" placeholder="${student?'Öğrenci numaranızı girin':'E-posta adresinizi girin'}"><label for="login-password">Şifre</label><div class="password-field"><input id="login-password" name="password" type="password" required autocomplete="current-password" placeholder="Şifrenizi girin"><button type="button" id="toggle-password" aria-controls="login-password" aria-label="Şifreyi göster" aria-pressed="false">Göster</button></div><button type="submit" class="primary login-submit">Giriş Yap →</button><p id="login-status" role="status" hidden></p></form><a class="login-help" href="support.html#troubleshoot">Giriş yaparken yardıma mı ihtiyacınız var? →</a>`;
 content.querySelector('.login-back').onclick=()=>showLoginChoices(true);
 const password=content.querySelector('#login-password');
 content.querySelector('#toggle-password').onclick=event=>{const show=password.type==='password';password.type=show?'text':'password';event.currentTarget.textContent=show?'Gizle':'Göster';event.currentTarget.setAttribute('aria-pressed',String(show));event.currentTarget.setAttribute('aria-label',show?'Şifreyi gizle':'Şifreyi göster');};
 content.querySelector('#login-form').onsubmit=async event=>{
  event.preventDefault();
  if(loginRequest)return;
  const form=event.currentTarget;
  const status=form.querySelector('#login-status');
  const fields=Object.fromEntries(new FormData(form));
  const controller=new AbortController();
  loginRequest=controller;
  const timeout=setTimeout(()=>controller.abort(),30000);
  const controls=[...content.querySelectorAll('input, button')];
  controls.forEach(control=>control.disabled=true);
  status.hidden=false;status.textContent='Giriş yapılıyor…';
  try {
   const destination=await window.raflyAuth.login(role,fields,controller.signal);
   if(modal.open&&!controller.signal.aborted)window.location.assign(destination);
  } catch(error) {
   if(modal.open)status.textContent=error.name==='AbortError'?'İstek zaman aşımına uğradı. Lütfen tekrar deneyin.':error instanceof TypeError?'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.':error.message;
  } finally {
   clearTimeout(timeout);password.value='';controls.forEach(control=>control.disabled=false);
   if(loginRequest===controller)loginRequest=null;
  }
 };
 content.querySelector('#school-code').focus();
}
const messages={video:['Rafly Tanıtımı','Tanıtım videomuz yakında burada olacak.']};
document.querySelectorAll('[data-modal]').forEach(button=>button.onclick=()=>{
 modalTrigger=button;modal.setAttribute('aria-labelledby','modal-title');
 if(button.dataset.modal==='login'){showLoginChoices();modal.showModal();content.querySelector('[data-role]').focus();return;}
 modal.classList.remove('login-modal');const [title,body]=messages[button.dataset.modal];content.innerHTML=`<h2 id="modal-title">${title}</h2><p>${body}</p><button class="primary" id="explore">Özellikleri İncele →</button>`;
 content.querySelector('#explore').onclick=()=>{modal.close();document.querySelector('#features').scrollIntoView({behavior:'smooth'})};modal.showModal();
});
document.querySelector('.close').onclick=()=>modal.close();
modal.addEventListener('click',event=>{if(event.target===modal){const r=modal.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)modal.close();}});
modal.addEventListener('close',()=>{loginRequest?.abort();loginRequest=null;content.replaceChildren();modal.classList.remove('login-modal');modalTrigger?.focus();});
document.querySelectorAll('.navlinks a').forEach(a=>a.onclick=()=>{document.querySelectorAll('.navlinks a').forEach(el=>el.classList.remove('active'));a.classList.add('active')});
