import {test, expect} from '@playwright/test';
import {importProject, projectRunCount, hostFixture} from './workspace_helpers.mjs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fountain = `Title: Phase 08 Browser\nAuthor: Fount\n\nINT. CAFÉ - MORNING\n\nMARA puts the café receipt beside the coffee maker.\n\nMARA\nThe café opens before dawn.\n\nOWEN\nCount it twice.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nMARA waits under the departure board.\n\nMARA\nThe receipt is still in my pocket.\n`;
const fdx = `<FinalDraft><Content><Paragraph Type="Scene Heading"><Text>INT. FDX ROOM - DAY</Text></Paragraph><Paragraph Type="Action"><Text>Mara checks the imported page.</Text></Paragraph><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>The import is visible.</Text></Paragraph></Content><TagData/></FinalDraft>`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createProject(page, name) {
  return importProject(page, name, fountain);
}
async function openSection(page, key, section) {
  await page.goto(`/p/${key}${section ? '/' + section : ''}`);
  await expect(page.locator('.phx-connected')).toBeVisible();
}
async function createRead(page, key) {
  await openSection(page,key,'read');
  await page.getByLabel('Read title').fill('Receipt rehearsal');
  await page.getByRole('button',{name:'Save table-read material'}).click();
  await expect(page.locator('#table-read-workspace')).toBeVisible();
}

