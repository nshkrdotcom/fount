import {test, expect} from '@playwright/test';
import {importProject, createTask} from './workspace_helpers.mjs';
import {readFileSync} from 'node:fs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 06 Browser Fixture\nAuthor: Fount\n\nINT. KITCHEN - MORNING\n\nMARA sets an unopened envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board, one hand around a brass key.\n\nNORA\nThe train is late.\n\nOWEN\nThat's what you wanted.\n\nINT. INTERVIEW ROOM - LATER\n\nNora keeps her hands flat on the table.\n\nNORA\nI didn't miss anything.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('.phx-connected')).toBeVisible();
}

async function createJourney(page, journey, name) {
  const key=await importProject(page,name,fixture);
  await createTask(page,key,journey);
  return key;
}

async function revealTechnical(locator) {
  await locator.waitFor({state:'attached'});
  await locator.evaluate(node=>{for(let parent=node.parentElement;parent;parent=parent.parentElement){if(parent.tagName==='DETAILS')parent.open=true}});
}

async function chooseRoute(page, runId) {
  await page.goto(`/p/${runId}/activity/task-1/decisions`);
  const route = page.getByRole('button', {name: /Commit now|route-a/i}).first();
  await expect(route).toBeVisible();
  await route.click();
}

async function waitForCandidate(page, runId, needle) {
  await page.goto(`/p/${runId}/changes/task-1`);
  await expect(page.locator('pre.script').last()).toContainText(needle, {timeout: 60_000});
}

test('U01 brief to checked opening candidate, export, canon base unchanged', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'opening', `u01-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'INT. LOCKED ROOM - NIGHT');
  await expect(page.locator('pre.script').first()).not.toContainText('INT. LOCKED ROOM - NIGHT');
  await expect(page.locator('p.status')).toContainText('stage: deliver', {timeout: 60_000});

  await page.goto(`/p/${runId}/exports/task-1`);
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

  await page.goto(`/p/${runId}/activity/task-1/decisions`);
  const approve = page.getByRole('button', {name: /Make this exact checked proposal current|Accept candidate|approve/i}).first();
  await expect(approve).toBeVisible({timeout: 60_000});
  await approve.click();
  await page.reload();
  await page.goto(`/p/${runId}/activity/task-1`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('.technical-details').evaluateAll(nodes=>nodes.forEach(node=>node.open=true));
  await revealTechnical(page.locator('pre').filter({hasText: '"outcome": "accepted"'}));
  await expect(page.locator('pre').filter({hasText: '"outcome": "accepted"'})).toBeVisible({timeout: 60_000});
  await page.goto(`/p/${runId}/exports/task-1`);
  await page.getByRole('button', {name: 'Publish / retry bundle'}).click();
  await expect(page.locator('p.status')).toContainText('completed accepted', {timeout: 60_000});
});

test('U03 selected-scene dialogue records configured service approval identity', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'dialogue', `u03-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'If you missed it, you were meant to.');
  await page.goto(`/p/${runId}/activity/task-1`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('.technical-details').evaluateAll(nodes=>nodes.forEach(node=>node.open=true));
  await revealTechnical(page.getByText(/demo-service/).first());
  await expect(page.getByText(/demo-service/).first()).toBeVisible({timeout: 60_000});
  await revealTechnical(page.locator('pre').filter({hasText: '"outcome": "accepted"'}));
  await expect(page.locator('pre').filter({hasText: '"outcome": "accepted"'})).toBeVisible({timeout: 60_000});
  await page.goto(`/p/${runId}/exports/task-1`);
  await page.getByRole('button', {name: 'Publish / retry bundle'}).click();
  await expect(page.locator('p.status')).toContainText('completed accepted', {timeout: 60_000});
});

