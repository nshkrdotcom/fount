import {test, expect} from '@playwright/test';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const artifactRoot = process.env.FOUNT_ARTIFACT_ROOT;

const fountain = `Title: WINDOW LIGHT\nAuthor: Browser Fixture\n\nINT. KITCHEN - NIGHT\n\nMARA opens the window.\n\nMARA\nLeave it open.\n\nEXT. PORCH - DAWN\n\nELI waits with two coffees.\n`;
const fdx = `<FinalDraft><Content><Paragraph Type="Scene Heading"><Text>EXT. PORCH - DAWN</Text></Paragraph><Paragraph Type="Action"><Text>Eli waits.</Text></Paragraph></Content><TagData/></FinalDraft>`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('.phx-connected')).toBeVisible();
}

async function capture(page, name) {
  if (!artifactRoot) return;
  await page.screenshot({path: `${artifactRoot}/${name}.png`, fullPage: true});
}

async function importFixture(page, name, body, mimeType = 'text/plain') {
  await page.goto('/new');
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('input[type=file]').setInputFiles({name, mimeType, buffer: Buffer.from(body)});
  await page.getByRole('button', {name: 'Preview import'}).click();
  await expect(page.getByRole('heading', {name})).toBeVisible();
  await page.getByRole('button', {name: 'Open screenplay'}).click();
  await expect(page).toHaveURL(/\/p\/[a-z0-9-]+$/);
}

function noMachineIdentity(text) {
  expect(text).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i);
  expect(text).not.toMatch(/sha-?256/i);
}

test('UX01 import reaches real pages before any workflow setup and keeps ordinary UI human-readable', async ({page}) => {
  await page.setViewportSize({width: 1440, height: 900});
  await login(page);
  await expect(page.getByRole('heading', {name: /Bring your pages|What are you working on/})).toBeVisible();
  await expect(page.getByText(/None of these actions starts AI work/)).toBeVisible();

  await capture(page, 'ux01-desktop-arrival');
  await importFixture(page, 'window-light.fountain', fountain);
  await expect(page.getByText('WINDOW LIGHT', {exact: true}).first()).toBeVisible();
  await expect(page.locator('.screenplay')).toContainText('INT. KITCHEN - NIGHT');
  await expect(page.locator('.screenplay')).toContainText('Leave it open.');
  await expect(page.getByText('Current draft', {exact: true}).first()).toBeVisible();
  noMachineIdentity(await page.locator('main').innerText());

  const about = page.locator('#about-screenplay');
  await expect(about).not.toHaveAttribute('open', '');
  await about.locator(':scope > summary').click();
  await expect(about.getByText('Script facts', {exact: true})).toBeVisible();
  await expect(about.locator('.script-facts')).not.toHaveAttribute('open', '');
  await about.locator('.script-facts > summary').click();
  await expect(about.getByText('2', {exact: true}).first()).toBeVisible();
  await capture(page, 'ux01-desktop-import-reading');

  await page.goto('/new');
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('input[type=file]').setInputFiles({name: 'porch.fdx', mimeType: 'application/xml', buffer: Buffer.from(fdx)});
  await page.getByRole('button', {name: 'Preview import'}).click();
  await expect(page.getByText('FDX', {exact: true})).toBeVisible();
  await page.getByRole('button',{name:'Open screenplay'}).click();
  await expect(page.locator('.screenplay')).toContainText('Eli waits.');
  await capture(page,'ux01-desktop-fdx-import');
});

test('UX01 blank starts with empty source; saving working pages never advances current screenplay', async ({page}) => {
  await login(page);
  await page.goto('/new');
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByRole('button', {name: 'Start writing'}).click();
  await expect(page).toHaveURL(/\/p\/[a-z0-9-]+\/write$/);

  const editor = page.locator('#source-editor');
  await expect(editor).toHaveValue('');
  const source = `INT. EMPTY ROOM - DAY\n\nA WRITER starts with an actual page.\n`;
  await editor.fill(source);
  await page.getByRole('button', {name: 'Save working draft'}).click();
  await expect(page.locator('.authoring-status')).toContainText(/Saved working draft/i);
  await page.reload();
  await expect(editor).toHaveValue(source);

  await page.getByRole('link', {name: 'Reading'}).click();
  await expect(page.locator('.screenplay')).not.toContainText('A WRITER starts with an actual page.');
  await page.getByRole('link', {name: 'Working draft'}).click();
  await expect(page.locator('.screenplay')).toContainText('A WRITER starts with an actual page.');
  noMachineIdentity(await page.locator('main').innerText());
  await capture(page, 'ux01-desktop-blank-working');
});

