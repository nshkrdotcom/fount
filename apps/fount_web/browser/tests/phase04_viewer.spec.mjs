import {test, expect} from '@playwright/test';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 04 Viewer <Fixture>\nAuthor: Zoë\n\n# ACT ONE\nINT. CAFÉ - MORNING #1#\n\nMARA sets an envelope beside the coffee maker. <script>not executable</script>\n\nMARA\nI said I would wait.\n\nOWEN ^\nAnd I said the train would not.\n\n[[private note]]\n\nEXT. TRAIN PLATFORM - NIGHT #2#\n\nNORA waits under the departure board.\n\nNORA\nThe train is late.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Owner token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createRun(page, key, journey = 'opening', source = fixture) {
  await page.goto('/projects/new');
  await page.getByLabel('Project title').fill(`Phase 04 ${key}`);
  await page.getByLabel('Project key').fill(key);
  await page.getByLabel('Journey').selectOption(journey);
  await page.getByLabel('Or Fountain source').fill(source);
  await page.getByRole('button', {name: 'Create Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  return page.url().match(/\/runs\/([0-9a-f-]+)\/setup$/)[1];
}

async function launchAndChoose(page, runId) {
  await page.getByRole('button', {name: 'Launch / resume durable worker'}).click();
  await page.goto(`/runs/${runId}/decisions`);
  const route = page.getByRole('button', {name: /Commit now|route-a/i}).first();
  await expect(route).toBeVisible({timeout: 60_000});
  await route.click();
}

async function waitForCandidate(page, runId, needle) {
  await page.goto(`/runs/${runId}/review`);
  await expect(page.locator('pre.script').last()).toContainText(needle, {timeout: 60_000});
}

test('U01-U05 viewer renders escaped IR, analyzer indices, stable scenes and dialog keyboard behavior', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `viewer-foundation-${Date.now()}`);
  await page.goto(`/runs/${runId}/viewer`);

  await expect(page.getByRole('heading', {name: /Phase 04 viewer/i})).toBeVisible();
  await expect(page.locator('.screenplay-title-page')).toContainText('Phase 04 Viewer <Fixture>');
  await expect(page.locator('.screenplay-dual')).toBeVisible();
  await expect(page.locator('.screenplay')).toContainText('<script>not executable</script>');
  await expect(page.locator('.screenplay script')).toHaveCount(0);
  await expect(page.getByText(/Literal cue summaries only/)).toBeVisible();
  await expect(page.getByText(/derived reading approximation/).first()).toBeVisible();

  const firstSceneLink = page.locator('#scene-outline [data-scene-link]').first();
  const firstSceneId = await firstSceneLink.getAttribute('data-scene-link');
  await firstSceneLink.click();
  await expect(page.locator(`#scene-${firstSceneId}`)).toBeFocused();
  await firstSceneLink.focus();
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('#scene-outline [data-scene-link]').nth(1)).toBeFocused();

  const help = page.getByRole('button', {name: 'Revision identity details'});
  await help.focus();
  await help.click();
  const dialog = page.getByRole('dialog', {name: 'Revision identity'});
  await expect(dialog).toBeVisible();
  await page.keyboard.press('Tab');
  await expect(dialog.locator('button')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(help).toBeFocused();
});

test('U02/U07 narrow, dark, reduced-motion and reload retain the explicitly selected revision URL', async ({page}) => {
  await page.setViewportSize({width: 480, height: 900});
  await page.emulateMedia({colorScheme: 'dark', reducedMotion: 'reduce'});
  await login(page);
  const runId = await createRun(page, `viewer-layout-${Date.now()}`);
  await page.goto(`/runs/${runId}/viewer`);

  const columns = await page.locator('.workspace-grid').evaluate((node) => getComputedStyle(node).gridTemplateColumns);
  expect(columns.split(' ').length).toBeLessThanOrEqual(2);
  const bg = await page.locator('body').evaluate((node) => getComputedStyle(node).backgroundColor);
  expect(bg).not.toBe('rgba(0, 0, 0, 0)');

  const selected = await page.getByLabel('Displayed revision').inputValue();
  await page.getByLabel('Filter character index').fill('MARA');
  await page.getByRole('button', {name: 'Apply view'}).click();
  await expect(page).toHaveURL(/view=/);
  await page.evaluate(() => { window.liveSocket.disconnect(); window.liveSocket.connect(); });
  await expect(page.locator('#scene-outline [data-scene-link]').first()).toBeVisible();
  await page.reload();
  await expect(page.getByLabel('Displayed revision')).toHaveValue(selected);
  await expect(page.getByText('MARA', {exact: true}).first()).toBeVisible();
});

