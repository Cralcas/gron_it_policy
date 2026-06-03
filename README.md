# gron_it_policy

<h1>Info och tider</h1>
Varje dag kör vi:

<ul>
  <li>
    12.00 Sprint Planning + Daily Scrum
  </li>
  <li>
    17.00 Sprint Review + Sprint Retrospective
  </li>
</ul>

<b>Onsdagens lektion sker i Aula 1 på Axel Weudel kl. 08.30.</b>
<ul>
  <li>
    If ($allaPåPlats -eq "true") {'Sprint 2 Planning + Scrum på lektion'}
  </li>
  <li>
    Else {'Sprint 2 Planning + Scrum vid 12.00 som vanligt'}
  </li>
</ul>

<B>Presentation Torsdag - Presentationen ska genomföras 15.00 i R0. Vi samlas ca 14.00 utanför R0 för tid för reflektion.</B>
<hr>

<h1>Product Vision</h1>

<h2>Visionen</h2>
Vi vill skapa en enkel och användbar PowerShell-lösning för Grön IT som hjälper organisationer att minska onödig energiförbrukning. Målet är att skapa ett fungerande exempel som visar hur automatisering kan bidra till ett mer hållbart IT-arbete.

<h2>Ramar och begränsningar</h2>
Projektet startar fredag och ska vara helt klart för demonstration torsdag kl. 14:00. Lösningen måste baseras på scripting (PowerShell/Bash) och versionshanteras i GitHub.

<h2>Vad måste lösningen klara?</h2>
Produkten ska kunna inventera datorer i ett nätverk med hjälp av WMI/CIM, identifiera maskiner som verkar vara inaktiva och logga relevant information. Lösningen ska även kunna schemalägga eller trigga avstängning/viloläge för att minska elförbrukningen utan att störa aktiva användare.

<hr>

<h1>Intruktioner för att köra script</h1>
<ol>
  <li>
    <ul>Skapa en .env-fil i mappen "src" med följande kod, var noga med att fylla i egna uppgifter:
      <li>GREENIT_USER=namnet på adminkonto</li>
      <li>GREENIT_PASSWORD=lösenord för adminkontot</li>
      <li>DISCORD_WEBHOOK_URL=adressen till utvald discord webhook</li>
    </ul>
  </li>
  <li>På rad16 i Networkinventory.ps1: Ange det subnätverk som skall skannas </li>
  <li>På rad 19 i Networkinventory.ps1: Ange det spann av subnätverkets adresser som skall skannas</li>
  <li>Spara och kör script.</li>
</ol>
<hr>

<hr>

<hr>

<h1>Sprint 1</h1>

<h2>Sprint 1 Planning </h2>
Produktägare och utvecklare gick igenom och klassificerade issues efter produktens behov.
Issues med klassficiseringen "Must have" prioriteras. Sprintmålet är att skapa en fungerande prototyp.

<ul><h3>Fördelning Sprint 1</h3>
  <li>Maxiprogramm - https://github.com/Cralcas/gron_it_policy/issues/4</li>
  <li>Gustafssoon - https://github.com/Cralcas/gron_it_policy/issues/5, https://github.com/Cralcas/gron_it_policy/issues/7</li>
  <li>AntonEI - https://github.com/Cralcas/gron_it_policy/issues/8, https://github.com/Cralcas/gron_it_policy/issues/9,  https://github.com/Cralcas/gron_it_policy/issues/16, https://github.com/Cralcas/gron_it_policy/issues/20</li>
  <li>dnal0 - https://github.com/Cralcas/gron_it_policy/issues/13, https://github.com/Cralcas/gron_it_policy/issues/17,</li>
</ul>

<h2>Sprint Review 1 </h2>
Alla som planerats genomfördes under dagen. En issue kunde strykas då det visades sig att samma problem löstes i en annan issue.
VM-miljön diskuterades och en smärre förenkling godtogs. Gruppen skapade en ny issue angående risken för och kontroll av dubbel kod.