test('S01-S03 literal retrieval, cast and location facts stay source-bound', async ({page}) => {
  await login(page);
  const key=await createProject(page,`s01-${Date.now()}`);
  await page.locator('#script-search > summary').click();
  await page.getByLabel('Literal text').fill('café');
  await page.getByLabel('Maximum results').fill('1');
  await page.getByRole('button',{name:'Search selected source'}).click();
  await expect(page.locator('.script-search-results')).toContainText('1 result(s)');
  await expect(page.locator('.script-search-results')).toContainText(/Truncated|truncated/);
  const hit=page.locator('.script-search-results a').first();
  await expect(hit).toHaveAttribute('href',/#node-/);
  await hit.click();
  await expect(page).toHaveURL(/#node-/);
  await openSection(page,key,'cast');
  await expect(page.getByRole('heading',{name:'Cast',exact:true})).toBeVisible();
  await expect(page.locator('.character-grid')).toContainText('literal dialogue blocks');
  await expect(page.locator('.character-grid')).toContainText('unreviewed');
  await expect(page.locator('#semantic-assessment-status')).toContainText('Not configured');
  await openSection(page,key,'locations');
  await expect(page.getByRole('heading',{name:'Locations',exact:true})).toBeVisible();
  await expect(page.locator('.location-workspace')).toContainText('CAFÉ');
  await expect(page.locator('main')).toContainText('never source text or production scheduling');
  expect(projectRunCount(key)).toBe(0);
});

test('S04 authored notes remain proposed until deliberate Core acceptance and export preserves identity', async ({page}) => {
  await login(page);
  const key=await createProject(page,`s04-${Date.now()}`);
  await openSection(page,key,'notes');
  await page.getByLabel('Title').fill('Continuity');
  await page.getByRole('textbox',{name:'Note',exact:true}).fill('Keep the receipt visible.');
  await page.getByRole('button',{name:'Save proposed note'}).click();
  await expect(page.locator('.note-card')).toHaveCount(0);
  await expect(page.locator('main')).toContainText('The current screenplay is unchanged');
  await page.getByRole('button',{name:'Make this note change current'}).click();
  await expect(page.locator('.note-card')).toContainText('Keep the receipt visible.');
  const body=await page.evaluate(async url=>(await fetch(url)).json(),`/p/${key}/notes/export.json`);
  expect(body.kind).toBe('fount.authored_notes_export');
  expect(body.notes.some(n=>n.text==='Keep the receipt visible.')).toBe(true);
  expect(body.screenplay_id).toBeTruthy();
  expect(body.revision_id).toBeTruthy();
  expect(projectRunCount(key)).toBe(0);
});

test('S05 manual saved table reads retain timing, bookmark and human reaction without a Run', async ({page}) => {
  await login(page);
  const key=await createProject(page,`s05-${Date.now()}`);
  await createRead(page,key);
  const read=page.locator('#table-read-workspace');
  await expect(read).toContainText('not configured');
  await read.getByRole('button',{name:'Next',exact:true}).click();
  await read.getByRole('button',{name:'Bookmark current passage'}).click();
  await expect(read).toHaveAttribute('data-version','2');
  await page.reload();
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('.saved-read-row').first().click();
  await expect(read).toHaveAttribute('data-bookmark-index','1');
  await page.getByLabel('Reader',{exact:true}).fill('reader-a');
  await page.getByLabel('Reaction',{exact:true}).fill('The handoff landed clearly.');
  await page.getByRole('button',{name:'Save reaction'}).click();
  await expect(page.locator('.reaction-list')).toContainText('reader-a: The handoff landed clearly.');
  const url=await page.getByRole('link',{name:'Export saved table-read JSON'}).getAttribute('href');
  const data=await page.evaluate(async url=>(await fetch(url)).json(),url);
  expect(JSON.stringify(data)).toContain('The handoff landed clearly.');
  expect(projectRunCount(key)).toBe(0);
});

test('S07 supplied metadata and Fountain/FDX import fidelity remain factual', async ({page}) => {
  await login(page);
  const key=await createProject(page,`s07-${Date.now()}`);
  await openSection(page,key,'settings');
  await page.getByLabel('Synopsis').fill('Writer supplied synopsis.');
  await page.getByRole('button',{name:'Save project details'}).click();
  await openSection(page,key,'');
  await expect(page.locator('.reading-synopsis')).toHaveText('Writer supplied synopsis.');
  await page.locator('#about-screenplay > summary').click();
  await expect(page.locator('#about-screenplay')).toContainText('fountain');
  // Supplied legacy metadata remains stored; current reading does not invent a thumbnail.
  hostFixture('owner=System.fetch_env!("FOUNT_OWNER_ID"); {:ok,p}=FountWeb.Store.project_by_key(Fount.Repo,owner,System.fetch_env!("FOUNT_FIXTURE_KEY")); Ecto.Adapters.SQL.query!(Fount.Repo,"UPDATE fount_web_projects SET thumbnail_ref=$2 WHERE id=$1::text::uuid",[p["id"],"writer://thumb/phase08"]); {:ok,saved}=FountWeb.Store.project_by_key(Fount.Repo,owner,p["key"]); if saved["thumbnail_ref"] != "writer://thumb/phase08", do: raise("supplied metadata lost")',{FOUNT_FIXTURE_KEY:key});
  await page.goto('/new');
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('input[type=file]').setInputFiles({name:'phase08.fdx',mimeType:'application/xml',buffer:Buffer.from(fdx)});
  await page.getByRole('button',{name:'Preview import'}).click();
  await expect(page.locator('main')).toContainText('FDX');
  await page.getByRole('button',{name:'Open screenplay'}).click();
  await expect(page.locator('.screenplay')).toContainText('The import is visible.');
  await page.locator('#about-screenplay > summary').click();
  await expect(page.locator('#about-screenplay')).toContainText('fdx');
  await page.goto('/');
  await expect(page.locator('.project-row', {hasText:'phase08.fdx'}).first()).toContainText('Current draft');
});

for(const viewport of [{name:'desktop',width:1440,height:900},{name:'tablet',width:900,height:1000},{name:'phone',width:390,height:844}]) {
  test(`S08 ${viewport.name} current tools retain keyboard, focus and reconnect`,async ({page})=>{
    await page.setViewportSize(viewport);
    await login(page);
    const key=await createProject(page,`s08-${viewport.name}-${Date.now()}`);
    for(const section of ['', 'notes','cast','read']) {
      await openSection(page,key,section);
      expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
      await page.keyboard.press('Tab');
      await expect(page.locator(':focus')).toBeVisible();
      await page.evaluate(()=>window.liveSocket.disconnect());
      await page.evaluate(()=>window.liveSocket.connect());
      await expect.poll(()=>page.evaluate(()=>window.liveSocket.isConnected())).toBe(true);
    }
    await createRead(page,key);
    const clipped=await page.locator('#table-read-workspace button').evaluateAll(nodes=>nodes.some(n=>{const r=n.getBoundingClientRect();return r.left < -2 || r.right > innerWidth+2;}));
    expect(clipped).toBe(false);
    await page.screenshot({path:`${process.env.FOUNT_ARTIFACT_ROOT}/s08-${viewport.name}.png`,fullPage:true});
  });
}

test('S08 reduced motion retains manual table-read navigation',async ({page})=>{
  await page.emulateMedia({reducedMotion:'reduce'});
  await login(page);
  const key=await createProject(page,`s08-motion-${Date.now()}`);
  await createRead(page,key);
  await expect(page.locator('#table-read-workspace')).toHaveAttribute('data-scroll-mode','manual');
  await expect(page.getByRole('button',{name:'Start / pause'})).toBeDisabled();
  await page.getByRole('button',{name:'Next',exact:true}).click();
  await expect(page.locator('[data-read-turn].is-active-read-turn')).toHaveAttribute('data-index','1');
});

test('S05 two tabs preserve attempted bookmark and allow deliberate conflict recovery',async ({page,context})=>{
  await login(page);
  const key=await createProject(page,`s05-conflict-${Date.now()}`);
  await createRead(page,key);
  const second=await context.newPage();
  await openSection(second,key,'read');
  await second.locator('.saved-read-row').first().click();
  await page.getByRole('button',{name:'Next',exact:true}).click();
  await page.getByRole('button',{name:'Bookmark current passage'}).click();
  await expect(page.locator('#table-read-workspace')).toHaveAttribute('data-version','2');
  await second.getByRole('button',{name:'Bookmark current passage'}).click();
  await expect(second.locator('.table-read-conflict')).toBeVisible();
  await second.getByRole('button',{name:'Reload saved state instead'}).click();
  await expect(second.locator('#table-read-workspace')).toHaveAttribute('data-bookmark-index','1');
  await second.getByRole('button',{name:'Next',exact:true}).click();
  await second.getByRole('button',{name:'Bookmark current passage'}).click();
  await expect(second.locator('#table-read-workspace')).toHaveAttribute('data-version','3');
  await second.close();
});