test('UX01 example is provider-free, Help is reopenable, and phone navigation returns to the passage', async ({page}) => {
  await page.setViewportSize({width: 390, height: 844});
  await login(page);
  await page.getByRole('button', {name: 'Open LAST RETURN'}).click();
  await expect(page.locator('.screenplay')).toContainText('We stopped counting.');
  await expect(page.locator('#scene-outline [data-scene-link]')).toHaveCount(3);

  const second = page.locator('#scene-outline [data-scene-link]').nth(1);
  await page.locator('#reader-scenes > summary').click();
  await second.click();
  await expect(second).toHaveAttribute('aria-current', 'location');

  await page.getByRole('link', {name: 'Help', exact: true}).click();
  await expect(page.getByText('Optional example checklist')).toBeVisible();
  await page.getByRole('button', {name: 'Show dismissed hints again'}).click();
  await page.getByRole('link', {name: /Back to LAST RETURN/}).click();
  await expect(page.locator('#scene-outline [data-scene-link]').nth(1)).toHaveAttribute('aria-current', 'location');
  await capture(page, 'ux01-phone-return-to-passage');

  await page.setViewportSize({width: 768, height: 1024});
  await page.reload();
  await expect(page.locator('.reader-paper')).toBeVisible();
  await capture(page, 'ux01-tablet-reading');

  await page.evaluate(() => { document.documentElement.style.zoom = '2'; });
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(4);
});

test('UX01 shell, supplied About, no-task destinations, Help dismissal and phone writing remain usable', async ({page}) => {
  await login(page);
  await page.getByRole('button', {name:'Open LAST RETURN'}).click();
  await expect(page.locator('.screenplay')).toBeVisible();
  const key=new URL(page.url()).pathname.split('/')[2];
  await capture(page,'ux01-desktop-default-pages');
  await page.locator('.project-more > summary').focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('link',{name:'Project settings',exact:true})).toBeVisible();
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link',{name:'Analysis',exact:true})).toBeFocused();
  expect(await page.locator(':focus').evaluate(node=>getComputedStyle(node).outlineStyle)).not.toBe('none');
  await page.getByRole('link',{name:'Project settings',exact:true}).click();
  await page.getByLabel('Logline',{exact:true}).fill('A father returns a tape on the last night of a video shop.');
  await page.getByLabel('Synopsis',{exact:true}).fill('Mara and Eli pack the final cartons together.');
  await page.getByRole('button',{name:'Save project details'}).click();
  await expect(page.getByText('Project details saved.')).toBeVisible();
  await page.goto(`/p/${key}`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  const about=page.locator('#about-screenplay');
  await expect(about).not.toHaveAttribute('open','');
  await about.locator(':scope > summary').focus(); await page.keyboard.press('Enter');
  await expect(about.getByText('A father returns a tape on the last night of a video shop.')).toBeVisible();
  await expect(about.getByText('Mara and Eli pack the final cartons together.')).toBeVisible();
  await expect(about.locator('.script-facts')).not.toHaveAttribute('open','');
  await capture(page,'ux01-desktop-about-supplied');
  await page.getByRole('button',{name:'Dismiss',exact:true}).click();
  await expect(page.locator('.context-help')).toHaveCount(0);
  await page.getByRole('link',{name:'Help',exact:true}).click();
  await page.getByLabel('Search help').fill('Fountain');
  await expect(page.locator('.help-topic')).not.toHaveCount(0);
  await page.getByRole('button',{name:'Show dismissed hints again'}).click();
  await page.getByRole('link',{name:/Back to LAST RETURN/}).click();
  await expect(page.locator('.context-help')).toBeVisible();
  for (const destination of ['changes','analysis','read','exports','activity']) {
    await page.goto(`/p/${key}/${destination}`);
    await expect(page.getByText('No saved tasks yet. The screenplay is still fully available for reading and writing.')).toBeVisible();
    noMachineIdentity(await page.locator('main').innerText());
  }
  await page.goto(`/p/${key}/work`);
  await expect(page.locator('#creative-brief')).toBeVisible();
  await page.goto(`/p/${key}/notes`);
  await expect(page.getByRole('button', {name:'Save proposed note'})).toBeVisible();
  await page.goto(`/p/${key}`);
  await page.setViewportSize({width:1024,height:768}); await capture(page,'ux01-tablet-landscape');
  await page.setViewportSize({width:360,height:800});
  await page.locator('.project-more > summary').click();
  await expect(page.getByRole('link',{name:'History',exact:true})).toBeVisible();
  await capture(page,'ux01-phone-more');
  await page.getByRole('link',{name:'History',exact:true}).click();
  await expect(page.getByRole('heading',{name:'History',exact:true})).toBeVisible();
  await page.goto('/new'); await expect(page.locator('.phx-connected')).toBeVisible();
  await capture(page,'ux01-phone-entry');
  await page.getByRole('button',{name:'Start writing'}).click();
  const raw='INT. PHONE ROOM - DAY\n\nMARA types café 漢字 on her phone.\n';
  await page.locator('#source-editor').fill(raw);
  await page.getByRole('button',{name:'Save working draft',exact:true}).click();
  await expect(page.locator('.authoring-status')).toContainText('Saved working draft');
  await page.reload(); await expect(page.locator('#source-editor')).toHaveValue(raw);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
  await capture(page,'ux01-phone-writing-saved');
  await page.goto('/p/missing-project'); await expect(page).toHaveURL(/\/$/);
  await expect(page.getByText('That screenplay is not available in your workspace.')).toBeVisible();
  await capture(page,'ux01-no-project-returning-desk');
});


