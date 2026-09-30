import {test, expect} from '@playwright/test';
import {readFileSync} from 'node:fs';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 06 Intelligence\nAuthor: Fount\n\nINT. KITCHEN - MORNING\n\nMARA sets an unopened envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board.\n\nNORA\nThe train is late.\n\nINT. INTERVIEW ROOM - LATER\n\nNora keeps her hands flat on the table.\n\nNORA\nI didn't miss anything.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Owner token').fill(token);
  await page.getByRole('button', {name: /Sign in/}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createAnalysisRun(page, key) {
  await page.goto('/projects/new');
  await page.getByLabel('Project title').fill('Phase 06 Intelligence');
  await page.getByLabel('Project key').fill(key);
  await page.getByLabel('Journey').selectOption('analysis');
  await page.getByLabel('Or Fountain source').fill(fixture);
  await page.getByRole('button', {name: 'Create Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  const match = page.url().match(/\/runs\/([0-9a-f-]+)\/setup$/);
  expect(match).toBeTruthy();
  const runId = match[1];
  await page.getByRole('button', {name: 'Launch / resume durable worker'}).click();
  await page.goto(`/runs/${runId}/decisions`);
  const route = page.getByRole('button', {name: /Commit now|route-a/i}).first();
  await expect(route).toBeVisible({timeout: 60_000});
  await route.click();
  await page.goto(`/runs/${runId}/review`);
  await expect(page.locator('pre.script').last()).toContainText('If you missed it, you were meant to.', {timeout: 60_000});
  return runId;
}

test('A01-A07 saved intelligence is inspectable, bounded, accessible and revision-bound', async ({page}) => {
  await login(page);
  const runId = await createAnalysisRun(page, `phase06-intel-${Date.now()}`);

  await page.goto(`/runs/${runId}/analysis`);
  await expect(page.getByRole('heading', {name: 'Phase 06 Intelligence'})).toBeVisible();
  await expect(page.getByText('Persisted evidence console')).toBeVisible();
  await expect(page.getByText(/Inspection reads saved rows only/)).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Authoritative required checks'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Workshop application checks'})).toBeVisible();
  await expect(page.getByRole('heading', {name: 'Semantic advisory findings'})).toBeVisible();
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
    await expect(page.getByText(/No stored graph records/)).toBeVisible();
  }

  const evidenceLink = page.getByRole('link', {name: 'Open exact recorded revision target'}).first();
  if (await evidenceLink.count()) {
    await evidenceLink.click();
    await expect(page).toHaveURL(new RegExp(`/runs/${runId}/viewer\\?.*view=evidence%3A`));
    await expect(page.getByText(/Read-only analysis evidence revision/)).toBeVisible();
  }

  await page.goto(`/runs/${runId}/review`);
  await expect(page.getByRole('heading', {name: 'Revision intelligence beside the candidate'})).toBeVisible();
  await expect(page.getByText(/Advisory confidence never changes required checks/)).toBeVisible();
});

test('site-wide signal-room layout is dense, responsive and does not overflow narrow screens', async ({page}) => {
  await page.setViewportSize({width: 480, height: 900});
  await login(page);
  await expect(page.locator('.system-rail')).toBeVisible();
  await expect(page.locator('.project-shell')).toBeVisible();

  await page.goto('/projects/new');
  await expect(page.locator('.project-create')).toBeVisible();
  const layout = await page.evaluate(() => ({
    width: document.documentElement.clientWidth,
    scroll: document.documentElement.scrollWidth,
    background: getComputedStyle(document.body).backgroundColor,
    rail: getComputedStyle(document.querySelector('.system-rail')).position,
  }));
  expect(layout.scroll).toBeLessThanOrEqual(layout.width + 2);
  expect(layout.rail).toBe('sticky');
  expect(layout.background).not.toBe('rgb(255, 255, 255)');

  const key = `phase06-style-${Date.now()}`;
  await page.getByLabel('Project key').fill(key);
  await page.getByLabel('Or Fountain source').fill(fixture);
  await page.getByRole('button', {name: 'Create Run'}).click();
  const runId = page.url().match(/\/runs\/([0-9a-f-]+)\/setup$/)[1];
  await page.goto(`/runs/${runId}/edit`);
  await expect(page.locator('.authoring-grid')).toBeVisible();
  await expect(page.getByText(/Analysis evidence:/)).toBeVisible();
  const editorOverflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(editorOverflow).toBeLessThanOrEqual(2);
});

const stored = () => JSON.parse(readFileSync(`${process.env.FOUNT_ARTIFACT_ROOT}/phase06-fixtures.json`, 'utf8'));

