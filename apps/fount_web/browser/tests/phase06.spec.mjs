import {test, expect} from '@playwright/test';
import {readFileSync} from 'node:fs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 06 Browser Fixture\nAuthor: Fount\n\nINT. KITCHEN - MORNING\n\nMARA sets an unopened envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board, one hand around a brass key.\n\nNORA\nThe train is late.\n\nOWEN\nThat's what you wanted.\n\nINT. INTERVIEW ROOM - LATER\n\nNora keeps her hands flat on the table.\n\nNORA\nI didn't miss anything.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Owner token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createJourney(page, journey, key) {
  await page.goto('/projects/new');
  await page.getByLabel('Project title').fill(`Browser ${journey}`);
  await page.getByLabel('Project key').fill(key);
  await page.getByLabel('Journey').selectOption(journey);
  await page.getByLabel('Or Fountain source').fill(fixture);
  await page.getByRole('button', {name: 'Create Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  const runId = page.url().match(/\/runs\/([0-9a-f-]+)\/setup$/)[1];
  await page.getByRole('button', {name: 'Launch / resume durable worker'}).click();
  return runId;
}

async function chooseRoute(page, runId) {
  await page.goto(`/runs/${runId}/decisions`);
  const route = page.getByRole('button', {name: /Commit now|route-a/i}).first();
  await expect(route).toBeVisible();
  await route.click();
}

async function waitForCandidate(page, runId, needle) {
  await page.goto(`/runs/${runId}/review`);
  await expect(page.locator('pre.script').last()).toContainText(needle, {timeout: 60_000});
}

test('U01 brief to checked opening candidate, export, canon base unchanged', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'opening', `u01-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'INT. LOCKED ROOM - NIGHT');
  await expect(page.locator('pre.script').first()).not.toContainText('INT. LOCKED ROOM - NIGHT');
  await expect(page.locator('p.status')).toContainText('stage: deliver', {timeout: 60_000});

  await page.goto(`/runs/${runId}/exports`);
  await page.getByRole('button', {name: 'Publish / retry bundle'}).click();
  const fountain = page.getByRole('link', {name: 'Download'}).first();
  await expect(fountain).toBeVisible({timeout: 60_000});
  const [download] = await Promise.all([page.waitForEvent('download'), fountain.click()]);
  expect(await download.suggestedFilename()).toBeTruthy();
  expect(readFileSync(await download.path(), 'utf8')).toContain('INT. LOCKED ROOM - NIGHT');
});

test('U02 protected reveal repairs then exact human approval survives refresh', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'reveal', `u02-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'The stationmaster locks the evidence cabinet');
  await expect(page.locator('pre.script').last()).toContainText('departure board');

  await page.goto(`/runs/${runId}/decisions`);
  const approve = page.getByRole('button', {name: /Accept candidate|approve/i}).first();
  await expect(approve).toBeVisible({timeout: 60_000});
  await approve.click();
  await page.reload();
  await page.goto(`/runs/${runId}/timeline`);
  await expect(page.locator('pre').filter({hasText: '"outcome": "accepted"'})).toBeVisible({timeout: 60_000});
  await page.goto(`/runs/${runId}/exports`);
  await page.getByRole('button', {name: 'Publish / retry bundle'}).click();
  await expect(page.locator('p.status')).toContainText('completed_accepted', {timeout: 60_000});
});

