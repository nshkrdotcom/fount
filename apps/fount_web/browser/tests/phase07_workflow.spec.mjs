import {test, expect} from '@playwright/test';

const token = process.env.FOUNT_OWNER_TOKEN || 'browser-owner-token';
const fixture = `Title: Phase 07 Browser Fixture\nAuthor: Fount\n\nINT. KITCHEN - MORNING\n\nMARA sets an envelope beside the coffee maker.\n\nMARA\nI said I would wait.\n\nEXT. TRAIN PLATFORM - NIGHT\n\nNORA waits under the departure board.\n\nNORA\nThe train is late.\n\nOWEN\nThat's what you wanted.\n`;

async function login(page) {
  await page.goto('/login');
  await page.getByLabel('Owner token').fill(token);
  await page.getByRole('button', {name: 'Sign in'}).click();
  await expect(page).toHaveURL(/\/$/);
}

async function createRun(page, key, launch = false) {
  await page.goto('/projects/new');
  await page.getByLabel('Project title').fill('Phase 07 Browser');
  await page.getByLabel('Project key').fill(key);
  await page.getByLabel('Journey').selectOption('opening');
  await page.getByLabel('Or Fountain source').fill(fixture);
  await page.getByRole('button', {name: 'Create Run'}).click();
  await expect(page).toHaveURL(/\/runs\/[0-9a-f-]+\/setup$/);
  const runId = page.url().match(/\/runs\/([0-9a-f-]+)\/setup$/)[1];
  if (launch) await page.getByRole('button', {name: 'Launch / resume durable worker'}).click();
  return runId;
}

async function selectTwoScenes(page, runId) {
  await page.goto(`/runs/${runId}/viewer`);
  await expect(page.getByRole('heading', {name: 'Revision-bound workflow scope'})).toBeVisible();
  await page.locator('input[name="scope[whole_screenplay]"]').uncheck();
  const scenes = page.locator('input[name="scope[scene_ids][]"]');
  await expect(scenes).toHaveCount(2);
  await scenes.nth(0).check();
  await scenes.nth(1).check();
  await page.getByRole('button', {name: 'Save exact scope'}).click();
  await expect(page.getByText(/Workflow scope saved against the exact Run base revision/)).toBeVisible();
  await page.reload();
  await expect(page.getByLabel('Selected workflow scope')).toContainText('fingerprint');
}

test('W01-W03 expose validated policy, closed actions and persistent exact-base visual scope', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `w01-${Date.now()}`);

  for (const gate of ['investigation_scope', 'strategy_choice', 'candidate_generation', 'iteration']) {
    await expect(page.locator(`select[name="policy[${gate}]"]`)).toBeVisible();
  }
  await expect(page.getByText(/Max microunits/)).toBeVisible();
  await expect(page.getByText(/Authenticated owner/)).toBeVisible();
  await expect(page.getByText(/Unknown provider cost stays unknown/)).toBeVisible();
  await page.getByLabel('Route').selectOption('registered_reviewer');
  await page.getByLabel('Registered route reviewer').selectOption('owner');
  await page.getByRole('button', {name: 'Append validated policy snapshot'}).click();
  await expect(page.getByText(/Policy snapshot updated/)).toBeVisible();

  await page.getByLabel('Preset name').fill('Browser preset');
  await page.getByRole('button', {name: 'Save current policy'}).click();
  await expect(page.getByText(/Saved host preset Browser preset v1/)).toBeVisible();

  const investigate = page.locator('.action-card').filter({hasText: 'Investigate'});
  await expect(investigate).toContainText('unavailable through Run');
  await expect(investigate).toContainText('not promoted to a Run action');

  await selectTwoScenes(page, runId);
  await page.goto(`/runs/${runId}/setup`);
  await expect(page.getByRole('heading', {name: 'Revision-bound workflow scope'})).toBeVisible();
  await page.getByLabel('Action').selectOption('pass');
  await page.getByLabel('Instruction').fill('Sharpen the selected dialogue without changing scope.');
  await page.getByRole('button', {name: 'Validate launch preview'}).click();
  await expect(page.getByRole('heading', {name: 'Validated launch preview'})).toBeVisible();
  await expect(page.getByText(/request_fingerprint/)).toBeVisible();
});