test('stored fixtures prove all states, finite graph controls, comparable history and exact finding navigation', async ({page}) => {
  const f = stored();
  await login(page);
  const inspect = async (packet, run = f.run_id) => {
    await page.goto(`/runs/${run}/analysis?packet=${packet}`);
    await expect(page.locator('.analysis-mast__signals .ui-status')).toBeVisible();
  };
  for (const state of ['complete', 'partial', 'failed', 'running']) {
    await inspect(f[state]);
    await expect(page.locator('.analysis-mast__signals')).toContainText(state === 'running' ? 'not_run' : state);
  }
  await inspect(f.stale, f.stale_run_id);
  await expect(page.locator('.analysis-mast__signals')).toContainText('stale');
  await inspect("00000000-0000-4000-8000-000000000000");
  await expect(page.locator(".analysis-mast__signals")).toContainText("not_run");
  await expect(page.getByText("No stored graph records", {exact: true})).toBeVisible();
  await inspect(f.legacy);
  await expect(page.getByText('legacy / unavailable', {exact: true})).toBeVisible();
  await inspect(f.empty);
  await expect(page.getByText('No stored graph records', {exact: true})).toBeVisible();
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
  await expect(page.locator('.target-context')).toContainText(f.revision_id);
  await page.getByRole('link', {name: 'Open exact recorded revision target'}).click();
  await expect(page).toHaveURL(new RegExp(`view=evidence%3A${f.complete}%3A${f.revision_id}#scene-`));
  await expect(page.getByText(/Read-only analysis evidence revision/)).toBeVisible();
  await page.goto(`/runs/${f.run_id}/analysis?packet=${f.complete}&target=deleted-target`);
  await expect(page.locator('.target-context')).toContainText('Recorded target unresolved');
  await page.goto(`/runs/${f.run_id}/viewer?view=evidence%3A${f.complete}%3A${f.revision_id}&target=deleted-target`);
  await expect(page.getByText(/Recorded target unresolved in this exact analysis evidence revision/)).toBeVisible();
  await inspect(f.oversized);
  await expect(page.getByText(/View bounded to 48 nodes and 96 links/)).toBeVisible();
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
    await page.goto('/projects/new');
    await check('intake');
    const f = stored();
    for (const section of ['setup', 'timeline', 'decisions', 'review', 'exports', 'viewer', 'analysis']) {
      await page.goto(`/runs/${f.run_id}/${section}?packet=${f.oversized}`);
      await expect(page.locator('main')).toBeVisible();
      await check(section);
    }
    await page.goto(`/runs/${f.run_id}/viewer`);
    const paper = await page.locator('.screenplay').evaluate(el => ({background: getComputedStyle(el).backgroundColor, color: getComputedStyle(el).color, body: getComputedStyle(document.body).backgroundColor}));
    expect(paper.background).toBe('rgb(242, 238, 227)');
    expect(paper.color).toBe('rgb(23, 24, 23)');
    expect(paper.background).not.toBe(paper.body);
    await expect(page.locator('.screenplay .is-selected-scene')).toHaveCount(0);
    const blankHeight = await page.locator('.screenplay-element--blank').first().evaluate(el => el.getBoundingClientRect().height);
    expect(blankHeight).toBeLessThan(24);
    await page.goto(`/runs/${f.run_id}/edit`);
    for (const mode of ['Editor', 'Preview', 'Split']) {
      await page.getByRole('button', {name: mode, exact: true}).click();
      await check(mode.toLowerCase());
    }
    const source = page.getByLabel('Fountain screenplay source');
    await source.fill(`${await source.inputValue()}\nUnsaved local observation.\n`);
    await expect(page.locator('.analysis-draft-marker')).toContainText('unsaved local draft is unanalyzed');
  });
}


test('saved intelligence and exact evidence viewer require authenticated ownership', async ({browser}) => {
  const f = stored();
  const outsider = await browser.newPage();
  for (const path of [
    `/runs/${f.run_id}/analysis?packet=${f.complete}`,
    `/runs/${f.run_id}/viewer?view=evidence%3A${f.complete}%3A${f.revision_id}`,
  ]) {
    await outsider.goto(path);
    await expect(outsider).toHaveURL(/\/login$/);
    await expect(outsider.getByText('Stored finding complete', {exact: true})).toHaveCount(0);
  }
  await outsider.close();
});


test('native exact revision selection survives the initial LiveView connection', async ({browser}) => {
  const context = await browser.newContext();
  let connect;
  await context.routeWebSocket('**/live/websocket**', socket => {
    connect = () => socket.connectToServer();
  });
  const page = await context.newPage();
  await login(page);
  const f = stored();
  await page.goto(`/runs/${f.run_id}/viewer`);
  const selected = `evidence:${f.complete}:${f.revision_id}`;
  await page.getByLabel('Displayed revision').selectOption(selected);
  connect();
  await expect(page.locator('.phx-connected')).toBeVisible();
  await expect(page.getByLabel('Displayed revision')).toHaveValue(selected);
  await page.getByRole('button', {name: 'Apply view'}).click();
  await expect(page.getByText(/Read-only analysis evidence revision/)).toBeVisible();
  await context.close();
});