test('U04 duplicate tabs replay exact decision and unauthenticated client is denied', async ({browser}) => {
  const context = await browser.newContext();
  const first = await context.newPage();
  await login(first);
  const runId = await createJourney(first, 'opening', `u04-${Date.now()}`);
  const second = await context.newPage();
  await first.goto(`/p/${runId}/activity/task-1/decisions`);
  await second.goto(`/p/${runId}/activity/task-1/decisions`);
  const one = first.getByRole('button', {name: /Commit now|route-a/i}).first();
  const two = second.getByRole('button', {name: /Commit now|route-a/i}).first();
  await expect(one).toBeVisible();
  await expect(two).toBeVisible();
  await Promise.allSettled([one.click({timeout:2000}), two.click({timeout:2000})]);
  await expect(second.getByText(/idempotent replay|conflict\/stale form|This decision changed|No pending decisions/i).first()).toBeVisible();

  const outsider = await browser.newPage();
  await outsider.goto(`/p/${runId}/activity/task-1`);
  await expect(outsider).toHaveURL(/\/login$/);
  await context.close();
});

test('U05 control, unknown-cost and failure semantics are visible and keyboard reachable', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'opening', `u05-${Date.now()}`);
  await page.goto(`/p/${runId}/activity/task-1`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('.technical-details').evaluateAll(nodes=>nodes.forEach(node=>node.open=true));
  await expect(page.getByRole('button', {name: 'Pause'})).toBeVisible();
  await expect(page.getByText(/Missing provider cost remains unknown/)).toBeVisible();
  await expect(page.locator('p.status[aria-live="polite"]')).toBeVisible();
  await page.keyboard.press('Tab');
  await expect(page.locator(':focus')).toBeVisible();
  await page.getByLabel('Confirm permanent stop').check();
  await page.getByRole('button', {name: 'Stop'}).click();
  await expect(page.locator('p[role=status]')).toContainText('Stop requested');
});

test('H03-H05 integrated analysis survives review reconnect and stays candidate-only', async ({page}) => {
  await login(page);
  const runId = await createJourney(page, 'analysis', `h03-${Date.now()}`);
  await chooseRoute(page, runId);
  await waitForCandidate(page, runId, 'If you missed it, you were meant to.');
  await expect(page.locator('p.status')).toContainText('stage: deliver', {timeout: 60_000});

  await expect(page.getByRole('heading', {name: 'Analysis before writing'}).first()).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Analysis of changes'}).first()).toBeVisible();
  await expect(page.getByText(/Status: (complete|partial)/).first()).toBeVisible({timeout: 60_000});
  await expect(page.getByRole('heading', {name: 'Story observations'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Required checks'})).toBeVisible();
  await revealTechnical(page.getByText(/revision_intelligence/).first());
  await expect(page.getByText(/revision_intelligence/).first()).toBeVisible();
  await expect(page.locator('pre.script').first()).toContainText("I didn't miss anything.");
  await expect(page.locator('pre.script').first()).not.toContainText('If you missed it, you were meant to.');

  await page.reload();
  await expect(page.getByText(/Status: (complete|partial)/).first()).toBeVisible({timeout: 60_000});
  await revealTechnical(page.getByText(/analysis_run_id/).first());
  await expect(page.getByText(/analysis_run_id/).first()).toBeVisible();

  await page.goto(`/p/${runId}/activity/task-1`);
  await expect(page.locator('.phx-connected')).toBeVisible();
  await page.locator('.technical-details').evaluateAll(nodes=>nodes.forEach(node=>node.open=true));
  await expect(page.getByText(/Analysis service:.*Deterministic Sandbox/)).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Analysis before writing'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Analysis of changes'})).toBeVisible();
});


test('Saved pages are available over HTTP without JavaScript', async ({browser}) => {
  const context=await browser.newContext(); const page=await context.newPage();
  await login(page);
  const key=await importProject(page,`http-reader-${Date.now()}`,fixture);
  const readerContext=await browser.newContext({javaScriptEnabled:false,storageState:await context.storageState()});
  const reader=await readerContext.newPage(); await reader.goto(`/p/${key}`);
  await expect(reader.locator('.screenplay')).toContainText('departure board');
  await readerContext.close(); await context.close();
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