test('U06/U08 candidate diff is Run-bound and stale arbitrary IDs fall back truthfully', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `viewer-candidate-${Date.now()}`, 'opening');
  await launchAndChoose(page, runId);
  await waitForCandidate(page, runId, 'INT. LOCKED ROOM - NIGHT');

  await page.goto(`/runs/${runId}/viewer`);
  const candidate = page.getByLabel('Displayed revision').locator('option', {hasText: 'Selected candidate'});
  await expect(candidate).toHaveCount(1);
  const candidateToken = await candidate.getAttribute('value');
  await page.getByLabel('Displayed revision').selectOption(candidateToken);
  await page.getByRole('button', {name: 'Apply view'}).click();
  await expect(page.locator('.screenplay')).toContainText('INT. LOCKED ROOM - NIGHT');
  await expect(page.locator('.diff-viewer')).toBeVisible();
  await expect(page.getByText(/Candidate — canon unchanged/)).toBeVisible();

  const selectedRevision = await page.locator('.workspace-controls code').first().textContent();
  await page.reload();
  await expect(page.locator('.workspace-controls code').first()).toHaveText(selectedRevision);

  await page.goto(`/runs/${runId}/viewer?view=accepted:00000000-0000-0000-0000-000000000000`);
  await expect(page.getByText(/stale or is not bound to this Run/)).toBeVisible();
  await expect(page.getByText('Run base', {exact: true}).first()).toBeVisible();
});

test('U08 accepted revision is separately labeled after exact approval and outsider is denied', async ({browser}) => {
  const context = await browser.newContext();
  const page = await context.newPage();
  await login(page);
  const runId = await createRun(page, `viewer-accepted-${Date.now()}`, 'reveal');
  await launchAndChoose(page, runId);
  await waitForCandidate(page, runId, 'The stationmaster locks the evidence cabinet');

  await page.goto(`/runs/${runId}/decisions`);
  const approve = page.getByRole('button', {name: /Accept candidate|approve/i}).first();
  await expect(approve).toBeVisible({timeout: 60_000});
  await approve.click();

  await page.goto(`/runs/${runId}/viewer`);
  const accepted = page.getByLabel('Displayed revision').locator('option', {hasText: 'Accepted revision'}).first();
  await expect(accepted).toBeVisible({timeout: 60_000});
  const acceptedToken = await accepted.getAttribute('value');
  await page.getByLabel('Displayed revision').selectOption(acceptedToken);
  await page.getByRole('button', {name: 'Apply view'}).click();
  await expect(page.getByText('Accepted canonical revision')).toBeVisible();

  const outsider = await browser.newPage();
  await outsider.goto(`/runs/${runId}/viewer`);
  await expect(outsider).toHaveURL(/\/login$/);
  await context.close();
});

test('U04/U08 server-rendered viewer remains readable without JavaScript', async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false});
  const page = await context.newPage();
  await login(page);
  const runId = await createRun(page, `viewer-nojs-${Date.now()}`);
  await page.goto(`/runs/${runId}/viewer`);
  await expect(page.locator('.screenplay')).toContainText('MARA sets an envelope');
  const href = await page.locator('#scene-outline a').first().getAttribute('href');
  expect(href).toMatch(/^#scene-/);
  await page.locator('#scene-outline a').first().click();
  await expect(page).toHaveURL(/#scene-/);
  await context.close();
});