test('U03 selected-scene dialogue records configured service approval identity', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'dialogue', `u03-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'If you missed it, you were meant to.');
  await page.goto(`/runs/${runId}/timeline`);
  await expect(page.getByText(/demo-service/).first()).toBeVisible({timeout: 60_000});
  await expect(page.locator('pre').filter({hasText: '"outcome": "accepted"'})).toBeVisible({timeout: 60_000});
  await page.goto(`/runs/${runId}/exports`);
  await page.getByRole('button', {name: 'Publish / retry bundle'}).click();
  await expect(page.locator('p.status')).toContainText('completed_accepted', {timeout: 60_000});
});

test('U04 duplicate tabs replay exact decision and unauthenticated client is denied', async ({browser}) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  await login(first);
  const runId = await createJourney(first, 'opening', `u04-${Date.now()}`);
  const second = await context.newPage();
  await first.goto(`/runs/${runId}/decisions`);
  await second.goto(`/runs/${runId}/decisions`);
  const one = first.getByRole('button', {name: /Commit now|route-a/i}).first();
  const two = second.getByRole('button', {name: /Commit now|route-a/i}).first();
  await expect(one).toBeVisible();
  await expect(two).toBeVisible();
  await Promise.allSettled([one.click(), two.click()]);
  await expect(second.getByText(/idempotent replay|conflict\/stale form|No pending decisions/i).first()).toBeVisible();

  const outsider = await browser.newPage();
  await outsider.goto(`/runs/${runId}/timeline`);
  await expect(outsider).toHaveURL(/\/login$/);
  await context.close();
});

test('U05 control, unknown-cost and failure semantics are visible and keyboard reachable', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'opening', `u05-${Date.now()}`);
  await page.goto(`/runs/${runId}/timeline`);
  await expect(page.getByRole('button', {name: 'Pause'})).toBeVisible();
  await expect(page.getByText(/Missing provider cost remains unknown/)).toBeVisible();
  await expect(page.locator('p.status[aria-live="polite"]')).toBeVisible();
  await page.keyboard.press('Tab');
  await expect(page.locator(':focus')).toBeVisible();
  await page.getByLabel('Confirm permanent stop and fencing').check();
  await page.getByRole('button', {name: 'Stop'}).click();
  await expect(page.getByRole('status')).toContainText('Stop recorded');
});

test('H03-H05 integrated analysis survives review reconnect and stays candidate-only', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'analysis', `h03-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'If you missed it, you were meant to.');
  await expect(page.locator('p.status')).toContainText('stage: deliver', {timeout: 60_000});

  await expect(page.getByRole('heading', {name: 'Prewrite Intelligence'}).first()).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Revision Intelligence'}).first()).toBeVisible();
  await expect(page.getByText(/Status: (complete|partial)/).first()).toBeVisible({timeout: 60_000});
  await expect(page.getByRole('heading', {name: 'Semantic advisory checks'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Authoritative required checks'})).toBeVisible();
  await expect(page.getByText(/revision_intelligence/).first()).toBeVisible();
  await expect(page.locator('pre.script').first()).toContainText("I didn't miss anything.");
  await expect(page.locator('pre.script').first()).not.toContainText('If you missed it, you were meant to.');

  await page.reload();
  await expect(page.getByText(/Status: (complete|partial)/).first()).toBeVisible({timeout: 60_000});
  await expect(page.getByText(/analysis_run_id/).first()).toBeVisible();

  await page.goto(`/runs/${runId}/timeline`);
  await expect(page.getByText(/Analysis service:.*Deterministic Sandbox/)).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Prewrite Intelligence'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Revision Intelligence'})).toBeVisible();
});


test('Create Run submits over HTTP when JavaScript is unavailable', async ({browser}) => {
  const context = await browser.newContext({javaScriptEnabled: false});
  const page = await context.newPage();
  await login(page);
  await page.goto('/projects/new');
  await page.getByLabel('Project key', {exact: true}).fill(`native-${Date.now()}`);
  await page.getByRole('button', {name: 'Create Run', exact: true}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  await expect(page.getByText('Run setup', {exact: true})).toBeVisible();
  await context.close();
});

test('LiveView falls back to long polling when WebSocket connections fail', async ({browser}) => {
  const context = await browser.newContext();
  await context.addInitScript(() => {
    const NativeWebSocket = window.WebSocket;
    window.WebSocket = class extends NativeWebSocket {
      constructor(url, protocols) {
        super(url.replace(/:\d+\/live\/websocket/, ':1/live/websocket'), protocols);
      }
    };
  });
  const page = await context.newPage();
  await login(page);
  const runId = await createJourney(page, 'opening', `longpoll-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'INT. LOCKED ROOM - NIGHT');
  await context.close();
});