test('W05 lifecycle buttons reflect durable permitted states and no restart surface exists', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `w05-${Date.now()}`);
  await page.goto(`/runs/${runId}/timeline`);

  await expect(page.getByRole('button', {name: 'Pause'})).toBeEnabled();
  await expect(page.getByRole('button', {name: 'Resume'})).toBeDisabled();
  await page.getByRole('button', {name: 'Pause'}).click();
  await expect(page.getByRole('button', {name: 'Resume'})).toBeEnabled();
  await page.reload();
  await expect(page.getByText(/Run is paused; resume is the supported continuation/)).toBeVisible();
  await page.getByRole('button', {name: 'Resume'}).click();
  await page.getByLabel('Confirm permanent stop and fencing').check();
  await page.getByRole('button', {name: 'Stop'}).click();
  await expect(page.getByText(/restart-from-stage is not supported/)).toBeVisible();
  await expect(page.getByRole('button', {name: 'Ensure worker is running'})).toBeDisabled();
  await expect(page.getByText(/lock\/fencing version/)).toBeVisible();
});

test('W06-W07 supported export options, finite multi-launch, partial-safe identities and bounded registry are visible', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `w07-${Date.now()}`);
  await selectTwoScenes(page, runId);
  await page.goto(`/runs/${runId}/setup`);
  await page.getByLabel('Action').selectOption('develop');
  await page.getByLabel('Instruction').fill('Make two independent target Runs.');
  await page.getByText(/Launch one independent Run per selected target/).locator('input').check();
  await page.getByRole('button', {name: 'Validate launch preview'}).click();
  await expect(page.locator('.launch-entry')).toHaveCount(2);
  await page.getByRole('button', {name: 'Create these independent Runs'}).click();
  await expect(page.getByText(/2 created\/replayed · 0 failed/)).toBeVisible();

  await page.goto('/');
  await expect(page.getByRole('heading', {name: 'Runs'})).toBeVisible();
  await expect(page.locator('.run-registry tbody tr')).toHaveCount(3);
  await expect(page.getByRole('button', {name: 'Compare persisted facts'})).toBeVisible();

  await page.goto(`/runs/${runId}/exports`);
  await expect(page.getByText(/Optional formats are only PDF and table-read/)).toBeVisible();
  await expect(page.getByText(/explicitly fails\/partials/)).toBeVisible();
  await expect(page.locator('input[name="export[pdf]"]')).toBeVisible();
  await expect(page.locator('input[name="export[table_read]"]')).toBeVisible();
  await expect(page.getByText('DOCX')).toHaveCount(0);
});

test('W04-W08 decision binding and notification resynchronize from persisted state and remain session-local', async ({page}) => {
  await login(page);
  const runId = await createRun(page, `w08-${Date.now()}`, true);
  await page.goto(`/runs/${runId}/decisions`);

  await expect(page.getByText(/decision_required/)).toBeVisible({timeout: 60_000});
  await expect(page.getByRole('heading', {name: 'Exact decision / approval binding'}).first()).toBeVisible();
  await expect(page.getByText(/Intelligence lineage/).first()).toBeVisible();
  const unread = page.getByText(/Session notifications · [1-9][0-9]* unread/);
  await expect(unread).toBeVisible();
  await page.getByRole('button', {name: 'Mark current notices read'}).click();
  await expect(page.getByText('Session notifications · 0 unread')).toBeVisible();

  await page.reload();
  await expect(page.getByText(/decision_required/)).toBeVisible({timeout: 30_000});
  await expect(page.getByText(/Session notifications · [1-9][0-9]* unread/)).toBeVisible();

  const outsiderContext = await page.context().browser().newContext();
  const outsider = await outsiderContext.newPage();
  await outsider.goto(`/runs/${runId}/decisions`);
  await expect(outsider).toHaveURL(/\/login$/);
  await outsiderContext.close();
});

test('Phase 07 controls remain keyboard-readable at 480px with reduced motion and non-color states', async ({page}) => {
  await page.setViewportSize({width: 480, height: 900});
  await page.emulateMedia({reducedMotion: 'reduce'});
  await login(page);
  await createRun(page, `w480-${Date.now()}`);

  await expect(page.getByText('unavailable through Run').first()).toBeVisible();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(1);
  await page.keyboard.press('Tab');
  await expect(page.locator(':focus')).toBeVisible();
});
