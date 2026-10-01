import {test, expect} from '@playwright/test';
import {readFileSync} from 'node:fs';
import {importProject, createTask} from './workspace_helpers.mjs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 06 Intelligence\nAuthor: Fount\n\nINT. KITCHEN - MORNING\n\nMARA sets an unopened envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board.\n\nNORA\nThe train is late.\n\nINT. INTERVIEW ROOM - LATER\n\nNora keeps her hands flat on the table.\n\nNORA\nI didn't miss anything.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Access token').fill(token);
  await page.getByRole('button', {name: /Sign in/}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createAnalysisRun(page, name) {
  const key = await importProject(page, name, fixture);
  await createTask(page, key, 'analysis');
  await page.goto(`/p/${key}/activity/task-1/decisions`);
  await page.getByRole('button', {name: /Commit now|route-a/i}).first().click();
  await page.goto(`/p/${key}/changes/task-1`);
  await expect(page.locator('pre.script').last()).toContainText('If you missed it, you were meant to.', {timeout: 60_000});
  return key;
}

test('A01-A07 saved intelligence is inspectable, bounded, accessible and revision-bound', async ({page}) => {
  await login(page);
  const runId = await createAnalysisRun(page, `phase06-intel-${Date.now()}`);

  await page.goto(`/p/${runId}/analysis/task-1`);
  await expect(page.getByRole('heading', {name: 'Phase 06 Intelligence'})).toBeVisible();
  await expect(page.getByText('Script analysis')).toBeVisible();
  await expect(page.getByText(/Browsing or comparing reports does not start AI work/)).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Required checks'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Revision checks'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Story observations'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Usage & reservations'})).toBeVisible();
  await expect(page.getByText(/not HTTP request counts/)).toBeVisible();
  await expect(page.getByText(/No quality ranking/)).toBeVisible();

  const graph = page.locator('#analysis-evidence-graph');
  if (await graph.count()) {
    await expect(graph).toBeVisible();
    await graph.focus();
    await page.keyboard.press('ArrowRight');
    await page.keyboard.press('+');
    await expect(graph).toHaveAttribute('data-graph-scale', /1\.(1[0-9]|2[0-9])/);
    await page.getByRole('button', {name: 'Zoom graph out'}).click();
    await page.getByRole('button', {name: 'Reset'}).click();
    await expect(graph).toHaveAttribute('data-graph-scale', '1.00');
    await expect(page.getByText('Accessible graph list')).toBeVisible();
  } else {
    await expect(page.getByText(/No saved story connections/)).toBeVisible();
  }

  const evidenceLink = page.getByRole('link', {name: 'Open exact recorded revision target'}).first();
  if (await evidenceLink.count()) {
    await evidenceLink.click();
    await expect(page).toHaveURL(new RegExp(`/p/${runId}/source/task-1\\?.*view=evidence%3A`));
    await expect(page.locator('.named-source-picker [aria-current=page]')).toContainText('Evidence');
  }

  await page.goto(`/p/${runId}/changes/task-1`);
  await expect(page.getByRole('heading', {name: 'Analysis of proposed changes'})).toBeVisible();
  await expect(page.getByText(/Story observations do not replace required checks/)).toBeVisible();
});