test('UX01 import errors preserve the desk and allow a later successful import',async ({page})=>{
  await login(page); await page.goto('/new'); await expect(page.locator('.phx-connected')).toBeVisible();
  await page.getByRole('button',{name:'Preview import'}).click();
  await expect(page.getByText('Choose a .fountain or .fdx screenplay first.')).toBeVisible();
  await page.locator('input[type=file]').setInputFiles({name:'broken.fdx',mimeType:'application/xml',buffer:Buffer.from('<FinalDraft><Content>')});
  await page.getByRole('button',{name:'Preview import'}).click();
  await expect(page.getByText('This Final Draft file could not be parsed. The project was not created.')).toBeVisible();
  await capture(page,'ux01-import-error');
  await importFixture(page,'recovered.fountain',fountain);
  await expect(page.locator('.screenplay')).toContainText('Leave it open.');
});


test('UX01 touch Help, menus and About work on a phone',async ({browser})=>{
  const context=await browser.newContext({hasTouch:true,isMobile:true,viewport:{width:390,height:844}});
  const page=await context.newPage(); await login(page);
  await page.getByRole('button',{name:'Open LAST RETURN'}).tap(); await expect(page.locator('.screenplay')).toBeVisible();
  await page.locator('#reader-scenes > summary').tap();
  await page.locator('#scene-outline [data-scene-link]').nth(1).tap();
  await page.getByRole('link',{name:'Help',exact:true}).tap();
  await expect(page.getByText('Optional example checklist')).toBeVisible();
  await capture(page,'ux01-phone-touch-help');
  await page.getByRole('link',{name:/Back to LAST RETURN/}).tap();
  await expect(page.locator('#scene-outline [data-scene-link]').nth(1)).toHaveAttribute('aria-current','location');
  await page.locator('#about-screenplay > summary').tap();
  await expect(page.locator('.script-facts')).not.toHaveAttribute('open','');
  await page.locator('.script-facts > summary').tap();
  await expect(page.getByText('Literal source facts only.',{exact:false})).toBeVisible();
  await capture(page,'ux01-phone-touch-about');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
  const targets=await page.locator('.project-tabs > a, .project-more > summary').evaluateAll(nodes=>nodes.map(node=>({name:node.textContent.trim(),height:node.getBoundingClientRect().height,width:node.getBoundingClientRect().width})));
  for (const target of targets) { expect(target.height, target.name).toBeGreaterThanOrEqual(24); }
  await context.close();
});
