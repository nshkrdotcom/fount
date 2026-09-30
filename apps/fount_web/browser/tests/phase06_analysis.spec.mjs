import {test, expect} from '@playwright/test';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 06 Intelligence\nAuthor: Fount\n\nINT. KITCHEN - MORNING\n\nMARA sets an unopened envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board.\n\nNORA\nThe train is late.\n`;

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
    await expect(page).toHaveURL(new RegExp(`/runs/${runId}/viewer\\?view=evidence%3A`));
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