test('current project layout is responsive and writing remains source-first on narrow screens', async ({page}) => {
  await page.setViewportSize({width:480,height:900});
  await login(page);
  const key = await importProject(page, `phase06-style-${Date.now()}`, fixture);
  await page.goto(`/p/${key}/write`);
  await expect(page.locator('#source-editor')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
  await expect(page.locator('main')).toContainText('analysis remains tied to saved task sources');
});

const stored = () => JSON.parse(readFileSync(`${process.env.FOUNT_ARTIFACT_ROOT}/phase06-fixtures.json`, 'utf8'));

test('stored fixtures prove all states, finite graph controls, comparable history and exact finding navigation', async ({page}) => {
  const f = stored();
  await login(page);
  const inspect = async (packet, run = f.project_key) => {
    await page.goto(`/p/${run}/analysis/task-1?packet=${packet}`);
    await expect(page.locator('.analysis-mast__signals .ui-status')).toBeVisible();
  };
  for (const state of ['complete', 'partial', 'failed', 'running']) {
    await inspect(f[state]);
    await expect(page.locator('.analysis-mast__signals')).toContainText(state === 'running' ? 'not_run' : state);
  }
  await inspect(f.stale, f.stale_project_key);
  await expect(page.locator('.analysis-mast__signals')).toContainText('stale');
  await inspect("00000000-0000-4000-8000-000000000000");
  await expect(page.locator(".analysis-mast__signals")).toContainText("not_run");
  await expect(page.getByText("No saved story connections", {exact: true})).toBeVisible();
  await inspect(f.legacy);
  await page.locator('.analysis-rail details > summary').click();
  await expect(page.getByText('legacy / unavailable', {exact: true})).toBeVisible();
  await inspect(f.empty);
  await expect(page.getByText('No saved story connections', {exact: true})).toBeVisible();
  await expect(page.locator('#analysis-evidence-graph')).toHaveCount(0);
  await inspect(f.complete);
  const graph = page.locator('#analysis-evidence-graph');
  await expect(graph).toBeVisible();
  await expect(graph.locator('.graph-node')).toHaveCount(2);
  await expect(graph.locator('.graph-edge')).toHaveCount(1);
  await expect(page.locator('.graph-card table').first().locator('tbody tr')).toHaveCount(2);
  await expect(page.locator('.graph-card table').first().locator('tbody')).toContainText('evidence-complete');
  await expect(page.locator('.event-sequence li').first()).toContainText('Stored event complete');
  await graph.focus();
  await page.keyboard.press('ArrowRight');
  await expect(graph.locator('[data-graph-viewport]')).toHaveAttribute('transform', /translate\(-18 0\)/);
  await page.keyboard.press('+');
  await expect(graph).toHaveAttribute('data-graph-scale', '1.15');
  await page.getByRole('button', {name: 'Reset', exact: true}).click();
  const box = await graph.boundingBox();
  await page.mouse.move(box.x + 100, box.y + 100);
  await page.mouse.down();
  await page.mouse.move(box.x + 140, box.y + 125);
  await page.mouse.up();
  await expect(graph.locator('[data-graph-viewport]')).toHaveAttribute('transform', /translate\(40 25\)/);
  await page.getByRole('button', {name: 'Zoom graph in', exact: true}).click();
  await expect(graph).toHaveAttribute('data-graph-scale', '1.15');
  await page.getByRole('button', {name: 'Zoom graph out', exact: true}).click();
  await expect(graph).toHaveAttribute('data-graph-scale', '1.00');
  await expect(page.locator('.resource-row').filter({hasText: 'tokens'})).toContainText('consumed 60');
  await expect(page.locator('.resource-row').filter({hasText: 'tokens'})).toContainText('reserved/open 120');
  await expect(page.locator('.resource-row').filter({hasText: 'tokens'})).toContainText('unknown rows 2');
  await expect(page.locator('.resource-row').filter({hasText: 'tokens'})).toContainText('cost unknown for 3 row(s)');
  await page.getByRole('link', {name: 'Focus provenance here'}).click();
  await page.locator('.target-context summary').click();
  await expect(page.locator('.target-context')).toContainText(f.revision_id);
  await page.getByRole('link', {name: 'Open exact recorded revision target'}).click();
  await expect(page).toHaveURL(new RegExp(`view=evidence%3A${f.complete}%3A${f.revision_id}#scene-`));
  await expect(page.locator('.named-source-picker [aria-current=page]')).toContainText('Evidence');
  await page.goto(`/p/${f.project_key}/analysis/task-1?packet=${f.complete}&target=deleted-target`);
  await expect(page.locator('.target-context')).toContainText('Recorded target unresolved');
  await page.goto(`/p/${f.project_key}/source/task-1?view=evidence%3A${f.complete}%3A${f.revision_id}&target=deleted-target`);
  await expect(page.getByText(/Recorded target unresolved in this exact analysis evidence revision/)).toBeVisible();
  await inspect(f.oversized);
  await expect(page.getByText(/Showing up to 48 nodes and 96 links/)).toBeVisible();
  await expect(graph.locator('.graph-node')).toHaveCount(48);
  await expect(page.locator('.graph-card table').first().locator('tbody tr')).toHaveCount(48);
  await expect(page.locator('.event-sequence li')).toHaveCount(70);
  await expect(page.locator('.event-sequence li').first()).toContainText('Recorded event 1');
  await expect(page.locator('.event-sequence li').last()).toContainText('Recorded event 70');
  await page.getByLabel('Earlier / A').selectOption(f.left);
  await page.getByLabel('Later / B').selectOption(f.right);
  await page.getByRole('button', {name: 'Compare stored evidence'}).click();
  await expect(page.locator('[data-comparison-state]')).toHaveAttribute('data-comparison-state', 'comparable');
  const delta = page.locator('#analysis-comparison tr').filter({hasText: 'coverage.observed'});
  await expect(delta.locator('td')).toHaveText(['coverage.observed', '2', '5', '3']);
  await expect(page.locator('.comparison-uncertainty')).toContainText('Stored uncertainty');
  await page.getByLabel('Later / B').selectOption(f.other);
  await page.getByRole('button', {name: 'Compare stored evidence'}).click();
  await expect(page.locator('[data-comparison-state]')).toHaveAttribute('data-comparison-state', 'incomparable');
  await expect(page.locator('[data-comparison-state]')).toContainText('provider/model fingerprint');
});

for (const width of [1440, 480]) {
  test(`all current pages and authoring modes retain controls, focus and paper at ${width}px`, async ({page}) => {
    await page.setViewportSize({width, height: 1000});
    await page.emulateMedia({reducedMotion: 'reduce'});
    const check = async (name) => {
      const result = await page.evaluate(() => {
        const controls = [...document.querySelectorAll('button,input:not([type=hidden]),select,textarea')]
          .filter(el => el.getClientRects().length && getComputedStyle(el).visibility !== 'hidden');
        return {
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          clipped: controls.filter(el => { const r = el.getBoundingClientRect(); return r.left < -2 || r.right > innerWidth + 2; }).map(el => el.id || el.textContent),
          aggressiveLive: document.querySelectorAll('[aria-live="assertive"]').length,
          scroll: getComputedStyle(document.documentElement).scrollBehavior,
        };
      });
      expect(result.overflow, `${name} overflow`).toBeLessThanOrEqual(2);
      expect(result.clipped, `${name} controls`).toEqual([]);
      expect(result.aggressiveLive, `${name} live regions`).toBe(0);
      expect(result.scroll).toBe('auto');
      await page.keyboard.press('Tab');
      await expect(page.locator(':focus')).toBeVisible();
      const focus = await page.locator(':focus').evaluate(el => ({width: getComputedStyle(el).outlineWidth, style: getComputedStyle(el).outlineStyle}));
      expect(parseFloat(focus.width)).toBeGreaterThanOrEqual(2);
      expect(focus.style).not.toBe('none');
      await page.screenshot({path: `${process.env.FOUNT_ARTIFACT_ROOT}/layout-${width}-${name}.png`, fullPage: true});
    };
    await page.goto('/login');
    await check('login');
    await login(page);
    await expect(page.getByRole('button', {name: 'Sign out', exact: true})).toBeVisible();
    await check('projects');
    await page.goto('/new');
    await check('intake');
    const f = stored();
    for (const [section, path] of Object.entries({setup:'activity/task-1/setup',timeline:'activity/task-1',decisions:'activity/task-1/decisions',review:'changes/task-1',exports:'exports/task-1',viewer:'source/task-1',analysis:'analysis/task-1'})) {
      await page.goto(`/p/${f.project_key}/${path}?packet=${f.oversized}`);
      await expect(page.locator('main')).toBeVisible();
      await check(section);
    }
    await page.goto(`/p/${f.project_key}`);
    const paper = await page.locator('.screenplay').evaluate(el => ({background: getComputedStyle(el).backgroundColor, color: getComputedStyle(el).color, body: getComputedStyle(document.body).backgroundColor}));
    expect(paper.background).toBe('rgb(243, 239, 227)');
    expect(paper.color).toBe('rgb(23, 25, 20)');
    expect(paper.background).not.toBe(paper.body);
    await expect(page.locator('.screenplay .is-selected-scene')).toHaveCount(0);
    const blankHeight = await page.locator('.screenplay-element--blank').first().evaluate(el => el.getBoundingClientRect().height);
    expect(blankHeight).toBeLessThan(24);
    await page.goto(`/p/${f.project_key}/write`);
    for (const mode of ['Source', 'Pages', 'Source + pages']) {
      await page.getByRole('button', {name: mode, exact: true}).click();
      await check(mode.toLowerCase().replaceAll(' ','-'));
    }
    await page.getByRole('button', {name:'Source',exact:true}).click();
    const source = page.locator('#source-editor');
    await source.fill(`${await source.inputValue()}\nUnsaved local observation.\n`);
    await expect(page.locator('main')).toContainText('This unsaved draft has not been analyzed');
  });
}


test('saved intelligence and exact evidence viewer require authenticated ownership', async ({browser}) => {
  const f = stored();
  const outsider = await browser.newPage();
  for (const path of [
    `/p/${f.project_key}/analysis/task-1?packet=${f.complete}`,
    `/p/${f.project_key}/source/task-1?view=evidence%3A${f.complete}%3A${f.revision_id}`,
  ]) {
    await outsider.goto(path);
    await expect(outsider).toHaveURL(/\/login$/);
    await expect(outsider.getByText('Stored finding complete', {exact: true})).toHaveCount(0);
  }
  await outsider.close();
});


test('named exact evidence source survives the initial LiveView connection', async ({browser}) => {
  const context = await browser.newContext();
  let connect;
  await context.routeWebSocket('**/live/websocket**', socket => { connect = () => socket.connectToServer(); });
  const page = await context.newPage();
  await login(page);
  const f = stored();
  const selected = `evidence:${f.complete}:${f.revision_id}`;
  await page.goto(`/p/${f.project_key}/source/task-1?view=${encodeURIComponent(selected)}`);
  await expect(page.locator('.named-source-picker [aria-current=page]')).toContainText('Evidence');
  connect();
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page.locator('.named-source-picker [aria-current=page]')).toContainText('Evidence');
  await page.locator('.technical-details summary').click();
  await expect(page.locator('.technical-details')).toContainText(f.revision_id);
  await context.close();
});