<h2>Sprint Retrospective 1</h2>
Tider för ceremonier diskuterades, lite svårigheter att få det att passa hela gruppen till 100%. Men gruppen beslutade att de tider som etablerats också gäller tills vidare.
Gruppen identifierade information som Scrum Master behöver undersöka; Hur ska presentationen se ut? Hur ser arbetet under onsdagen och Sprint 3 ut? Och hur ska Scrum Master dokumentera sitt arbete?
<hr>

<hr>
<h1>Sprint 2</h1>

<h2>Sprint 2 Planning </h2>
Då alla "must have" issues blev färdiga under Sprint 1 fokuserar Sprint 2 på att skapa mervärde och att implementera "nice to have" features.
Det uppmärksammades också att flera user stories redan var uppfyllda i den kod som producerats. Så dessa rensades ut från produktbackloggen.

<ul><h3>Fördelning Sprint 2</h3>
  <li>Gralcas - https://github.com/Cralcas/gron_it_policy/issues/12, https://github.com/Cralcas/gron_it_policy/issues/29</li>
  <li>Gustafssoon - https://github.com/Cralcas/gron_it_policy/issues/6, https://github.com/Cralcas/gron_it_policy/issues/24</li>
  <li>dnal0 - https://github.com/Cralcas/gron_it_policy/issues/15, https://github.com/Cralcas/gron_it_policy/issues/22,</li>
  <li>DrWeremoth - https://github.com/Cralcas/gron_it_policy/issues/10,</li>
</ul>

<h2>Sprint Review 2 </h2>
Under dagens arbete visade det sig att några issues tog längre tid än planerat och några behövde förläggas till ett senare skede i utveckligen.
Gruppen valde därför att föra tillbaka några issues till produktbackloggen. Majoriteten av dagens sprint gick dock enligt plan.

<h2>Sprint Retrospective 2</h2>
Inga funderingar eller förbättringar dryftades. Gruppen upplevde inga problem runt Sprint 2.
<hr>

<hr>
<h1>Sprint 3</h1>

<h2>Sprint 3 Planning </h2>
Gruppen hann inte med planering för Sprint 3 då den fasta tiden för mötet låg mer eller mindre runt lektionstid. Utvecklare och produktägare tog det successivt under sprintens arbete istället.
Målet med sprinten handlade om att förfina, förbättra, rensa ur och iterera på kod. Samt säkerhet. Nya issues tillfördes i form av user stories.

<ul><h3>Fördelning Sprint 3</h3>
  <li>Gralcas - https://github.com/Cralcas/gron_it_policy/issues/12, https://github.com/Cralcas/gron_it_policy/issues/29, https://github.com/Cralcas/gron_it_policy/issues/35</li>
  <li>Maxiprogramm - https://github.com/Cralcas/gron_it_policy/issues/37</li>
  <li>Gustafssoon - https://github.com/Cralcas/gron_it_policy/issues/24, https://github.com/Cralcas/gron_it_policy/issues/31, https://github.com/Cralcas/gron_it_policy/issues/40, https://github.com/Cralcas/gron_it_policy/issues/43</li>
  <li></li>
</ul>

<h2>Sprint Review 3 </h2>
Gruppen hade en mycket effektiv sprint. Koden är numera uppdelad i moduler, hastigheten har ökats, återupprepad kod har rensats ur och koden har formaterats och kan nu hantera svenska tecken ordentligt. Allting som planerats blev avklarat förutom issue https://github.com/Cralcas/gron_it_policy/issues/30 som vi beslutade att inte genomföra.

<h2>Sprint Retrospective 3</h2>
Att sprintplaneringen uteblev upplevdes inte som ett stort problem. Men gruppen kände också att strukturen på arbetet blev lite lidande. Arbetsfördelningen blev inte riktigt lika tydlig och några kände att de tog på sig för mycket ansvar. Något att ha med sig till i framtida sprints.
<hr>
