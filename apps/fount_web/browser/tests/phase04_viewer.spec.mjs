import {test, expect} from '@playwright/test';
import {importProject, createTask, openWorkspace, reloadWorkspace} from './workspace_helpers.mjs';
const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 04 Viewer <Fixture>\nAuthor: Zoë\n\n# ACT ONE\n\nINT. CAFÉ - MORNING #1#\n\nMARA sets an envelope beside the coffee maker. <script>not executable</script>\n\nMARA\nI said I would wait.\n\nOWEN ^\nAnd I said the train would not.\n\n[[private note]]\n\nEXT. TRAIN PLATFORM - NIGHT #2#\n\nNORA waits under the departure board.\n\nNORA\nThe train is late.\n\nINT. INTERVIEW ROOM - LATER\n\nNora keeps her hands flat on the table.\n\nNORA\nI didn't miss anything.\n`;
async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('.phx-connected')).toBeVisible();
}

test('U01-U05 project viewer preserves escaped IR, dual dialogue, scene focus and exact anchors', async ({page}) => {
  await login(page);
  const key = await importProject(page, `viewer-${Date.now()}`, fixture);
  await expect(page.locator('.screenplay-title-page')).toContainText('Phase 04 Viewer <Fixture>');
  await expect(page.locator('.screenplay-dual')).toBeVisible();
  await expect(page.locator('.screenplay')).toContainText('<script>not executable</script>');
  await expect(page.locator('.screenplay script')).toHaveCount(0);
  const links = page.locator('#scene-outline [data-scene-link]');
  await expect(links).toHaveCount(3);
  await page.locator('#reader-scenes > summary').click();
  await links.nth(1).click();
  const id = await links.nth(1).getAttribute('data-scene-link');
  await expect(page.locator(`#scene-${id}`)).toBeFocused();
  await expect(links.nth(1)).toHaveAttribute('aria-current', 'location');
  await reloadWorkspace(page);
  await expect(links.nth(1)).toHaveAttribute('aria-current', 'location');
  await page.locator('#reader-scenes > summary').click();
  await links.first().focus();
  await page.keyboard.press('ArrowDown');
  await expect(links.nth(1)).toBeFocused();
  await openWorkspace(page, `/p/${key}/cast`);
  await expect(page.locator('#unverified-source-cues')).toContainText('MARA');
  await expect(page.locator('.compact-character-card')).toHaveCount(0);
});

test('U04 narrow reduced-motion source reading remains legible and does not inject markup', async ({page}) => {
  await page.setViewportSize({width:360,height:800});
  await page.emulateMedia({reducedMotion:'reduce'});
  await login(page);
  await importProject(page, `viewer-narrow-${Date.now()}`, fixture);
  await page.evaluate(() => {
    window.sceneScrollCalls=[];
    const original=Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView=function(options) {window.sceneScrollCalls.push(options.behavior); return original.call(this,options)};
  });
  await page.locator('#reader-scenes > summary').click();
  await page.locator('#scene-outline [data-scene-link]').first().click();
  expect(await page.evaluate(()=>window.sceneScrollCalls)).toEqual(['auto']);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
  await expect(page.locator('.screenplay script')).toHaveCount(0);
});

test('U06/U08 task Sources keep proposed work distinct and reject arbitrary revision selection', async ({page}) => {
  await login(page);
  const key=await importProject(page, `viewer-candidate-${Date.now()}`, fixture);
  await createTask(page,key,'opening');
  await openWorkspace(page, `/p/${key}/activity/task-1/decisions`);
  await page.getByRole('button',{name:/Commit now|route-a/i}).first().click();
  await openWorkspace(page, `/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').last()).toContainText('INT. LOCKED ROOM - NIGHT',{timeout:60000});
  await openWorkspace(page, `/p/${key}/source/task-1`);
  await page.getByRole('link',{name:'Proposal 1',exact:true}).click();
  await expect(page.locator('.screenplay')).toContainText('INT. LOCKED ROOM - NIGHT');
  await reloadWorkspace(page);
  await expect(page.locator('.screenplay')).toContainText('INT. LOCKED ROOM - NIGHT');
  await openWorkspace(page, `/p/${key}/source/task-1?view=accepted:00000000-0000-0000-0000-000000000000`);
  await expect(page.getByText(/stale or no longer bound/)).toBeVisible();
  await expect(page.locator('.screenplay')).not.toContainText('INT. LOCKED ROOM - NIGHT');
  await openWorkspace(page, `/p/${key}`);
  await expect(page.locator('.screenplay')).not.toContainText('INT. LOCKED ROOM - NIGHT');
});

test('U04/U08 authenticated saved pages are readable without JavaScript and outsider is denied', async ({browser}) => {
  const context=await browser.newContext(); const page=await context.newPage();
  await login(page);
  const key=await importProject(page, `viewer-nojs-${Date.now()}`, fixture);
  const readContext=await browser.newContext({javaScriptEnabled:false,storageState:await context.storageState()});
  const reader=await readContext.newPage();
  await reader.goto(`/p/${key}`);
  await expect(reader.locator('.screenplay')).toContainText('MARA sets an envelope');
  await reader.locator('#reader-scenes > summary').click();
  await reader.locator('#scene-outline a').first().click();
  await expect(reader).toHaveURL(/scene=1/);
  const outsider=await browser.newPage(); await outsider.goto(`/p/${key}`);
  await expect(outsider).toHaveURL(/\/login$/);
  await readContext.close(); await context.close(); await outsider.close();
});
